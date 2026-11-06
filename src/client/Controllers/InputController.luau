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

function InputController.new(player: Player, onAction: (string, string?) -> (), onTarget: (string?) -> ())
	local self = setmetatable({ connections = {} :: { RBXScriptConnection }, cameraConnection = nil :: RBXScriptConnection?, destroyed = false }, InputController)
	local selected: string? = nil
	local explicitTarget: string? = nil
	local cachedTargets: {{id: string, part: BasePart}} = {}
	local lastCacheRefresh = -math.huge
	local lastTargetRefresh = -math.huge
	local characterRemoving = false
	local function selectTarget(id: string?)
		if id ~= selected then
			selected = id
			onTarget(id)
		end
	end
	local function rayTarget(point: Vector2?): string?
		local camera = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local world = workspace:FindFirstChild("RestaurantSlice")
		if characterRemoving or not camera or not root or not root:IsA("BasePart") or not world then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
		local ray = if point then camera:ScreenPointToRay(point.X, point.Y) else Ray.new(camera.CFrame.Position, camera.CFrame.LookVector)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 120, params)
		if not result or not result.Instance:IsA("BasePart") or not result.Instance:IsDescendantOf(world) then return nil end
		if (result.Instance.Position - root.Position).Magnitude >= 11.9 then return nil end
		local current: Instance? = result.Instance
		while current and current ~= world and current:GetAttribute("TargetId") == nil do current = current.Parent end
		local id = if current and current ~= world then current:GetAttribute("TargetId") else nil
		return if typeof(id) == "string" then id else nil
	end
	local function findTarget(point: Vector2?, overGui: boolean)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local world = workspace:FindFirstChild("RestaurantSlice")
		if characterRemoving or not root or not root:IsA("BasePart") or not world then
			explicitTarget = nil
			selectTarget(nil)
			return
		end
		local now = os.clock()
		if now - lastCacheRefresh >= 0.15 then
			lastCacheRefresh = now
			table.clear(cachedTargets)
			for _, instance in world:GetDescendants() do
				if instance:IsA("BasePart") then
					local parent: Instance? = instance
					while parent and parent ~= world and parent:GetAttribute("TargetId") == nil do parent = parent.Parent end
					local id = if parent and parent ~= world then parent:GetAttribute("TargetId") else nil
					if typeof(id) == "string" then table.insert(cachedTargets, { id = id, part = instance }) end
				end
			end
		end
		local nearest = 11.9
		local candidateId: string? = nil
		local selectedInRange = false
		local explicitInRange = false
		for _, target in cachedTargets do
			if target.part:IsDescendantOf(world) then
				local distance = (target.part.Position - root.Position).Magnitude
				if distance < 11.9 then
					if target.id == selected then selectedInRange = true end
					if target.id == explicitTarget then explicitInRange = true end
					if distance < nearest or (distance == nearest and (candidateId == nil or target.id < candidateId)) then
						nearest = distance
						candidateId = target.id
					end
				end
			end
		end
		if explicitInRange then selectTarget(explicitTarget); return end
		explicitTarget = nil
		if overGui and selectedInRange then return end
		local hitId = if overGui then nil else rayTarget(point)
		selectTarget(hitId or candidateId)
	end
	local function updateTarget()
		local now = os.clock()
		if now - lastTargetRefresh < 0.1 then return end
		lastTargetRefresh = now
		local point: Vector2? = nil
		local overGui = false
		if UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Gamepad1 then
			point = UserInputService:GetMouseLocation()
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			overGui = playerGui ~= nil and #playerGui:GetGuiObjectsAtPosition(point.X, point.Y) > 0
		end
		findTarget(point, overGui)
	end
	for _, entry in ACTIONS do
		local captured = entry
		ContextActionService:BindAction(captured.name, function(_, inputState, inputObject)
			if self.destroyed then return Enum.ContextActionResult.Pass end
			if captured.action == "BeginWork" then
				local source = "Key:" .. inputObject.KeyCode.Name
				if inputState == Enum.UserInputState.Begin then onAction("BeginWork", source) end
				if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then onAction("EndWork", source) end
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
		if (input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:GetLastInputType() == Enum.UserInputType.MouseMovement) or input.UserInputType == Enum.UserInputType.Gamepad1 then
			explicitTarget = nil
			updateTarget()
		end
	end))
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then updateTarget() end
	end))
	table.insert(self.connections, UserInputService.TouchStarted:Connect(function(input, processed)
		if not processed then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			explicitTarget = rayTarget(point)
			lastCacheRefresh = -math.huge
			findTarget(point, false)
		end
	end))
	table.insert(self.connections, game:GetService("RunService").Heartbeat:Connect(updateTarget))
	table.insert(self.connections, player.CharacterAdded:Connect(function()
		characterRemoving = false
		lastTargetRefresh = -math.huge
		task.defer(function() if not self.destroyed then updateTarget() end end)
	end))
	table.insert(self.connections, player.CharacterRemoving:Connect(function()
		characterRemoving = true
		explicitTarget = nil
		selectTarget(nil)
	end))
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
