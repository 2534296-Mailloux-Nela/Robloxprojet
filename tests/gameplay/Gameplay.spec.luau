--!strict
-- Paste into the SERVER Command Bar of a Studio Play test with one player.
-- Disable Bootstrap.server in this disposable test place first: this harness owns its own world.
local Players = game:GetService("Players")
local GameService = require(game:GetService("ServerScriptService").Services.GameService)
local players = Players:GetPlayers()
assert(#players == 1, "Start Play with exactly one player")
assert(not workspace:FindFirstChild("RestaurantSlice"), "Disable Bootstrap.server and restart the test; RestaurantSlice already exists")
local player = players[1]
local service = GameService.new()
local function run()
local changes = 0
service.onStateChanged = function() changes += 1 end
service:start()
local function waitFor(predicate: () -> boolean, timeout: number, message: string)
	local deadline = os.clock() + timeout
	while not predicate() do
		assert(os.clock() < deadline, message)
		task.wait(0.05)
	end
end
local loaded, loadError = false, nil
task.spawn(function()
	local ok, err = pcall(function() player:LoadCharacterAsync() end)
	if not ok then loadError = tostring(err) end
	loaded = true
end)
waitFor(function() return loaded end, 30, "Character load timed out")
assert(not loadError, loadError)
local function root(): BasePart
	local character = player.Character
	local part = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	assert(part and part:IsA("BasePart") and humanoid and humanoid.Health > 0, "Current character is missing a living humanoid or root")
	return part
end
waitFor(function()
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil and character:FindFirstChildOfClass("Humanoid") ~= nil
end, 10, "Character root timed out")
local function move(id: string)
	local part = workspace.RestaurantSlice:FindFirstChild(id) :: BasePart
	assert(part, id)
	root().CFrame = part.CFrame + Vector3.new(0, 4, 5)
end
local function act(action: string, id: string?): (boolean, string)
	return service:handleAction(player, action, if id then { targetId = id } else {})
end
local function station(id: string): any
	for _, entry in service:getSnapshot(player).stations do
		if entry.id == id then return entry end
	end
	error("Missing station " .. id)
end
assert(changes > 0, "Initial state callback must fire")
local userId = tostring(player.UserId)
local initial = service:getSnapshot(player)
assert(initial.readyPlayers[userId] == false and initial.players[userId] ~= nil, "Snapshot must use string user IDs")
initial.readyPlayers[userId] = true
initial.stations[1].state = "Tampered"
initial.players[userId].heldItem = "Tampered"
assert(service:getSnapshot(player).readyPlayers[userId] == false and station(initial.stations[1].id).state ~= "Tampered" and service:getSnapshot(player).players[userId].heldItem == nil, "Snapshot must be detached")
root().CFrame = CFrame.new(15, 5, 14)
assert(not act("PickUp", "ingredient"), "Gameplay is blocked during preparation")
assert(not act("NextDay"), "NextDay must be blocked before summary")
assert(service:handleAction(player, "SetReady", { ready = true }))
assert(service:getSnapshot(player).phase == "Service")
waitFor(function() return #service:getSnapshot(player).customers == 1 end, 5, "Customer did not arrive")
local customerSnapshot = service:getSnapshot(player)
customerSnapshot.customers[1].state = "Tampered"
assert(service:getSnapshot(player).customers[1].state == "WaitingOrder", "Customer snapshot must be detached")
local accepted, reason = act("PickUp", "ingredient")
assert(not accepted and reason == "OutOfRange", "Server must enforce range")
local ingredient = workspace.RestaurantSlice:FindFirstChild("ingredient") :: BasePart
root().CFrame = CFrame.new(ingredient.Position + Vector3.new(12.1, 0, 0))
accepted, reason = act("PickUp", "ingredient")
assert(not accepted and reason == "OutOfRange", "Station beyond 12 studs must be rejected")
assert(service:getSnapshot(player).players[userId].heldItem == nil, "Rejected pickup must not change hands")
root().CFrame = CFrame.new(ingredient.Position + Vector3.new(12, 0, 0))
assert(act("PickUp", "ingredient"), "Station exactly 12 studs away must be accepted")
assert(service:getSnapshot(player).players[userId].heldItem == "Lettuce")
move("board"); assert(act("PutDown", "board"))
assert(act("BeginWork", "board"))
waitFor(function() return station("board").progress > 0 end, 2, "Board work did not progress")
root().CFrame = CFrame.new(15, 5, 14)
waitFor(function() return station("board").progress == 0 end, 2, "Moving out of range must cancel work")
assert(station("board").progress == 0 and station("board").state == "Lettuce", "Moving out of range must cancel work")
accepted, reason = act("EndWork")
assert(not accepted and reason == "NotWorking")
move("board"); assert(act("PickUp", "board"))
move("counter"); assert(act("PutDown", "counter"))
move("table"); assert(act("TakeOrder", "table"))
move("ingredient"); assert(act("PickUp", "ingredient")); assert(not act("PickUp", "ingredient"))
move("board"); assert(act("PutDown", "board")); assert(act("BeginWork", "board"))
waitFor(function() return station("board").state == "ChoppedLettuce" end, 6, "Board work did not finish")
move("plates"); assert(act("PickUp", "plates"))
move("board"); assert(act("PutDown", "board")); assert(station("board").state == "Salad")
assert(act("PickUp", "board"))
move("table"); assert(act("Serve", "table")); assert(not act("Serve", "table"))
assert(service:getSnapshot(player).money == 10)
assert(station("table").state == "DirtyPlate" and #service:getSnapshot(player).customers == 0)
service.spawned = 3 -- Prevent further arrivals while exercising cleanup and summary.
assert(act("PickUp", "table"))
assert(service:getSnapshot(player).players[userId].heldItem == "DirtyPlate")
move("sink"); assert(act("PutDown", "sink")); assert(act("BeginWork", "sink"))
waitFor(function() return station("sink").state == "CleanPlate" end, 6, "Washing did not finish")
assert(act("PickUp", "sink"))
waitFor(function() return service:getSnapshot(player).phase == "Summary" end, 110, "Service did not reach summary")
assert(act("NextDay"))
local snapshot = service:getSnapshot(player)
assert(snapshot.day == 2 and snapshot.phase == "Preparation")
assert(snapshot.readyPlayers[tostring(player.UserId)] == false)
end
local ok, err = xpcall(run, debug.traceback)
service:stop()
assert(workspace:FindFirstChild("RestaurantSlice") == nil, "Service world was not removed")
assert(ok, err)
print("Gameplay smoke passed")
