local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Locations = workspace:WaitForChild("Locations")
local Waypoints = workspace:WaitForChild("Waypoints")

local ModuleFolder = ReplicatedStorage.Modules
local DispatchModule = require(ModuleFolder.DispatchModule)

local EventFolder = ReplicatedStorage.Events
local DispatchEvent = EventFolder.DispatchEvent
local CallDataEvent = EventFolder.CallDataEvent

local CHANNELS = {
	["Channel 1"] = "webbyhook booyah",
	["FireTAC 1"] = "can you just put the webhook here",
	["Firegrounds"] = "webhook here yada yada boom bow",
}

local DEFAULT_EMBED_COLOR = 16777215

local ServerAction = {
	Submit = 1,
	OpenWithTool = 2,
}

local ClientAction = {
	CloseInterface = 1,
	ShowWaypoint = 2,
}

type Session = {
	Gui: ScreenGui,
	Connections: { RBXScriptConnection },
}

type CallRequest = {
	Priority: string,
	Units: { string },
	Reason: string,
	Location: string,
	Channel: string,
}

local sessions: { [Player]: Session } = {}
local unitToFolder: { [string]: Instance } = {}

local function getActiveAttribute(locationName: string): string
	return (locationName:gsub(" ", "")) .. "Active"
end

local function getWaypointFolderName(unitFolder: Instance): string
	return (unitFolder.Name:gsub(" Units", "")) .. " Waypoints"
end

local function createLocation(name: string, position: Vector3): Part
	Locations:SetAttribute(getActiveAttribute(name), false)

	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Position = position
	part.Parent = Locations

	return part
end

local function createWaypoint(priority, reason: string, location: BasePart): BillboardGui
	local waypoint = DispatchModule.GUI.BillboardGui:Clone()
	waypoint.MainFrame.Marker.Image = priority.Marker
	priority.Gradient:Clone().Parent = waypoint.MainFrame
	waypoint.MainFrame.ReasonLabel.Text = reason
	waypoint.MainFrame.LocationLabel.Text = location.Name
	waypoint.Adornee = location

	return waypoint
end

local function syncTeamAttribute(player: Player)
	player:SetAttribute("Team", if player.Team then player.Team.Name else nil)
end

local function closeSession(player: Player)
	local session = sessions[player]
	if not session then
		return
	end

	sessions[player] = nil

	for _, connection in session.Connections do
		connection:Disconnect()
	end

	session.Gui:Destroy()
	DispatchEvent:FireClient(player, ClientAction.CloseInterface)
end

local function openSession(player: Player, requiredTool: string?)
	local character = player.Character
	if not character or sessions[player] or player.Team ~= DispatchModule.DispatcherTeam then
		return
	end

	if requiredTool and not character:FindFirstChild(requiredTool) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local connections = {
		humanoid.Died:Connect(function()
			closeSession(player)
		end),
	}

	if requiredTool then
		table.insert(
			connections,
			character.ChildRemoved:Connect(function(child)
				if child.Name == requiredTool then
					closeSession(player)
				end
			end)
		)
	end

	local gui = DispatchModule.GUI.ScreenGui:Clone()
	gui.Parent = player.PlayerGui

	sessions[player] = {
		Gui = gui,
		Connections = connections,
	}
end

local function findPriority(name: string)
	for _, priority in DispatchModule.CallPriorities do
		if priority.Name == name then
			return priority
		end
	end

	return nil
end

local function parseRequest(selected: any): CallRequest?
	if typeof(selected) ~= "table" then
		return nil
	end

	local priority, units, reason, location, channel = selected[1], selected[2], selected[3], selected[4], selected[5]

	if
		typeof(priority) ~= "string"
		or typeof(units) ~= "table"
		or typeof(reason) ~= "string"
		or typeof(location) ~= "string"
		or typeof(channel) ~= "string"
	then
		return nil
	end

	local unitList = {}
	for _, unit in ipairs(units) do
		if typeof(unit) ~= "string" then
			return nil
		end
		table.insert(unitList, unit)
	end

	return {
		Priority = priority,
		Units = unitList,
		Reason = reason,
		Location = location,
		Channel = channel,
	}
end

