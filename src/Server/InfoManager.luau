local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = workspace.Locations
local Waypoints = workspace.Waypoints

local Gui = script.Parent
local CallFrame = Gui.CallFrame

local ModuleFolder = ReplicatedStorage.Modules
local SoundModule = require(ModuleFolder.SoundModule)
local DispatchModule = require(ModuleFolder.DispatchModule)

local EventFolder = ReplicatedStorage.Events
local CallDataEvent = EventFolder.CallDataEvent
local CancelCallEvent = EventFolder.CancelCallEvent

local stationName: string = Gui:GetAttribute("Station")
local Station = ReplicatedStorage.Vehicles:FindFirstChild(stationName)
local Objects = workspace:FindFirstChild((stationName:gsub(" Units", "")) .. "StationObjects")

local CALL_SWITCH_DEBOUNCE = 1
local SOUND_DELAY = 0.5
local LIGHT_INTERVAL = 1

local CallField = {
	Priority = 1,
	Reason = 2,
	Location = 3,
	Units = 4,
	Channel = 5,
	Id = 6,
	Announced = 7,
}

type Call = { any }

local calls: { Call } = {}
local selectedCall = 0
local switchDebounce = false

script:SetAttribute("AlarmTimer", 0)
script:SetAttribute("LightsOn", false)

if not Station or not Objects then
	return
end

local function getActiveAttribute(locationName: string): string
	return (locationName:gsub(" ", "")) .. "Active"
end

local function getCallTitle(call: Call): string
	return call[CallField.Priority] .. " - " .. call[CallField.Location]
end

local function isAlarmExpired(): boolean
	return script:GetAttribute("AlarmTimer") >= DispatchModule.AlarmDuration
end

local function setLights(enabled: boolean)
	for _, light in Objects.Lights:GetChildren() do
		light.PointLight.Enabled = enabled
	end
end

local function clearSpeakers()
	for _, speaker in Objects.Speakers:GetChildren() do
		speaker:ClearAllChildren()
	end
end

local function flashLights(title: string)
	if script:GetAttribute("LightsOn") then
		return
	end

	script:SetAttribute("LightsOn", true)

	local function shouldStop(): boolean
		return not script:GetAttribute("LightsOn") or isAlarmExpired() or title ~= CallFrame.TopLabel.Text
	end

	repeat
		setLights(true)
		task.wait(LIGHT_INTERVAL)

		if shouldStop() then
			break
		end

		setLights(false)
		task.wait(LIGHT_INTERVAL)
	until shouldStop()

	if title == CallFrame.TopLabel.Text then
		script:SetAttribute("LightsOn", false)
		setLights(false)
	end
end

local function playAnnouncement(soundName: string, title: string): boolean
	local template = SoundModule[soundName]
	if not template then
		return false
	end

	local sounds = {}

	for _, speaker in Objects.Speakers:GetChildren() do
		local sound = template:Clone()
		sound.Parent = speaker
		table.insert(sounds, sound)
	end

	for _, sound in sounds do
		sound:Play()
	end

	task.wait(template.TimeLength)

	for _, sound in sounds do
		sound:Destroy()
	end

	task.wait(SOUND_DELAY)

	if title == CallFrame.TopLabel.Text then
		script:SetAttribute("AlarmTimer", script:GetAttribute("AlarmTimer") + SOUND_DELAY)
	end

	return true
end

local function announceCall(call: Call, index: number, title: string)
	call[CallField.Announced] = true
	script:SetAttribute("AlarmTimer", 0)

	local function shouldStop(): boolean
		return isAlarmExpired() or CallFrame.TopLabel.Text ~= title
	end

	repeat
		local played = false

		for _, unit in call[CallField.Units] do
			if isAlarmExpired() or index ~= selectedCall then
				break
			end

			played = playAnnouncement(unit, title) or played
		end

		for _, soundName in { call[CallField.Channel], call[CallField.Reason], call[CallField.Location] } do
			if shouldStop() then
				break
			end

			played = playAnnouncement(soundName, title) or played
		end

		if not played then
			task.wait(SOUND_DELAY)
			script:SetAttribute("AlarmTimer", script:GetAttribute("AlarmTimer") + SOUND_DELAY)
		end
	until shouldStop()
end

local function renderCall(call: Call)
	local index = selectedCall
	local title = getCallTitle(call)
	local list = CallFrame.UnitListFrame.List

	list:ClearAllChildren()

	local layout = script.UIListLayout:Clone()
	layout.Parent = list

	local function updateCanvas()
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

	CallFrame.TopLabel.Text = title
	CallFrame.ReasonLabel.Text = call[CallField.Reason]

	for _, unit in call[CallField.Units] do
		local frame = script.UnitFrame:Clone()
		frame.Label.Text = unit
		frame.Parent = list
	end

	updateCanvas()
	clearSpeakers()

	if not call[CallField.Announced] then
		announceCall(call, index, title)
	end
end

local function presentCall(call: Call)
	script:SetAttribute("LightsOn", false)

	if call[CallField.Announced] then
		setLights(false)
	else
		task.spawn(flashLights, getCallTitle(call))
	end

	task.spawn(renderCall, call)
end

local function onOngoingCallsChanged()
	if #calls == 0 then
		selectedCall = 0
	elseif selectedCall == 0 or selectedCall > #calls then
		selectedCall = 1
	end

	if selectedCall == 0 then
		script:SetAttribute("LightsOn", false)
		CallFrame.TopLabel.Text = ""
		CallFrame.Visible = false
		clearSpeakers()
		setLights(false)
		return
	end

	CallFrame.Visible = true
	presentCall(calls[selectedCall])
end

local function onCallCancelled(callId: string)
	for i = #calls, 1, -1 do
		if calls[i][CallField.Id] == callId then
			table.remove(calls, i)
			break
		end
	end

	Station:SetAttribute("OngoingCalls", #calls)

	if selectedCall > #calls then
		selectedCall = #calls
	end
end

local function onCallReceived(unitFolders: { Instance }, call: Call)
	if table.find(unitFolders, Station) then
		table.insert(calls, call)
		Station:SetAttribute("OngoingCalls", #calls)
	end
end

local function onNextPressed()
	if not CallFrame.Visible or switchDebounce then
		return
	end

	switchDebounce = true

	selectedCall += 1
	if selectedCall > #calls then
		selectedCall = 1
	end

	presentCall(calls[selectedCall])

	task.wait(CALL_SWITCH_DEBOUNCE)
	switchDebounce = false
end

local function onCancelPressed()
	local call = calls[selectedCall]
	if not CallFrame.Visible or not call then
		return
	end

	local locationName = call[CallField.Location]
	Locations:SetAttribute(getActiveAttribute(locationName), false)

	for _, teamWaypoints in Waypoints:GetChildren() do
		for _, waypoint in teamWaypoints:GetChildren() do
			if waypoint:IsA("BillboardGui") and waypoint.Adornee and waypoint.Adornee.Name == locationName then
				waypoint:Destroy()
			end
		end
	end

	script:SetAttribute("LightsOn", false)
	CancelCallEvent:Fire(call[CallField.Id])
end

CallFrame.Visible = false

CancelCallEvent.Event:Connect(onCallCancelled)
CallDataEvent.Event:Connect(onCallReceived)
Station:GetAttributeChangedSignal("OngoingCalls"):Connect(onOngoingCallsChanged)
CallFrame.Next.MouseButton1Click:Connect(onNextPressed)
CallFrame.CancelFrame.Button.MouseButton1Click:Connect(onCancelPressed)
