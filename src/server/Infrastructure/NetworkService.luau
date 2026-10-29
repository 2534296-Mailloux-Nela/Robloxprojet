--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Protocol"))

local NetworkService = {}
NetworkService.__index = NetworkService

local ACTION_RATE = 10
local ACTION_BURST = 20
local SNAPSHOT_INTERVAL = 2
local CACHE_LIMIT = 256
local MAX_SNAPSHOT_BYTES = 32768

type Result = { requestId: string, status: string, code: string, committedRevision: number }
type Cached = { fingerprint: string, result: Result }
type Peer = { tokens: number, lastRefill: number, snapshotAt: number, cache: { [string]: Cached }, order: { string }, session: string?, highestSequence: number }
type GameService = {
	getSnapshot: (self: any, player: Player) -> { [string]: any },
	handleAction: (self: any, player: Player, action: string, payload: any) -> (boolean, string),
	onStateChanged: (() -> ())?,
}

local function fingerprint(request: { [string]: any }): string
	local payload = request.payload
	return request.runId .. ":" .. request.action .. ":" .. tostring(payload.targetId or payload.ready or "")
end

function NetworkService.new(remotes: Folder, service: GameService)
	local self = setmetatable({}, NetworkService)
	self.service = service
	self.actionRequest = remotes:WaitForChild("ActionRequest") :: RemoteEvent
	self.actionResult = remotes:WaitForChild("ActionResult") :: RemoteEvent
	self.stateDelta = remotes:WaitForChild("StateDelta") :: RemoteEvent
	self.snapshotRequest = remotes:WaitForChild("SnapshotRequest") :: RemoteEvent
	self.stateSnapshot = remotes:WaitForChild("StateSnapshot") :: RemoteEvent
	self.peers = {} :: { [Player]: Peer }
	self.connections = {} :: { RBXScriptConnection }
	self.revision = 0
	self.publishedRevision = 0
	self.pending = false
	self.closed = false
	return self
end

function NetworkService:_peer(player: Player): Peer
	local peer = self.peers[player]
	if peer == nil then
		peer = { tokens = ACTION_BURST, lastRefill = os.clock(), snapshotAt = -math.huge, cache = {}, order = {}, session = nil, highestSequence = 0 }
		self.peers[player] = peer
	end
	return peer
end

function NetworkService:_snapshot(player: Player): { [string]: any }?
	local ok, state = pcall(self.service.getSnapshot, self.service, player)
	if not ok or type(state) ~= "table" or type(state.runId) ~= "string" then
		warn("Restaurant: GameService snapshot unavailable", state)
		return nil
	end
	local encoded, json = pcall(HttpService.JSONEncode, HttpService, state)
	if not encoded or #json > MAX_SNAPSHOT_BYTES then
		warn("Restaurant: snapshot exceeds slice budget")
		return nil
	end
	return state
end

function NetworkService:_publish()
	if self.closed or self.revision == self.publishedRevision then
		return
	end
	local base = self.publishedRevision
	local revision = self.revision
	for _, player in Players:GetPlayers() do
		local state = self:_snapshot(player)
		if state then
			self.stateDelta:FireClient(player, {
				runId = state.runId,
				baseRevision = base,
				revision = revision,
				changes = { snapshot = state },
			})
		end
	end
	self.publishedRevision = revision
end

function NetworkService:changed()
	if self.closed then
		return
	end
	self.revision += 1
	if self.pending then
		return
	end
	self.pending = true
	task.delay(0.1, function()
		self.pending = false
		self:_publish()
	end)
end

function NetworkService:_sendSnapshot(player: Player)
	local state = self:_snapshot(player)
	if state == nil then
		return
	end
	self.stateSnapshot:FireClient(player, {
		runId = state.runId,
		snapshotId = HttpService:GenerateGUID(false),
		revision = self.revision,
		chunkIndex = 1,
		chunkCount = 1,
		stateChunk = state,
	})
