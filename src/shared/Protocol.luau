--!strict
-- Transport schema for the bounded restaurant vertical slice (version 1).
local Protocol = {}

Protocol.VERSION = 1

local ACTIONS: { [string]: { [string]: string } } = {
	SetReady = { ready = "boolean" },
	PickUp = { targetId = "string" },
	PutDown = { targetId = "string" },
	BeginWork = { targetId = "string" },
	EndWork = {},
	TakeOrder = { targetId = "string" },
	Serve = { targetId = "string" },
	NextDay = {},
}

local function identifier(value: unknown, limit: number): boolean
	return type(value) == "string" and #value > 0 and #value <= limit and string.match(value, "^[%w_%-]+$") ~= nil
end

local function revision(value: unknown): boolean
	return type(value) == "number" and value >= 0 and value <= 2147483647 and value % 1 == 0
end

-- Walk every table before inspecting the action; prevent cycles, huge tables and nested Instances.
local function bounded(value: unknown, depth: number, visited: { [any]: boolean }, budget: { bytes: number, entries: number }): boolean
	local kind = type(value)
	if kind == "string" then
		budget.bytes += #value
		return #value <= 256 and budget.bytes <= 4096
	elseif kind == "number" then
		budget.bytes += 8
		return value == value and value ~= math.huge and value ~= -math.huge and budget.bytes <= 4096
	elseif kind == "boolean" or kind == "nil" then
		budget.bytes += 1
		return budget.bytes <= 4096
	elseif kind ~= "table" or depth > 4 then
		return false
	end
	local record = value :: { [any]: any }
	if visited[record] then
		return false
	end
	visited[record] = true
	for key, child in pairs(record) do
		budget.entries += 1
		budget.bytes += 8
		if budget.entries > 64 or not bounded(key, depth + 1, visited, budget) or not bounded(child, depth + 1, visited, budget) then
			return false
		end
	end
	visited[record] = nil
	return true
end

function Protocol.validateAction(value: unknown, currentRunId: string): (boolean, string)
	if type(value) ~= "table" then
		return false, "InvalidPayload"
	end
	if not bounded(value, 0, {}, { bytes = 0, entries = 0 }) then
		return false, "InvalidPayload"
	end
	local request = value :: { [string]: any }
	if request.protocolVersion ~= Protocol.VERSION then
		return false, "ProtocolMismatch"
	end
	if type(request.requestId) ~= "string" or #request.requestId > 80 or not string.match(request.requestId, "^[%w_%-]+:[1-9]%d*$") or not identifier(request.runId, 80) or not identifier(request.action, 32) then
		return false, "InvalidPayload"
	end
	if request.runId ~= currentRunId then
		return false, "StaleRevision"
	end
	for key in pairs(request) do
		if key ~= "protocolVersion" and key ~= "requestId" and key ~= "runId" and key ~= "action" and key ~= "expectedEntityRevisions" and key ~= "payload" then
			return false, "InvalidPayload"
		end
	end
	local schema = ACTIONS[request.action]
	if schema == nil or type(request.payload) ~= "table" or type(request.expectedEntityRevisions) ~= "table" then
		return false, "InvalidPayload"
	end
	for key, expected in pairs(schema) do
		local field = request.payload[key]
		if type(field) ~= expected or (expected == "string" and not identifier(field, 80)) then
			return false, "InvalidPayload"
		end
	end
	for key in pairs(request.payload) do
		if type(key) ~= "string" or schema[key] == nil then
			return false, "InvalidPayload"
		end
	end
	-- This slice does not publish per-entity revisions. Never silently ignore a precondition.
	if next(request.expectedEntityRevisions) ~= nil then
		return false, "StaleRevision"
	end
	return true, "OK"
end

function Protocol.validateSnapshotRequest(value: unknown): (boolean, string)
	if type(value) ~= "table" or not bounded(value, 0, {}, { bytes = 0, entries = 0 }) then
		return false, "InvalidPayload"
	end
	local request = value :: { [string]: any }
	if request.protocolVersion ~= Protocol.VERSION then
		return false, "ProtocolMismatch"
	end
	if not revision(request.lastRevision) then
		return false, "InvalidPayload"
	end
	for key in pairs(request) do
		if key ~= "protocolVersion" and key ~= "lastRevision" and key ~= "runId" then
			return false, "InvalidPayload"
		end
	end
	if request.runId ~= nil and not identifier(request.runId, 80) then
		return false, "InvalidPayload"
	end
	return true, "OK"
end

return Protocol
