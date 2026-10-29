--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controllers = script.Parent:WaitForChild("Controllers")
local UIController = require(Controllers:WaitForChild("UIController"))
local InputController = require(Controllers:WaitForChild("InputController"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRequest = remotes:WaitForChild("ActionRequest") :: RemoteEvent
local actionResult = remotes:WaitForChild("ActionResult") :: RemoteEvent
local stateDelta = remotes:WaitForChild("StateDelta") :: RemoteEvent
local snapshotRequest = remotes:WaitForChild("SnapshotRequest") :: RemoteEvent
local stateSnapshot = remotes:WaitForChild("StateSnapshot") :: RemoteEvent

local ui = UIController.new(player)
local sessionId = game:GetService("HttpService"):GenerateGUID(false)
local requestSequence = 0
local protocolVersion = 1
local runId: string? = nil
local revision = -1
local state: any = nil
local waitingForSnapshot = false

local pending: {[string]: string} = {}
local targetId: string? = nil
local heldAction: string? = nil
local disposed = false

local function render()
	ui:Render(state, targetId, pending)
end

local function requestSnapshot()
	if waitingForSnapshot or disposed then return end
	waitingForSnapshot = true
	local function retry()
		if disposed or not waitingForSnapshot then return end
		snapshotRequest:FireServer({ protocolVersion = protocolVersion, runId = runId, lastRevision = math.max(revision, 0) })
		task.delay(2.5, retry)
	end
	retry()
end

local function newRequest(): string
	requestSequence += 1
	return string.format("%s:%d", sessionId, requestSequence)
end

local function sendAction(action: string, payload: {[string]: any})
	if not state or not runId then
		ui:Notice("En attente de l'état du serveur")
		return
	end
	local requestId = newRequest()
	pending[requestId] = action
	ui:Notice("En attente de confirmation : " .. action)
	actionRequest:FireServer({
		protocolVersion = protocolVersion,
		runId = runId,
		requestId = requestId,
		action = action,
		expectedEntityRevisions = {},
		payload = payload,
	})
	render()
end

local function sendContextAction()
	if not state then
		ui:Notice("En attente de l'état du serveur")
		return
	end
	if not targetId then
		ui:Notice("Aucune cible : approchez-vous d'une station (12 studs max)")
		return
	end
	local station
	for _, candidate in state.stations or {} do
		if candidate.id == targetId then station = candidate; break end
	end
	if not station then return end
	local me = state.players and state.players[tostring(player.UserId)]
	local held = me and me.heldItem
	local action: string?
	if station.kind == "Table" then
		if station.state == "DirtyPlate" and not held then action = "PickUp"
		elseif held == "Salad" then action = "Serve"
		else action = "TakeOrder" end
	elseif station.kind == "Board" and station.state == "Lettuce" and not held then
		action = "BeginWork"
	elseif station.kind == "Sink" and station.state == "DirtyPlate" and not held then
		action = "BeginWork"
	elseif held then
		action = "PutDown"
	else
		action = "PickUp"
	end
	if action == "BeginWork" then
		-- Context is a single tap; work must be held with F, the work button, or R2.
		ui:Notice("Maintenez Travailler pour terminer cette étape")
	else
		sendAction(action, { targetId = targetId })
	end
end

local function perform(action: string)
	if action == "Context" then
		sendContextAction()
		return
	end
	if action == "EndWork" then
		if heldAction == "BeginWork" then
			heldAction = nil
			sendAction("EndWork", {})
		end
		return
	end
	if action == "SetReady" then
		local userId = tostring(player.UserId)
		local currentlyReady = state and state.readyPlayers and state.readyPlayers[userId] == true
		sendAction("SetReady", { ready = not currentlyReady })
	elseif action == "PickUp" or action == "PutDown" or action == "BeginWork" or action == "TakeOrder" or action == "Serve" then
		if targetId then
			if action == "BeginWork" and state then heldAction = action end
			sendAction(action, { targetId = targetId })
		else
			ui:Notice("Aucune cible : approchez-vous d'une station (12 studs max)")
		end
	elseif action == "NextDay" then
		sendAction(action, {})
	end
end

local input = InputController.new(player, function(action) perform(action) end, function(id) targetId = id; render() end)
ui:SetActionCallback(function(action) perform(action) end)
ui:SetTargetCallback(function() return targetId end)

local connections: {RBXScriptConnection} = {}
table.insert(connections, actionResult.OnClientEvent:Connect(function(result: any)
	if typeof(result) ~= "table" or typeof(result.requestId) ~= "string" then return end
	local action = pending[result.requestId]
	if not action then return end
	pending[result.requestId] = nil
	if result.status == "Accepted" then
		ui:Notice(action .. " confirmé (révision " .. tostring(result.committedRevision) .. ")")
	elseif result.status == "Rejected" then
		ui:Notice(action .. " refusé : " .. tostring(result.code))
	else
		ui:Notice("Réponse serveur invalide")
	end
	render()
end))

table.insert(connections, stateSnapshot.OnClientEvent:Connect(function(message: any)
	if typeof(message) ~= "table" or typeof(message.runId) ~= "string" or typeof(message.revision) ~= "number" then return end
	if typeof(message.snapshotId) ~= "string" or typeof(message.chunkIndex) ~= "number" or typeof(message.chunkCount) ~= "number" then return end
	if message.chunkCount < 1 or message.chunkCount > 128 or message.chunkIndex < 1 or message.chunkIndex > message.chunkCount then return end
	if message.chunkCount ~= 1 then
		ui:Notice("Snapshot fragmenté non pris en charge par ce contrat de slice")
		waitingForSnapshot = false
		return
	end
	if typeof(message.stateChunk) ~= "table" then return end
	if message.runId == runId and message.revision < revision then
		waitingForSnapshot = false
		return
	end
	if message.runId ~= runId then table.clear(pending) end
	runId = message.runId
	revision = message.revision
	state = message.stateChunk
	waitingForSnapshot = false
	render()
end))

table.insert(connections, stateDelta.OnClientEvent:Connect(function(message: any)
	if typeof(message) ~= "table" or typeof(message.runId) ~= "string" or typeof(message.baseRevision) ~= "number" or typeof(message.revision) ~= "number" or typeof(message.changes) ~= "table" then return end
	if state and message.runId == runId and message.revision <= revision then return end
	if not state or message.runId ~= runId or message.baseRevision ~= revision then
		requestSnapshot()
		return
	end
	local snapshot = message.changes.snapshot
	if typeof(snapshot) ~= "table" then
		requestSnapshot()
		return
	end
	state = snapshot
	revision = message.revision
	render()
end))

local function cleanup()
	if disposed then return end
	disposed = true
	if heldAction then
		heldAction = nil
		if runId then
			requestSequence += 1
			actionRequest:FireServer({ protocolVersion = protocolVersion, runId = runId, requestId = string.format("%s:%d", sessionId, requestSequence), action = "EndWork", expectedEntityRevisions = {}, payload = {} })
		end
	end
	input:Destroy()
	ui:Destroy()
	for _, connection in connections do connection:Disconnect() end
end

table.insert(connections, player.CharacterRemoving:Connect(function()
	if heldAction then perform("EndWork") end
end))
table.insert(connections, script.Destroying:Connect(cleanup))
requestSnapshot()
render()
