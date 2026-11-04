local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Waypoints = workspace:WaitForChild("Waypoints")

local ModuleFolder = ReplicatedStorage.Modules
local DispatchModule = require(ModuleFolder.DispatchModule)

local EventFolder = ReplicatedStorage.Events
local DispatchEvent = EventFolder.DispatchEvent

local ClientAction = {
	EnablePrompts = 1,
	ShowWaypoint = 2,
}

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local tracked: { [BillboardGui]: boolean } = {}

local function getTeamWaypointFolder(): Instance?
	local team = LocalPlayer.Team
	if not team then
		return nil
	end

	return Waypoints:FindFirstChild(team.Name .. " Waypoints")
end

local function getFlatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function refreshWaypoints()
	local teamFolder = getTeamWaypointFolder()

	for _, folder in Waypoints:GetChildren() do
		for _, waypoint in folder:GetChildren() do
			if waypoint:IsA("BillboardGui") then
				local belongsToTeam = folder == teamFolder
				waypoint.Enabled = belongsToTeam
				tracked[waypoint] = if belongsToTeam then true else nil
			end
		end
	end
end

local function onHeartbeat()
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local teamFolder = getTeamWaypointFolder()

	for waypoint in tracked do
		if not waypoint.Parent or waypoint.Parent ~= teamFolder then
			tracked[waypoint] = nil
		elseif
			waypoint.Adornee
			and getFlatDistance(rootPart.Position, waypoint.Adornee.Position) <= DispatchModule.GUI.DistanceToDisappear
		then
			waypoint.Enabled = false
			tracked[waypoint] = nil
		end
	end
end

local function onDispatchEvent(action: number, waypoint: BillboardGui?)
	if action == ClientAction.EnablePrompts then
		for _, prompt in CollectionService:GetTagged(DispatchModule.PromptTag) do
			prompt.Enabled = true
		end
	elseif action == ClientAction.ShowWaypoint then
		local teamFolder = getTeamWaypointFolder()

		if waypoint and teamFolder and waypoint.Parent == teamFolder then
			waypoint.Enabled = true
			tracked[waypoint] = true
		end
	end
end

local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	refreshWaypoints()
end

DispatchEvent.OnClientEvent:Connect(onDispatchEvent)
LocalPlayer:GetPropertyChangedSignal("Team"):Connect(refreshWaypoints)
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
RunService.Heartbeat:Connect(onHeartbeat)

refreshWaypoints()
