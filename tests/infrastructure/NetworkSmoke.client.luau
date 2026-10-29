--!strict
-- Paste in the CLIENT Command Bar in a disposable Play test, with Bootstrap.client disabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local snapshots: { any } = {}
local results: { any } = {}
local snapshotConnection = remotes.StateSnapshot.OnClientEvent:Connect(function(value) table.insert(snapshots, value) end)
local resultConnection = remotes.ActionResult.OnClientEvent:Connect(function(value) table.insert(results, value) end)
local function awaitCount(list: { any }, count: number): any
	local deadline = os.clock() + 5
	while #list < count and os.clock() < deadline do task.wait(0.05) end
	assert(#list >= count, "No remote response within 5 s")
	return list[count]
end
remotes.SnapshotRequest:FireServer({ protocolVersion = 1, lastRevision = 0 })
local snapshot = awaitCount(snapshots, 1)
assert(snapshot.runId == snapshot.stateChunk.runId and snapshot.chunkIndex == 1 and snapshot.chunkCount == 1)
local requestId = HttpService:GenerateGUID(false) .. ":1"
local request = { protocolVersion = 1, runId = snapshot.runId, requestId = requestId, action = "EndWork", expectedEntityRevisions = {}, payload = {} }
remotes.ActionRequest:FireServer(request)
local first = awaitCount(results, 1)
assert(first.requestId == requestId and first.status == "Rejected" and first.code == "NotWorking")
remotes.ActionRequest:FireServer(request)
local duplicate = awaitCount(results, 2)
assert(duplicate.code == first.code and duplicate.committedRevision == first.committedRevision)
remotes.ActionRequest:FireServer({ protocolVersion = 1, runId = snapshot.runId, requestId = requestId, action = "NextDay", expectedEntityRevisions = {}, payload = {} })
assert(awaitCount(results, 3).code == "InvalidPayload")
snapshotConnection:Disconnect()
resultConnection:Disconnect()
print("Network smoke passed")
