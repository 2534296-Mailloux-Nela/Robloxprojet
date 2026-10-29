--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local RANGE = 12
local DAY_SECONDS = 100
local PATIENCE = 90
local WORK_SECONDS = 3
local MAX_WORK_SECONDS = 8

type Station = {id: string, kind: string, cellX: number, cellZ: number, state: string, progress: number, part: BasePart?}
type Customer = {id: string, order: string, patience: number, state: string}
type Worker = {targetId: string, elapsed: number}
type PlayerState = {heldItem: string?, work: Worker?}
type Service = {
 runId: string, phase: string, day: number, money: number, timeRemaining: number,
 readyPlayers: {[string]: boolean}, players: {[string]: PlayerState}, stations: {Station},
 customers: {Customer}, message: string, onStateChanged: (() -> ())?,
 running: boolean, connections: {RBXScriptConnection}, world: Model?, accumulator: number,
 spawned: number, nextArrival: number,
 start: (Service) -> (), stop: (Service) -> (), handleAction: (Service, Player, string, any) -> (boolean, string),
 getSnapshot: (Service, Player) -> {[string]: any},
 _tick: (Service, number) -> (), _notify: (Service) -> (), _reset: (Service) -> (),
}

local GameService = {}
local methods = {}

local function findStation(self: Service, id: string): Station?
 for _, station in self.stations do
  if station.id == id then return station end
 end
 return nil
end

local function nearby(player: Player, station: Station): boolean
 local character = player.Character
 local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
 local part = station.part
 return root ~= nil and root:IsA("BasePart") and part ~= nil and (root.Position - part.Position).Magnitude <= RANGE
end

local function participant(player: Player): boolean
 return player.Parent == Players
end

local function publish(self: Service)
 if self.onStateChanged then self.onStateChanged() end
end

function methods:_notify()
 publish(self)
end

function methods:_reset()
 self.timeRemaining = DAY_SECONDS
 self.customers = {}
 self.spawned = 0
 self.nextArrival = 0
 self.readyPlayers = {}
 for _, state in self.players do state.heldItem = nil; state.work = nil end
 for _, station in self.stations do
  station.progress = 0
  station.state = if station.kind == "PlateRack" then "CleanPlate" else "Empty"
 end
end

function GameService.new(): Service
 local self: Service = setmetatable({
  runId = HttpService:GenerateGUID(false), phase = "Preparation", day = 1, money = 0,
  timeRemaining = DAY_SECONDS, readyPlayers = {}, players = {}, stations = {}, customers = {},
  message = "Preparez-vous puis confirmez Pret.", onStateChanged = nil,
  running = false, connections = {}, world = nil, accumulator = 0, spawned = 0, nextArrival = 0,
 }, {__index = methods}) :: any
 local definitions = {
  {"ingredient", "Ingredient", -2, -2},
  {"board", "Board", 0, -2},
  {"plates", "PlateRack", 2, -2},
  {"counter", "Counter", -2, 1},
  {"sink", "Sink", 0, 1},
  {"table", "Table", 2, 1},
 }
 for _, def in definitions do
  table.insert(self.stations, {id = def[1] :: string, kind = def[2] :: string, cellX = def[3] :: number, cellZ = def[4] :: number, state = if def[2] == "PlateRack" then "CleanPlate" else "Empty", progress = 0, part = nil})
 end
 return self
end

