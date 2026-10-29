--!strict

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local UIController = {}
UIController.__index = UIController

local function make(className: string, props: {[string]: any}, parent: Instance): Instance
	local object = Instance.new(className)
	for key, value in props do (object :: any)[key] = value end
	object.Parent = parent
	return object
end

function UIController.new(player: Player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "KitchenClient"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(0.94, 0, 0, 240), BackgroundColor3 = Color3.fromRGB(24, 28, 35), BackgroundTransparency = 0.08 }, gui) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, root)
	make("UISizeConstraint", { MaxSize = Vector2.new(720, 240) }, root)
	local status = make("TextLabel", { Name = "Status", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 56), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = Color3.new(1, 1, 1), TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = "Connexion…" }, root) :: TextLabel
	local detail = make("TextLabel", { Name = "Details", Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 0, 34), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(215, 222, 230), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, root) :: TextLabel
	local targetLabel = make("TextLabel", { Name = "Target", Position = UDim2.fromOffset(12, 96), Size = UDim2.new(1, -24, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(255, 220, 120), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = "Cible : aucune" }, root) :: TextLabel
	local notice = make("TextLabel", { Name = "Notice", Position = UDim2.new(0, 12, 1, -32), Size = UDim2.new(1, -24, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(190, 225, 255), TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, root) :: TextLabel
	local buttons: {[string]: TextButton} = {}
	local specs = {
		{ "Prendre", "PickUp" }, { "Poser", "PutDown" }, { "Travailler", "BeginWork" }, { "Commande", "TakeOrder" }, { "Servir", "Serve" }, { "Prêt", "SetReady" }, { "Jour suivant", "NextDay" },
	}
	for index, spec in specs do
		local column = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		local button = make("TextButton", { Name = spec[2], Position = UDim2.new(column * 0.25, 8, 0, 125 + row * 40), Size = UDim2.new(0.25, -12, 0, 34), BackgroundColor3 = Color3.fromRGB(55, 68, 84), TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextScaled = true, TextWrapped = true, Text = spec[1], Selectable = true, AutoButtonColor = true }, root) :: TextButton
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, button)
		make("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 14 }, button)
		buttons[spec[2]] = button
	end
	local self = setmetatable({ gui = gui, status = status, detail = detail, targetLabel = targetLabel, noticeLabel = notice, buttons = buttons, noticeText = "En attente de l'état du serveur", actionCallback = nil, targetCallback = nil, connections = {} }, UIController)
	for action, button in buttons do
		if action == "BeginWork" then
			table.insert(self.connections, button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.Gamepad1 then
					if self.actionCallback then self.actionCallback("BeginWork") end
				end
			end))
			table.insert(self.connections, button.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.Gamepad1 then
					if self.actionCallback then self.actionCallback("EndWork") end
				end
			end))
		else
			table.insert(self.connections, button.Activated:Connect(function()
				if self.actionCallback then self.actionCallback(action) end
			end))
		end
	end
	return self
end

function UIController:SetActionCallback(callback: (string) -> ()) self.actionCallback = callback end
function UIController:SetTargetCallback(callback: () -> string?) self.targetCallback = callback end

function UIController:Notice(text: string)
	self.noticeText = text
	self.noticeLabel.Text = text
end

function UIController:Render(state: any, targetId: string?, pending: {[string]: string})
	if not state then
		self.status.Text = "Connexion au restaurant… état serveur en attente"
		self.detail.Text = "Les actions restent désactivées jusqu'au snapshot."
		self.targetLabel.Text = "Cible : aucune"
		for _, button in self.buttons do button.Active = false; button.Selectable = false end
		return
	end
	local phase = tostring(state.phase or "?")
	local phaseText = if phase == "Preparation" then "Préparation" elseif phase == "Service" then "Service" elseif phase == "Summary" then "Bilan" elseif phase == "Closed" then "Fermé" else phase
	local seconds = if type(state.timeRemaining) == "number" then tostring(math.ceil(state.timeRemaining)) else "?"
	self.status.Text = string.format("Jour %s · %s · Temps %s · Argent partagé : %s", tostring(state.day or "?"), phaseText, seconds, tostring(state.money or "?"))
	local orders = {}
	for _, customer in state.customers or {} do
		if typeof(customer) == "table" then
			local patience = if type(customer.patience) == "number" then tostring(math.ceil(customer.patience)) else "?"
			table.insert(orders, string.format("%s : patience %s", tostring(customer.order or "Commande"), patience))
		end
	end
	self.detail.Text = if #orders > 0 then table.concat(orders, "  |  ") else tostring(state.message or "Aucune commande en attente")
	local userId = tostring(game:GetService("Players").LocalPlayer.UserId)
	local ready = state.readyPlayers and state.readyPlayers[userId] == true
	self.buttons.SetReady.Text = if ready then "Annuler prêt" else "Prêt"
	local myState = state.players and state.players[userId]
	local targetState = ""
	for _, station in state.stations or {} do
		if station.id == targetId then
			local progress = if type(station.progress) == "number" and station.progress > 0 then string.format(" %d%%", math.floor(station.progress * 100)) else ""
			targetState = " (" .. tostring(station.state) .. progress .. ")"
			break
		end
	end
	self.targetLabel.Text = "Cible : " .. (targetId or "aucune") .. targetState .. (if targetId then "" else " · Approchez-vous d'une station") .. " · Main : " .. tostring(myState and myState.heldItem or "vide") .. (if next(pending) then " · attente" else "")
	self.noticeLabel.Text = self.noticeText
	local active = state.phase ~= "Closed" and state.phase ~= "Summary"
	for action, button in self.buttons do
		button.Active = active
		button.Selectable = active
		button.TextTransparency = if active then 0 else 0.45
	end
	self.buttons.NextDay.Active = state.phase == "Summary"
	self.buttons.NextDay.Selectable = state.phase == "Summary"
	self.buttons.SetReady.Active = state.phase == "Preparation"
	self.buttons.SetReady.Selectable = state.phase == "Preparation"
	if UserInputService.GamepadEnabled then
		local focused = GuiService.SelectedObject
		if focused == nil or (focused.Parent == self.buttons.SetReady.Parent and not focused.Selectable) then
			GuiService.SelectedObject = if state.phase == "Summary" then self.buttons.NextDay elseif state.phase == "Preparation" then self.buttons.SetReady else self.buttons.PickUp
		end
	end
end

function UIController:Destroy()
	for _, connection in self.connections do connection:Disconnect() end
	table.clear(self.connections)
	for _, button in self.buttons do
		if GuiService.SelectedObject == button then GuiService.SelectedObject = nil; break end
	end
	self.gui:Destroy()
end

return UIController
