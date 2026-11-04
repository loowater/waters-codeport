-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
-- Variables
local GUIObjects = ReplicatedStorage.GUIObjects
-- Module
local Dispatch = {
	DispatcherTeam = Teams.Dispatchers,
	PromptTag = "DispatchPrompts",
	InfoBoardTag = "InfoBoard",
	DispatchToolName = "DispatchTool",
	MaxCalls = 5,
	AlarmDuration = 5,
	Log = false, 
	CallPriorities = {
		[1] = {Name = "Standard", Color = 16711680, Marker = "rbxassetid://1195495135", Gradient = GUIObjects.DispatchGUI.Container.MainFrame.TopBar.Priority1.UIGradient},
		[2] = {Name = "Special", Color = 255, Marker = "rbxassetid://5639840603", Gradient = GUIObjects.DispatchGUI.Container.MainFrame.TopBar.Priority2.UIGradient},
		[3] = {Name = "Balance", Color = 65280, Marker = "rbxassetid://6976119485", Gradient = GUIObjects.DispatchGUI.Container.MainFrame.TopBar.Priority3.UIGradient},
	},
	UnitFolders = {
		ReplicatedStorage.Vehicles["Team1 Units"],
		ReplicatedStorage.Vehicles["Team2 Units"],
	},
	CallTypes = {
		"Medical Emergency",
		"Robbery",
		"Trouble Breathing",
		"Chest Pain",
		"Structure Fire",
		"Residential Fire",
		"Unstable Patient",
		"PANIC Alarm",
	},
	Channels = {
		"Channel 1",
		"FireTAC 1",
		"Firegrounds",
	},
	Locations = {
		["Location 1"] = Vector3.new(87, 100, -133),
	},
	GUI = {
		BillboardGui = GUIObjects.WaypointGUI,
		DistanceToDisappear = 50,
		ScreenGui = GUIObjects.DispatchGUI,
		ArrowID = "rbxassetid://8539638324",
		CheckMarkID = "rbxassetid://12690727184",
	},
}
return Dispatch