function methods:start()
 if self.running then return end
 self.running = true
 local world = Instance.new("Model")
 world.Name = "RestaurantSlice"
 local floor = Instance.new("Part")
 floor.Name = "Floor"; floor.Size = Vector3.new(36, 1, 30); floor.Position = Vector3.new(0, 0, 0); floor.Anchored = true; floor.Parent = world
 local spawn = Instance.new("SpawnLocation")
 spawn.Name = "RestaurantSpawn"; spawn.Size = Vector3.new(4, 1, 4); spawn.Position = Vector3.new(0, 1, 10); spawn.Anchored = true; spawn.Neutral = true; spawn.Parent = world
 local actions: {[string]: string} = {Ingredient = "PickUp", Board = "PutDown", PlateRack = "PickUp", Counter = "PutDown", Sink = "PutDown", Table = "TakeOrder"}
 for _, station in self.stations do
  local part = Instance.new("Part")
  part.Name = station.id; part.Size = Vector3.new(4, 3, 4); part.Position = Vector3.new(station.cellX * 5, 2, station.cellZ * 5); part.Anchored = true
  part:SetAttribute("TargetId", station.id); part:SetAttribute("InteractionAction", actions[station.kind]); part:SetAttribute("PickUpAction", "PickUp"); part:SetAttribute("WorkAction", "BeginWork")
  local billboard = Instance.new("BillboardGui"); billboard.Size = UDim2.fromOffset(150, 40); billboard.StudsOffset = Vector3.new(0, 3, 0); billboard.AlwaysOnTop = true; billboard.Parent = part
  local label = Instance.new("TextLabel"); label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 0.25; label.TextScaled = true; label.Text = station.kind; label.Parent = billboard
  part.Parent = world; station.part = part
 end
 world.Parent = workspace; self.world = world
 local function addPlayer(player: Player)
  local id = tostring(player.UserId)
  local count = 0
  for _ in self.players do count += 1 end
  if not self.players[id] and count < 4 then
   self.players[id] = {heldItem = nil, work = nil}; self.readyPlayers[id] = false
   if self.phase == "Preparation" then for key in self.readyPlayers do self.readyPlayers[key] = false end end
   self:_notify()
  end
 end
 for _, player in Players:GetPlayers() do addPlayer(player) end
 table.insert(self.connections, Players.PlayerAdded:Connect(addPlayer))
 table.insert(self.connections, Players.PlayerRemoving:Connect(function(player: Player)
  local id = tostring(player.UserId)
  local state = self.players[id]
  if state then
   if state.work then
    local station = findStation(self, state.work.targetId)
    if station then station.progress = 0 end
   end
   -- Returning a held plate prevents an unrecoverable shortage after disconnect.
   if state.heldItem == "CleanPlate" or state.heldItem == "Salad" then
    local rack = findStation(self, "plates")
    if rack and rack.state == "Empty" then rack.state = "CleanPlate" end
   elseif state.heldItem == "DirtyPlate" then
    local sink = findStation(self, "sink")
    if sink and sink.state == "Empty" then sink.state = "DirtyPlate" end
   end
   self.players[id] = nil; self.readyPlayers[id] = nil
   if self.phase == "Preparation" then for key in self.readyPlayers do self.readyPlayers[key] = false end end
   self:_notify()
  end
 end))
 table.insert(self.connections, RunService.Heartbeat:Connect(function(dt: number)
  self.accumulator += dt
  if self.accumulator >= 0.1 then
   local elapsed = self.accumulator; self.accumulator = 0
   self:_tick(elapsed)
  end
 end))
 self:_notify()
end

function methods:stop()
 if not self.running then return end
 self.running = false
 for _, connection in self.connections do connection:Disconnect() end
 table.clear(self.connections)
 if self.world then self.world:Destroy(); self.world = nil end
 for _, station in self.stations do station.part = nil end
 for _, state in self.players do state.work = nil end
end

function methods:_tick(dt: number)
 if not self.running then return end
 local changed = false
 if self.phase == "Service" then
  self.timeRemaining = math.max(0, self.timeRemaining - dt); changed = true
  if self.timeRemaining > 0 and self.spawned < 3 and self.nextArrival <= 0 and #self.customers == 0 then
   local tableStation = findStation(self, "table")
   if tableStation and tableStation.state == "Empty" then
    self.spawned += 1
    self.customers = {{id = "customer" .. tostring(self.spawned), order = "Salad", patience = PATIENCE, state = "WaitingOrder"}}
    tableStation.state = "WaitingOrder"; self.nextArrival = 15
    self.message = "Un client attend sa commande."
   end
  end
  self.nextArrival = math.max(0, self.nextArrival - dt)
  for _, customer in self.customers do
   customer.patience = math.max(0, customer.patience - dt)
   if customer.patience <= 0 then
    self.phase = "Closed"; self.message = "Fermeture : patience epuisee."
   end
  end
  if self.timeRemaining <= 0 and #self.customers == 0 then
   self.phase = "Summary"; self.message = "Service termine. Passez au jour suivant."
  end
 end
 for id, state in self.players do
  local work = state.work
  if work then
   local station = findStation(self, work.targetId)
   local player = Players:GetPlayerByUserId(tonumber(id) :: number)
   if self.phase ~= "Service" or not station or not player or not nearby(player, station) then
    state.work = nil
    if station then station.progress = 0 end
    changed = true
   else
    work.elapsed += dt; station.progress = math.min(1, work.elapsed / WORK_SECONDS); changed = true
    if work.elapsed >= WORK_SECONDS then
     if station.kind == "Board" and station.state == "Lettuce" then station.state = "ChoppedLettuce"
     elseif station.kind == "Sink" and station.state == "DirtyPlate" then station.state = "CleanPlate" end
     station.progress = 0; state.work = nil
    elseif work.elapsed >= MAX_WORK_SECONDS then state.work = nil; station.progress = 0 end
   end
  end
 end
 if changed then self:_notify() end
end

