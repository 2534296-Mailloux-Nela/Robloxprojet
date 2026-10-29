--!strict
-- Paste into the SERVER Command Bar of a Studio Play test with one player.
-- Disable Bootstrap.server in this disposable test place first: this harness owns its own world.
local Players = game:GetService("Players")
local GameService = require(game:GetService("ServerScriptService").Services.GameService)
local player = Players:GetPlayers()[1]
assert(player, "Start Play with at least one player")
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart") :: BasePart
local service = GameService.new()
local changes = 0
service.onStateChanged = function() changes += 1 end
service:start()
local function move(id: string)
	local part = workspace.RestaurantSlice:FindFirstChild(id) :: BasePart
	assert(part, id)
	root.CFrame = part.CFrame + Vector3.new(0, 4, 5)
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
assert(service:getSnapshot(player).readyPlayers[userId] == false and station(initial.stations[1].id).state ~= "Tampered", "Snapshot must be detached")
root.CFrame = CFrame.new(1000, 10, 1000)
assert(not act("PickUp", "ingredient"), "Gameplay is blocked during preparation")
assert(not act("NextDay"), "NextDay must be blocked before summary")
assert(service:handleAction(player, "SetReady", { ready = true }))
assert(service:getSnapshot(player).phase == "Service")
service:_tick(0.1)
assert(#service:getSnapshot(player).customers == 1)
local accepted, reason = act("PickUp", "ingredient")
assert(not accepted and reason == "OutOfRange", "Server must enforce range")
move("table"); assert(act("TakeOrder", "table"))
move("ingredient"); assert(act("PickUp", "ingredient")); assert(not act("PickUp", "ingredient"))
move("board"); assert(act("PutDown", "board")); assert(act("BeginWork", "board"))
service:_tick(1.5)
assert(station("board").progress > 0 and station("board").progress < 1)
service:_tick(1.6)
assert(station("board").state == "ChoppedLettuce")
move("plates"); assert(act("PickUp", "plates"))
move("board"); assert(act("PutDown", "board")); assert(station("board").state == "Salad")
assert(act("PickUp", "board"))
move("table"); assert(act("Serve", "table")); assert(not act("Serve", "table"))
assert(service:getSnapshot(player).money == 10)
assert(act("PickUp", "table"))
move("sink"); assert(act("PutDown", "sink")); assert(act("BeginWork", "sink"))
service:_tick(3.1)
assert(station("sink").state == "CleanPlate")
assert(act("PickUp", "sink"))
service.spawned = 3
service.timeRemaining = 0
service:_tick(0.1)
assert(service:getSnapshot(player).phase == "Summary")
assert(act("NextDay"))
local snapshot = service:getSnapshot(player)
assert(snapshot.day == 2 and snapshot.phase == "Preparation")
assert(snapshot.readyPlayers[tostring(player.UserId)] == false)
service:stop()
assert(workspace:FindFirstChild("RestaurantSlice") == nil)
print("Gameplay smoke passed")
