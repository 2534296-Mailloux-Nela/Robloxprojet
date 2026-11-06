--!strict
-- Paste into the SERVER Command Bar in a disposable Studio test with exactly two players.
-- Disable Bootstrap.server before starting the test; this harness owns its world.
local Players = game:GetService("Players")
local GameService = require(game:GetService("ServerScriptService").Services.GameService)
local players = Players:GetPlayers()
assert(#players == 2, "Start a Studio local server with exactly two players")
assert(not workspace:FindFirstChild("RestaurantSlice"), "Disable Bootstrap.server and restart the test; RestaurantSlice already exists")
local a, b = players[1], players[2]
local service = GameService.new()
local function run()
service:start()
local function waitFor(predicate: () -> boolean, timeout: number, message: string)
	local deadline = os.clock() + timeout
	while not predicate() do
		assert(os.clock() < deadline, message)
		task.wait(0.05)
	end
end
for _, player in players do
	local loaded, loadError = false, nil
	task.spawn(function()
		local ok, err = pcall(function() player:LoadCharacterAsync() end)
		if not ok then loadError = tostring(err) end
		loaded = true
	end)
	waitFor(function() return loaded end, 30, "Character load timed out for " .. player.Name)
	assert(not loadError, loadError)
	waitFor(function()
		local character = player.Character
		return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil and character:FindFirstChildOfClass("Humanoid") ~= nil
	end, 10, "Character root timed out for " .. player.Name)
end
local function root(player: Player): BasePart
	local character = player.Character
	local part = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	assert(part and part:IsA("BasePart") and humanoid and humanoid.Health > 0, "Current character is missing a living humanoid or root: " .. player.Name)
	return part
end
local function move(player: Player, id: string)
	local part = workspace.RestaurantSlice:FindFirstChild(id) :: BasePart
	assert(part, id)
	root(player).CFrame = part.CFrame + Vector3.new(0, 4, 5)
end
local function act(player: Player, action: string, id: string?): (boolean, string)
	return service:handleAction(player, action, if id then {targetId = id} else {})
end
local function station(id: string): any
	for _, entry in service:getSnapshot(a).stations do
		if entry.id == id then return entry end
	end
	error("Missing station " .. id)
end
local function reject(player: Player, action: string, id: string?, expected: string)
	local ok, reason = act(player, action, id)
	assert(not ok and reason == expected, action .. ": expected " .. expected .. ", got " .. reason)
end
assert(service:handleAction(a, "SetReady", {ready = true}))
assert(service:getSnapshot(a).phase == "Preparation", "One player must not start a two-player service")
assert(service:handleAction(b, "SetReady", {ready = true}))
assert(service:getSnapshot(a).phase == "Service")
waitFor(function() return #service:getSnapshot(a).customers == 1 end, 5, "Customer did not arrive")
move(a, "table"); assert(act(a, "TakeOrder", "table"))
move(a, "ingredient"); assert(act(a, "PickUp", "ingredient"))
move(a, "board"); assert(act(a, "PutDown", "board")); assert(act(a, "BeginWork", "board"))
move(b, "board"); reject(b, "BeginWork", "board", "Occupied")
reject(b, "PickUp", "board", "Occupied")
waitFor(function() return station("board").state == "ChoppedLettuce" end, 6, "Board work did not finish")
move(b, "plates"); assert(act(b, "PickUp", "plates"))
move(b, "board"); assert(act(b, "PutDown", "board")); assert(act(b, "PickUp", "board"))
move(b, "table"); assert(act(b, "Serve", "table"))
move(a, "table"); reject(a, "Serve", "table", "InvalidRecipe")
assert(service:getSnapshot(a).money == 10 and station("table").state == "DirtyPlate")
service.spawned = 3 -- Prevent further arrivals while exercising cleanup and summary.
assert(act(a, "PickUp", "table")); reject(b, "PickUp", "table", "Empty")
move(a, "sink"); assert(act(a, "PutDown", "sink")); assert(act(a, "BeginWork", "sink"))
move(b, "sink"); reject(b, "BeginWork", "sink", "Occupied")
waitFor(function() return station("sink").state == "CleanPlate" end, 6, "Washing did not finish")
assert(act(b, "PickUp", "sink"))
move(b, "plates"); assert(act(b, "PutDown", "plates"))

waitFor(function() return service:getSnapshot(a).phase == "Summary" end, 110, "Service did not reach summary")
assert(act(a, "NextDay"))
local snapshot = service:getSnapshot(b)
assert(snapshot.day == 2 and snapshot.phase == "Preparation")
assert(snapshot.readyPlayers[tostring(a.UserId)] == false and snapshot.readyPlayers[tostring(b.UserId)] == false)
assert(service:handleAction(a, "SetReady", {ready = true}))
assert(service:handleAction(b, "SetReady", {ready = true}))
waitFor(function() return #service:getSnapshot(a).customers == 1 end, 5, "Customer did not arrive on day two")
waitFor(function() return service:getSnapshot(a).phase == "Closed" end, 100, "Customer patience did not expire")
reject(a, "NextDay", nil, "WrongPhase")
end
local ok, err = xpcall(run, debug.traceback)
service:stop()
assert(workspace:FindFirstChild("RestaurantSlice") == nil, "Service world was not removed")
assert(ok, err)
print("Coop gameplay smoke passed")