function methods:handleAction(player: Player, action: string, payload: any): (boolean, string)
 if not self.running or not participant(player) then return false, "NotParticipant" end
 local id = tostring(player.UserId)
 local state = self.players[id]
 if not state then return false, "NotParticipant" end
 if type(action) ~= "string" or type(payload) ~= "table" then return false, "InvalidPayload" end
 if action == "SetReady" then
  if self.phase ~= "Preparation" then return false, "WrongPhase" end
  if type(payload.ready) ~= "boolean" then return false, "InvalidPayload" end
  self.readyPlayers[id] = payload.ready
  local allReady = true; local count = 0
  for _, ready in self.readyPlayers do count += 1; if not ready then allReady = false end end
  if count > 0 and allReady then self.phase = "Service"; self.message = "Service commence !" end
  self:_notify(); return true, "OK"
 elseif action == "NextDay" then
  if self.phase ~= "Summary" then return false, "WrongPhase" end
  self.day += 1; self.phase = "Preparation"; self:_reset()
  for key in self.players do self.readyPlayers[key] = false end
  self.message = "Preparez le prochain service."; self:_notify(); return true, "OK"
 elseif action == "EndWork" then
  if not state.work then return false, "NotWorking" end
  local station = findStation(self, state.work.targetId)
  if station then station.progress = 0 end
  state.work = nil; self:_notify(); return true, "OK"
 end
 if self.phase ~= "Service" then return false, "WrongPhase" end
 if type(payload.targetId) ~= "string" or #payload.targetId > 64 then return false, "InvalidPayload" end
 local station = findStation(self, payload.targetId)
 if not station then return false, "InvalidTarget" end
 if not nearby(player, station) then return false, "OutOfRange" end
 if state.work then return false, "Busy" end
 for _, other in self.players do
  if other.work and other.work.targetId == station.id then return false, "Occupied" end
 end
 if action == "PickUp" then
  if state.heldItem then return false, "Occupied" end
  if station.kind == "Ingredient" then state.heldItem = "Lettuce"
  elseif station.kind == "Table" and station.state == "DirtyPlate" then state.heldItem = "DirtyPlate"; station.state = "Empty"
  elseif station.state == "CleanPlate" or station.state == "Lettuce" or station.state == "ChoppedLettuce" or station.state == "Salad" or station.state == "DirtyPlate" then
   state.heldItem = station.state; station.state = "Empty"
  else return false, "Empty" end
 elseif action == "PutDown" then
  local item = state.heldItem
  if not item then return false, "EmptyHands" end
  if station.kind == "Board" and station.state == "ChoppedLettuce" and item == "CleanPlate" then
   station.state = "Salad"; state.heldItem = nil
  elseif station.kind == "Board" and station.state == "Empty" and (item == "Lettuce" or item == "ChoppedLettuce" or item == "Salad") then
   station.state = item; state.heldItem = nil
  elseif station.kind == "Counter" and station.state == "Empty" then station.state = item; state.heldItem = nil
  elseif station.kind == "Sink" and station.state == "Empty" and item == "DirtyPlate" then station.state = item; state.heldItem = nil
  elseif station.kind == "PlateRack" and station.state == "Empty" and item == "CleanPlate" then station.state = item; state.heldItem = nil
  else return false, "InvalidRecipe" end
 elseif action == "BeginWork" then
  if state.heldItem then return false, "Occupied" end
  if not ((station.kind == "Board" and station.state == "Lettuce") or (station.kind == "Sink" and station.state == "DirtyPlate")) then return false, "InvalidRecipe" end
  for _, other in self.players do if other.work and other.work.targetId == station.id then return false, "Occupied" end end
  state.work = {targetId = station.id, elapsed = 0}; station.progress = 0
 elseif action == "TakeOrder" then
  local customer = self.customers[1]
  if station.kind ~= "Table" or not customer or customer.state ~= "WaitingOrder" then return false, "InvalidTarget" end
  customer.state = "Ordered"; station.state = "Ordered"; self.message = "Commande : salade."
 elseif action == "Serve" then
  local customer = self.customers[1]
  if station.kind ~= "Table" or not customer or customer.state ~= "Ordered" or state.heldItem ~= "Salad" then return false, "InvalidRecipe" end
  state.heldItem = nil; self.customers = {}; station.state = "DirtyPlate"; self.money += 10
  self.message = "Salade servie : +10. Debarrassez et lavez."
 else return false, "InvalidAction" end
 self:_notify(); return true, "OK"
end

function methods:getSnapshot(_player: Player): {[string]: any}
 local stations = {}
 for _, station in self.stations do table.insert(stations, {id = station.id, kind = station.kind, cellX = station.cellX, cellZ = station.cellZ, state = station.state, progress = station.progress}) end
 local players = {}
 for id, state in self.players do players[id] = {heldItem = state.heldItem} end
 local readyPlayers = table.clone(self.readyPlayers)
 local customers = {}
 for _, customer in self.customers do table.insert(customers, {id = customer.id, order = customer.order, patience = customer.patience, state = customer.state}) end
 return {runId = self.runId, phase = self.phase, day = self.day, money = self.money, timeRemaining = self.timeRemaining, readyPlayers = readyPlayers, players = players, stations = stations, customers = customers, message = self.message}
end

return GameService
