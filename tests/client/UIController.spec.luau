--!strict
-- Paste into the CLIENT Command Bar during Studio Play.
-- Disable the client bootstrap LocalScript in StarterPlayerScripts before Play.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player, "Run this test from the client Command Bar")

local function waitForChildBounded(parent: Instance, name: string, timeout: number): Instance
	local deadline = os.clock() + timeout
	local child = parent:FindFirstChild(name)
	while not child and os.clock() < deadline do
		task.wait(0.1)
		child = parent:FindFirstChild(name)
	end
	assert(child, string.format("Timed out waiting for %s.%s", parent:GetFullName(), name))
	return child
end

local playerScripts = waitForChildBounded(player, "PlayerScripts", 10)
local controllers = waitForChildBounded(playerScripts, "Controllers", 10)
local controllerModule = waitForChildBounded(controllers, "UIController", 10)
local UIController = require(controllerModule)

local ui = UIController.new(player)
local ok, err = xpcall(function()
	local pending = {}
	ui:Render(nil, nil, pending)
	assert(not ui.buttons.PickUp.Active, "Actions must stay disabled before the initial snapshot")
	assert(ui.targetLabel.Text == "Cible : aucune", "Missing state must clear the displayed target")

	local state = {
		phase = "Service",
		day = 1,
		timeRemaining = 42,
		money = 10,
		customers = { { order = "Salade", patience = 18 } },
		players = { [tostring(player.UserId)] = { heldItem = "Lettuce" } },
		stations = { { id = "board", kind = "Board", state = "Lettuce", progress = 0.5 } },
		readyPlayers = {},
	}
	ui:Render(state, "board", pending)
	assert(ui.buttons.PickUp.Active and ui.buttons.BeginWork.Active, "Service actions should be enabled")
	assert(string.find(ui.targetLabel.Text, "board", 1, true), "HUD must show the selected target")
	assert(string.find(ui.targetLabel.Text, "50%", 1, true), "HUD must show station progress")
	assert(string.find(ui.targetLabel.Text, "Lettuce", 1, true), "HUD must show the held item")

	state.phase = "Summary"
	ui:Render(state, nil, pending)
	assert(not ui.buttons.PickUp.Active and ui.buttons.NextDay.Active, "Summary should only enable NextDay")
	ui:Render(nil, nil, pending)
	assert(not ui.buttons.NextDay.Active, "Actions must be disabled again while awaiting a snapshot")
end, debug.traceback)

ui:Destroy()
if not ok then error(err, 0) end
print("Client UI tests passed")
