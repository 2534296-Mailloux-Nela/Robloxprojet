--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local InputController = {}
InputController.__index = InputController

local ACTIONS = {
	{ name = "Kitchen_Interact", label = "Interagir", keys = { Enum.KeyCode.E, Enum.KeyCode.ButtonR3 }, action = "Context" },
	{ name = "Kitchen_PickUp", label = "Prendre", keys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX }, action = "PickUp" },
	{ name = "Kitchen_PutDown", label = "Poser", keys = { Enum.KeyCode.R, Enum.KeyCode.ButtonB }, action = "PutDown" },
	{ name = "Kitchen_Work", label = "Travailler", keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonR2 }, action = "BeginWork" },
	{ name = "Kitchen_Order", label = "Commande", keys = { Enum.KeyCode.One, Enum.KeyCode.ButtonL1 }, action = "TakeOrder" },
	{ name = "Kitchen_Serve", label = "Servir", keys = { Enum.KeyCode.Two, Enum.KeyCode.ButtonR1 }, action = "Serve" },
	{ name = "Kitchen_Ready", label = "Prêt", keys = { Enum.KeyCode.G, Enum.KeyCode.ButtonY }, action = "SetReady" },
}

function InputController.new(player: Player, onAction: (string) -> (), onTarget: (string?) -> ())
	local self = setmetatable({ connections = {} :: { RBXScriptConnection }, cameraConnection = nil :: RBXScriptConnection?, destroyed = false }, InputController)
	local selected: string? = nil
	local function selectTarget(id: string?)
		if id ~= selected then
			selected = id
			onTarget(id)
		end
	end
	local function findTarget(screenPoint: Vector2?)
		local camera = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not camera or not root or not root:IsA("BasePart") then selectTarget(nil); return end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
		local ray = if screenPoint then camera:ScreenPointToRay(screenPoint.X, screenPoint.Y) else Ray.new(camera.CFrame.Position, camera.CFrame.LookVector)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 120, params)
		local current = if result then result.Instance else nil
		while current and current:GetAttribute("TargetId") == nil do current = current.Parent end
		local id = if current then current:GetAttribute("TargetId") else nil
		if typeof(id) == "string" and result and (result.Instance.Position - root.Position).Magnitude <= 12 then
			selectTarget(id)
			return
		end
		-- Keep nearby stations selectable when the cursor/camera ray misses them.
		local nearest = 12
		local candidateId: string? = nil
		local world = workspace:FindFirstChild("RestaurantSlice")
		if world then
			for _, instance in world:GetDescendants() do
				if instance:IsA("BasePart") then
					local partId = instance:GetAttribute("TargetId")
					local targetInstance: Instance? = instance
					while targetInstance and targetInstance:GetAttribute("TargetId") == nil do targetInstance = targetInstance.Parent end
					if typeof(partId) ~= "string" and targetInstance then partId = targetInstance:GetAttribute("TargetId") end
					if typeof(partId) == "string" then
						local distance = (instance.Position - root.Position).Magnitude
						if distance < nearest then nearest = distance; candidateId = partId end
					end
				end
			end
		end
		selectTarget(candidateId)
	end
	local function updateTarget()
		local point: Vector2? = nil
		if UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Gamepad1 then
			point = UserInputService:GetMouseLocation()
		end
		findTarget(point)
	end
	for _, entry in ACTIONS do
		local captured = entry
		ContextActionService:BindAction(captured.name, function(_, inputState)
			if self.destroyed then return Enum.ContextActionResult.Pass end
			if captured.action == "BeginWork" then
				if inputState == Enum.UserInputState.Begin then onAction("BeginWork") end
				if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then onAction("EndWork") end
			elseif inputState == Enum.UserInputState.Begin then
				onAction(captured.action)
			end
			return Enum.ContextActionResult.Sink
		end, false, table.unpack(captured.keys))
	end
	local function connectCamera()
		if self.cameraConnection then self.cameraConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		self.cameraConnection = if camera then camera:GetPropertyChangedSignal("CFrame"):Connect(updateTarget) else nil
		updateTarget()
	end
	table.insert(self.connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera))
	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Gamepad1 then updateTarget() end
	end))
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then updateTarget() end
	end))
	table.insert(self.connections, UserInputService.TouchStarted:Connect(function(input, processed)
		if not processed then findTarget(Vector2.new(input.Position.X, input.Position.Y)) end
	end))
	table.insert(self.connections, game:GetService("RunService").Heartbeat:Connect(updateTarget))
	table.insert(self.connections, player.CharacterAdded:Connect(function() task.defer(updateTarget) end))
	table.insert(self.connections, player.CharacterRemoving:Connect(function() selectTarget(nil) end))
	connectCamera()
	return self
end

function InputController:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, entry in ACTIONS do ContextActionService:UnbindAction(entry.name) end
	if self.cameraConnection then self.cameraConnection:Disconnect() end
	for _, connection in self.connections do connection:Disconnect() end
	table.clear(self.connections)
end

return InputController