end

function NetworkService:_action(player: Player, request: unknown)
	if player.Parent ~= Players then
		return
	end
	local peer = self:_peer(player)
	local requestId = if type(request) == "table" and type(request.requestId) == "string" and #request.requestId <= 80 then request.requestId else ""
	local function reject(code: string)
		self.actionResult:FireClient(player, { requestId = requestId, status = "Rejected", code = code, committedRevision = self.revision })
	end
	local now = os.clock()
	peer.tokens = math.min(ACTION_BURST, peer.tokens + (now - peer.lastRefill) * ACTION_RATE)
	peer.lastRefill = now
	if peer.tokens < 1 then
		reject("RateLimited")
		return
	end
	peer.tokens -= 1
	local state = self:_snapshot(player)
	if state == nil then
		reject("PersistenceUnavailable")
		return
	end
	local valid, code = Protocol.validateAction(request, state.runId)
	if not valid then
		reject(code)
		return
	end
	local envelope = request :: { [string]: any }
	local key = envelope.requestId :: string
	local signature = fingerprint(envelope)
	local previous = peer.cache[key]
	if previous ~= nil then
		if previous.fingerprint == signature then
			self.actionResult:FireClient(player, previous.result)
		else
			reject("InvalidPayload")
		end
		return
	end
	local session, sequenceText = string.match(key, "^([%w_%-]+):([1-9]%d*)$")
	local sequence = if sequenceText then tonumber(sequenceText) else nil
	if session == nil or sequence == nil or sequence > 9007199254740991 or (peer.session ~= nil and peer.session ~= session) or sequence <= peer.highestSequence then
		reject("StaleRevision")
		return
	end
	peer.session = session
	peer.highestSequence = sequence
	-- GameService owns participation, world range and atomic mutations; never trust payload as state.
	local before = self.revision
	local ok, accepted, reason = pcall(self.service.handleAction, self.service, player, envelope.action, envelope.payload)
	if not ok then
		warn("Restaurant: GameService action failed", accepted)
		reject("InvalidPayload")
		return
	end
	if accepted and self.revision == before then
		self:changed()
	end
	local result: Result = {
		requestId = key,
		status = if accepted then "Accepted" else "Rejected",
		code = if accepted then "OK" else (if type(reason) == "string" then reason else "InvalidPayload"),
		committedRevision = self.revision,
	}
	peer.cache[key] = { fingerprint = signature, result = result }
	table.insert(peer.order, key)
	if #peer.order > CACHE_LIMIT then
		local oldest = table.remove(peer.order, 1)
		if oldest then
			peer.cache[oldest] = nil
		end
	end
	self.actionResult:FireClient(player, result)
end

function NetworkService:_snapshotRequest(player: Player, request: unknown)
	if player.Parent ~= Players then
		return
	end
	local peer = self:_peer(player)
	local valid = Protocol.validateSnapshotRequest(request)
	if not valid then
		return
	end
	local now = os.clock()
	if now - peer.snapshotAt < SNAPSHOT_INTERVAL then
		return
	end
	peer.snapshotAt = now
	self:_sendSnapshot(player)
end

function NetworkService:start()
	table.insert(self.connections, self.actionRequest.OnServerEvent:Connect(function(player, request)
		self:_action(player, request)
	end))
	table.insert(self.connections, self.snapshotRequest.OnServerEvent:Connect(function(player, request)
		self:_snapshotRequest(player, request)
	end))
	table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
		-- GameService registered first; defer until its participant record exists.
		task.defer(function()
			if not self.closed and player.Parent == Players then self:_sendSnapshot(player) end
		end)
	end))
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		self.peers[player] = nil
	end))
	for _, player in Players:GetPlayers() do
		self:_sendSnapshot(player)
	end
end

function NetworkService:stop()
	self.closed = true
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.peers)
end

return NetworkService
