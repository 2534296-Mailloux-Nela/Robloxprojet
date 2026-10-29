--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameService = require(script.Parent:WaitForChild("Services"):WaitForChild("GameService"))
local NetworkService = require(script.Parent:WaitForChild("Infrastructure"):WaitForChild("NetworkService"))

local service = GameService.new()
local network = NetworkService.new(ReplicatedStorage:WaitForChild("Remotes") :: Folder, service)
service.onStateChanged = function()
	network:changed()
end
service:start()
network:start()

game:BindToClose(function()
	network:stop()
	service:stop()
end)