local function resolveUnitFolders(units: { string }): { Instance }?
	local folders = {}

	for _, unit in units do
		local folder = unitToFolder[unit]
		if not folder or folder:GetAttribute("OngoingCalls") >= DispatchModule.MaxCalls then
			return nil
		end

		if not table.find(folders, folder) then
			table.insert(folders, folder)
		end
	end

	return folders
end

local function postWebhook(player: Player, request: CallRequest, priority)
	local embed = {
		title = request.Priority .. " Call",
		color = if typeof(priority.Color) == "number" then priority.Color else DEFAULT_EMBED_COLOR,
		fields = {
			{ name = "Caller", value = player.Name .. " - " .. game.JobId, inline = false },
			{ name = "Reason", value = request.Reason, inline = false },
			{ name = "Location", value = request.Location, inline = false },
			{
				name = "Units",
				value = if #request.Units > 0 then table.concat(request.Units, "\n") else "None",
				inline = false,
			},
		},
		timestamp = DateTime.now():ToIsoDate(),
	}

	local url = CHANNELS[request.Channel]
	local body = HttpService:JSONEncode({ embeds = { embed } })

	task.spawn(function()
		local success, err = pcall(HttpService.PostAsync, HttpService, url, body, Enum.HttpContentType.ApplicationJson)
		if not success then
			warn("[Dispatch] Webhook failed:", err)
		end
	end)
end

local function createCall(player: Player, request: CallRequest, priority, unitFolders: { Instance })
	if #unitFolders > 0 then
		Locations:SetAttribute(getActiveAttribute(request.Location), true)

		CallDataEvent:Fire(unitFolders, {
			request.Priority,
			request.Reason,
			request.Location,
			request.Units,
			request.Channel,
			HttpService:GenerateGUID(false),
			false,
		})

		for _, unitFolder in unitFolders do
			local teamWaypoints = Waypoints:FindFirstChild(getWaypointFolderName(unitFolder))
			if teamWaypoints then
				local waypoint = createWaypoint(priority, request.Reason, DispatchModule.Locations[request.Location])
				waypoint.Parent = teamWaypoints
				DispatchEvent:FireAllClients(ClientAction.ShowWaypoint, waypoint)
			end
		end
	end

	if DispatchModule.Log == true then
		postWebhook(player, request, priority)
	end
end

local function onSubmit(player: Player, selected: any)
	if player.Team ~= DispatchModule.DispatcherTeam or not sessions[player] then
		return
	end

	closeSession(player)

	local request = parseRequest(selected)
	if not request then
		return
	end

	local priority = findPriority(request.Priority)

	if
		not priority
		or not CHANNELS[request.Channel]
		or not DispatchModule.Locations[request.Location]
		or Locations:GetAttribute(getActiveAttribute(request.Location)) ~= false
		or not table.find(DispatchModule.CallTypes, request.Reason)
	then
		return
	end

	local unitFolders = resolveUnitFolders(request.Units)
	if not unitFolders then
		return
	end

	createCall(player, request, priority, unitFolders)
end

local function onPlayerAdded(player: Player)
	syncTeamAttribute(player)

	player:GetPropertyChangedSignal("Team"):Connect(function()
		if player.Team ~= DispatchModule.DispatcherTeam then
			closeSession(player)
		end

		syncTeamAttribute(player)
	end)
end

for _, board in CollectionService:GetTagged(DispatchModule.InfoBoardTag) do
	local manager = script.InfoManager:Clone()
	manager.Parent = board
	manager.Enabled = true
end

for name, position in DispatchModule.Locations do
	DispatchModule.Locations[name] = createLocation(name, position)
end

for _, unitFolder in DispatchModule.UnitFolders do
	local teamWaypoints = Instance.new("Folder")
	teamWaypoints.Name = getWaypointFolderName(unitFolder)
	teamWaypoints.Parent = Waypoints

	unitFolder:SetAttribute("OngoingCalls", 0)

	for _, unit in unitFolder:GetChildren() do
		unitToFolder[unit.Name] = unitFolder
	end
end

for _, prompt in CollectionService:GetTagged(DispatchModule.PromptTag) do
	prompt.Triggered:Connect(function(player)
		openSession(player)
	end)
end

DispatchEvent.OnServerEvent:Connect(function(player, action, selected)
	if action == ServerAction.Submit then
		onSubmit(player, selected)
	elseif action == ServerAction.OpenWithTool then
		openSession(player, DispatchModule.DispatchToolName)
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(closeSession)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
