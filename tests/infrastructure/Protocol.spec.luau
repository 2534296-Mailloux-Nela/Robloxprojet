--!strict
-- Run in Studio's server Command Bar after syncing the Rojo project (paste this file).
local Protocol = require(game:GetService("ReplicatedStorage").Shared.Protocol)
local request = {
	protocolVersion = 1, runId = "run-1", requestId = "session-1:1",
	action = "SetReady", expectedEntityRevisions = {}, payload = { ready = false },
}
local function check(value: any, expected: boolean, code: string?)
	local valid, reason = Protocol.validateAction(value, "run-1")
	assert(valid == expected and (code == nil or reason == code), reason)
end
check(request, true)
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:0", action = "EndWork", expectedEntityRevisions = {}, payload = {} }, false, "InvalidPayload")
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:9", action = "PickUp", expectedEntityRevisions = {}, payload = { targetId = "board" } }, true)
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:2", action = "EndWork", expectedEntityRevisions = {}, payload = {} }, true)
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:3", action = "SetReady", expectedEntityRevisions = {}, payload = { ready = 1 } }, false, "InvalidPayload")
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:4", action = "NextDay", expectedEntityRevisions = {}, payload = { money = 999 } }, false, "InvalidPayload")
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:5", action = "NextDay", expectedEntityRevisions = { table = 1 }, payload = {} }, false, "StaleRevision")
check({ protocolVersion = 2, runId = "run-1", requestId = "session-1:6", action = "NextDay", expectedEntityRevisions = {}, payload = {} }, false, "ProtocolMismatch")
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:7", action = "BeginWork", expectedEntityRevisions = {}, payload = { targetId = "bad id" } }, false, "InvalidPayload")
local cyclic: any = {}
cyclic.loop = cyclic
check(cyclic, false, "InvalidPayload")
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:8", action = "EndWork", expectedEntityRevisions = {}, payload = { count = math.huge } }, false, "InvalidPayload")
check({ protocolVersion = 1, runId = "run-1", requestId = "session-1:10", action = "EndWork", expectedEntityRevisions = {}, payload = { count = 0/0 } }, false, "InvalidPayload")
assert(Protocol.validateSnapshotRequest({ protocolVersion = 1, lastRevision = 0 }))
local valid = Protocol.validateSnapshotRequest({ protocolVersion = 1, lastRevision = math.huge })
assert(not valid)
print("Infrastructure protocol tests passed")
