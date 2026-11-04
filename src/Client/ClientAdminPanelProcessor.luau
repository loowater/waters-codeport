--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Player = assert(Players.LocalPlayer)
local SharedModules = ReplicatedStorage.SharedModules
local PlayerGui = Player and Player.PlayerGui
local Source = ReplicatedStorage.Source
local AdminPanelUI = PlayerGui:WaitForChild('AdminPanel')
local AdminPanelContentFrame = AdminPanelUI.MainFrame.Content
local AdminPanelNavBar = AdminPanelUI.MainFrame.NavBar
local AdminPanelCloseButton = AdminPanelUI.MainFrame.CloseBtn
local Remotes = script.Parent.Parent.Remotes

local BrainrotRegistry = require(Source.Brainrot.Core.BrainrotRegistry)
local BrainrotManager = require(Source.Brainrot.Core.BrainrotManager)
local EventRegistry = require(Source.Event.Core.EventRegistry)
local EventManager = require(Source.Event.Core.EventManager)
local GunRegistry = require(Source.Gun.Core.GunRegistry)
local GunManager = require(Source.Gun.Core.GunManager)
local TimeUtil = require(SharedModules.Utils.TimeUtil)
local Tick = require(Source.Util.Tick)

BrainrotManager.defineBrainrotClasses()
BrainrotManager.defineRarityTiers()
EventManager.defineEvents()
GunManager.defineGunConfigs()

local ClientAdminPanelProcessor = {}

local eventCards = {}

ClientAdminPanelProcessor.announcementFadeTime = .5
ClientAdminPanelProcessor.showingError = false
ClientAdminPanelProcessor.errorQueue = {}
ClientAdminPanelProcessor.eventTimerActive = false

export type Tab = {
	name: string,
	button: TextButton,
	container: ScrollingFrame,
}

export type ActiveEvent = EventRegistry.ActiveEvent

ClientAdminPanelProcessor.adminTabs = {
	announcements = {
		name = 'announcements',
		button = AdminPanelNavBar.AnnouncementsBtn,
		container = AdminPanelContentFrame.AnnouncementsTab,
	},
	brainrot_spawn = {
		name = 'brainrot_spawn',
		button = AdminPanelNavBar.BrainrotSpawnBtn,
		container = AdminPanelContentFrame.BrainrotSpawnTab,
	},
	events = {
		name = 'events',
		button = AdminPanelNavBar.EventsBtn,
		container = AdminPanelContentFrame.EventsTab,
	},
	tools = {
		name = 'tools',
		button = AdminPanelNavBar.ToolsBtn,
		container = AdminPanelContentFrame.ToolsTab,
	},
	troll_panel = {
		name = 'troll_panel',
		button = AdminPanelNavBar.TrollBtn,
		container = AdminPanelContentFrame.TrollPanelTab,
	},
}::{[string]: Tab}

ClientAdminPanelProcessor.defaultAdminPanelTab = 'brainrot_spawn'
ClientAdminPanelProcessor.currentAdminTab = nil::string?

local function tween(obj, goal)
	return TweenService:Create(
		obj,
		TweenInfo.new(ClientAdminPanelProcessor.announcementFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
end

function ClientAdminPanelProcessor.init()
	ClientAdminPanelProcessor.stopEventTimer()
	ClientAdminPanelProcessor.setupAdminPanelButtons()
	ClientAdminPanelProcessor.setupAdminPanelHotkey()
	ClientAdminPanelProcessor.setupTabSwitching()
	ClientAdminPanelProcessor.hideAdminPanel()
	ClientAdminPanelProcessor.initBrainrotSpawnTab()
	ClientAdminPanelProcessor.initEventsTab()
	ClientAdminPanelProcessor.initAnnouncementsTab()
	ClientAdminPanelProcessor.initToolsTab()
	ClientAdminPanelProcessor.initTrollPanelTab()
end

function ClientAdminPanelProcessor.setupAdminPanelButtons()
	AdminPanelCloseButton.Active = true
	AdminPanelCloseButton.Activated:Connect(function()
		ClientAdminPanelProcessor.hideAdminPanel()
	end)
end

function ClientAdminPanelProcessor.setupAdminPanelHotkey()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then return end
		if input.KeyCode ~= Enum.KeyCode.J then return end
		if AdminPanelUI.MainFrame.Visible then
			ClientAdminPanelProcessor.hideAdminPanel()
		else
			ClientAdminPanelProcessor.showAdminPanel()
		end
	end)
end

function ClientAdminPanelProcessor.setupTabSwitching()
	for _, tab in ClientAdminPanelProcessor.adminTabs do
		local name = tab.name
		local button = tab.button
		button.Active = true
		button.Activated:Connect(function()
			ClientAdminPanelProcessor.switchToTab(name)
		end)
		if ClientAdminPanelProcessor.defaultAdminPanelTab == name then
			ClientAdminPanelProcessor.switchToTab(name)
		end
	end
end

function ClientAdminPanelProcessor.switchToTab(tabName: string)
	if ClientAdminPanelProcessor.currentAdminTab == tabName then return end
	if ClientAdminPanelProcessor.currentAdminTab ~= nil and ClientAdminPanelProcessor.currentAdminTab ~= tabName then
		local currentTab: Tab = ClientAdminPanelProcessor.adminTabs[ClientAdminPanelProcessor.currentAdminTab]
		if currentTab then
			currentTab.container.Visible = false
			currentTab.button.TextColor3 = Color3.new(1, 1, 1)
		end
		ClientAdminPanelProcessor.currentAdminTab = nil
	end
	local newTab = ClientAdminPanelProcessor.adminTabs[tabName]
	if newTab then
		ClientAdminPanelProcessor.currentAdminTab = newTab.name
		newTab.container.Visible = true
		newTab.button.TextColor3 = Color3.new(0, 1, 0)
	end
end

function ClientAdminPanelProcessor.showError(text: string, duration: number)
	ClientAdminPanelProcessor.showFeedback(text, Color3.new(1, 0, 0), duration)
end

function ClientAdminPanelProcessor.showSuccess(text: string, duration: number)
	ClientAdminPanelProcessor.showFeedback(text, Color3.new(0, 1, 0), duration)
end

function ClientAdminPanelProcessor.showFeedback(text: string, textColor: Color3, duration: number)
	if ClientAdminPanelProcessor.showingError then
		table.insert(ClientAdminPanelProcessor.errorQueue, text)
		return
	end
	local currentTabName = ClientAdminPanelProcessor.currentAdminTab
	if not currentTabName then return end
	local tab: Tab? = ClientAdminPanelProcessor.adminTabs[currentTabName]
	if not tab then return end
	local errorTextLabel = AdminPanelContentFrame.Errors
	if not errorTextLabel then
		warn('Error text label not found in tab', tab.name)
		return
	end
	ClientAdminPanelProcessor.showingError = true
	errorTextLabel.Text = text
	errorTextLabel.TextColor3 = textColor
	errorTextLabel.Visible = true
	tween(errorTextLabel, {TextTransparency = 0}):Play()
	task.wait(ClientAdminPanelProcessor.announcementFadeTime + duration)
	tween(errorTextLabel, {TextTransparency = 1}):Play()
	task.wait(ClientAdminPanelProcessor.announcementFadeTime)
	ClientAdminPanelProcessor.showingError = false
	errorTextLabel.Visible = false
	if #ClientAdminPanelProcessor.errorQueue > 0 then
		local nextText = table.remove(ClientAdminPanelProcessor.errorQueue, 1)
		if not nextText then return end
		ClientAdminPanelProcessor.showFeedback(nextText, textColor, duration)
	end
end

function ClientAdminPanelProcessor.showAdminPanel()
	AdminPanelUI.MainFrame.Visible = true
end

function ClientAdminPanelProcessor.hideAdminPanel()
	AdminPanelUI.MainFrame.Visible = false
end

function ClientAdminPanelProcessor.requestExecuteCommand(commandText: string)
	: {ok: boolean, err: string?}
	return Remotes.RequestExecuteCommand:InvokeServer(commandText)
end

function ClientAdminPanelProcessor.requestExecuteCommandWithArgs(commandName: string, args: {[string]: any})
	: {ok: boolean, err: string?}
	return Remotes.RequestExecuteCommandWithArgs:InvokeServer(commandName, args)
end

function ClientAdminPanelProcessor.toggleHighlightButton(button: GuiButton, color: Color3, enabled: boolean)
	if enabled then
		if not button:GetAttribute('OriginalBackgroundColor') then
			button:SetAttribute('OriginalBackgroundColor', button.BackgroundColor3)
		end
		button.BackgroundColor3 = color
	elseif button:GetAttribute('OriginalBackgroundColor') then
		button.BackgroundColor3 = button:GetAttribute('OriginalBackgroundColor')
	end
end

function ClientAdminPanelProcessor.toggleHighlightActive(button: GuiButton, enabled: boolean)
	ClientAdminPanelProcessor.toggleHighlightButton(button, Color3.new(0, 0, 1), enabled)
end

function ClientAdminPanelProcessor.toggleHighlightSelected(button: GuiButton, enabled: boolean)
	ClientAdminPanelProcessor.toggleHighlightButton(button, Color3.new(0, 1, 0), enabled)
end

function ClientAdminPanelProcessor.toggleStartEventButton(enabled: boolean)
	local tab = assert(ClientAdminPanelProcessor.adminTabs['events'], `Events tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.EventsTab)
	local startEventBtn = container.StartEvent
	startEventBtn.Active = enabled
	startEventBtn.AutoButtonColor = enabled
	local stopEventBtn = container.StopEvent
	stopEventBtn.Active = not enabled
	stopEventBtn.AutoButtonColor = not enabled
	if enabled then
		startEventBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
		stopEventBtn.BackgroundColor3 = Color3.fromRGB(125, 125, 125)
		startEventBtn.Text = 'Start Event'
	else
		startEventBtn.BackgroundColor3 = Color3.fromRGB(125, 125, 125)
		stopEventBtn.BackgroundColor3 = Color3.fromRGB(180, 113, 4)
		startEventBtn.Text = 'Event already active'
	end
end

function ClientAdminPanelProcessor.updateEventTimer(timeLeft: number)
	local tab = assert(ClientAdminPanelProcessor.adminTabs['events'], `Events tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.EventsTab)
	if timeLeft <= 0 then
		container.TimerDisplay.Text = 'No event running'
		return
	end
	container.TimerDisplay.Text = (TimeUtil.ConvertToMS :: (number) -> string)(timeLeft)
end

function ClientAdminPanelProcessor.initBrainrotSpawnTab()
	local tab = assert(ClientAdminPanelProcessor.adminTabs['brainrot_spawn'], `Brainrot spawn tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.BrainrotSpawnTab)

	local spawnForServerButton = container.SpawnForServer
	local spawnForAllServersButton = container.SpawnForAllServers

	local selectedBrainrotClass: BrainrotRegistry.BrainrotClass? = nil
	local selectedRarityId: string? = nil
	local selectedVariantId: string? = nil

	local rarityButtons: {[string]: string} = {
		CommonSpawn    = 'common',
		RareSpawn      = 'rare',
		MythicSpawn    = 'mythic',
		LegendarySpawn = 'legendary',
		EternalSpawn   = 'eternal',
	}

	local variantButtons: {[string]: string} = {
		GoldenSpawn = 'golden',
		UndeadSpawn = 'undead',
	}

	for buttonName, rarityId in rarityButtons do
		local button = container:FindFirstChild(buttonName) :: TextButton
		if not button then
			warn(`BrainrotSpawnTab: rarity button '{buttonName}' not found`)
			continue
		end
		button.Active = true
		button.Activated:Connect(function()
			selectedRarityId = rarityId
			for otherName in rarityButtons do
				local otherButton = container:FindFirstChild(otherName) :: TextButton
				if otherButton then
					ClientAdminPanelProcessor.toggleHighlightSelected(
						otherButton :: GuiButton,
						otherName == buttonName
					)
				end
			end
		end)
	end

	for buttonName, variantId in variantButtons do
		local button = container:FindFirstChild(buttonName) :: TextButton
		if not button then
			warn(`BrainrotSpawnTab: variant button '{buttonName}' not found`)
			continue
		end
		button.Active = true
		button.Activated:Connect(function()
			if selectedVariantId == variantId then
				selectedVariantId = nil
				ClientAdminPanelProcessor.toggleHighlightSelected(button :: GuiButton, false)
			else
				selectedVariantId = variantId
				for otherName in variantButtons do
					local otherButton = container:FindFirstChild(otherName) :: TextButton
					if otherButton then
						ClientAdminPanelProcessor.toggleHighlightSelected(
							otherButton :: GuiButton,
							otherName == buttonName
						)
					end
				end
			end
		end)
	end

	local function getValidatedInputs(): (string?, string?, string?)
		if not selectedBrainrotClass then
			ClientAdminPanelProcessor.showError('No brainrot class selected', 2)
			return nil, nil, nil
		end
		if not selectedRarityId then
			ClientAdminPanelProcessor.showError('No rarity selected', 2)
			return nil, nil, nil
		end
		return selectedBrainrotClass.id, selectedRarityId, selectedVariantId
	end

	spawnForServerButton.Activated:Connect(function()
		local classId, rarityId, variantId = getValidatedInputs()
		if not classId then return end
		local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
			'spawnBrainrotForServer',
			{ class = classId, rarity = rarityId, variant = variantId }
		)
		if result.ok then
			ClientAdminPanelProcessor.showSuccess('Successfully spawned for this server', 3)
		else
			ClientAdminPanelProcessor.showError(assert(result.err), 3)
		end
	end)

	spawnForAllServersButton.Activated:Connect(function()
		local classId, rarityId, variantId = getValidatedInputs()
		if not classId then return end
		local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
			'spawnBrainrotForAllServers',
			{ class = classId, rarity = rarityId, variant = variantId }
		)
		if result.ok then
			ClientAdminPanelProcessor.showSuccess('Successfully broadcast spawn to all servers', 3)
		else
			ClientAdminPanelProcessor.showError(assert(result.err), 3)
		end
	end)

	local template = container.TypeDropdown.Template
	template.Visible = false
	local classCards: {[string]: TextButton} = {}

	for _, class in BrainrotRegistry.brainrotClasses do
		local card = template:Clone() :: TextButton
		classCards[class.id] = card
		card.Text = class.id
		card.Active = true
		card.Activated:Connect(function()
			selectedBrainrotClass = class
			for otherId, otherCard in classCards do
				ClientAdminPanelProcessor.toggleHighlightSelected(
					otherCard :: GuiButton,
					otherId == class.id
				)
			end
		end)
		card.Visible = true
		card.Parent = container.TypeDropdown
	end
end

function ClientAdminPanelProcessor.initEventsTab()
	local tab = assert(ClientAdminPanelProcessor.adminTabs['events'], `Events tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.EventsTab)
	local startEventButton = container.StartEvent
	local stopEventButton = container.StopEvent
	local selectedEvent: EventRegistry.Event? = nil

	stopEventButton.Active = true
	stopEventButton.Activated:Connect(function()
		local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
			'stopEvent',
			{ reason = 'Admin stopped event' }
		)
		if result.ok then
			ClientAdminPanelProcessor.showSuccess(result.err or 'Successfully stopped active event', 3)
		else
			ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
		end
	end)

	startEventButton.Active = true
	startEventButton.Activated:Connect(function()
		if not selectedEvent then
			ClientAdminPanelProcessor.showError('No event selected', 3)
			return
		end
		local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
			'startEvent',
			{ eventName = selectedEvent.id, duration = 30 }
		)
		if result.ok then
			ClientAdminPanelProcessor.showSuccess('Successfully started event', 3)
		else
			ClientAdminPanelProcessor.showError(assert(result.err), 3)
		end
	end)

	local template = container.EventList.Template
	template.Visible = false

	for _, event in EventRegistry.events do
		local card = template:Clone()
		eventCards[event.id] = card
		card.Visible = true
		card.Text = event.displayName
		card.Active = true
		card.Activated:Connect(function()
			selectedEvent = event
			ClientAdminPanelProcessor.toggleHighlightSelected(card, true)
			for _, otherCard in eventCards do
				if otherCard == card then continue end
				ClientAdminPanelProcessor.toggleHighlightActive(otherCard, false)
				ClientAdminPanelProcessor.toggleHighlightSelected(otherCard, false)
			end
		end)
		card.Parent = container.EventList
	end

	local adminButtons: {[string]: any} = {
		-- Spawns a random lucky block type on the road
		SpawnRandomLuckyBlock = function()
			local blockTypes = {'common', 'rare', 'mythic', 'undead'}
			local randomType = blockTypes[math.random(#blockTypes)]
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				'spawnLuckyBlock',
				{ type = randomType }
			)
			if result.ok then
				ClientAdminPanelProcessor.showSuccess(`Spawned {randomType} lucky block on the road!`, 3)
			else
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
			end
		end,
		EventVoice = function()
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				'eventVoice', {}
			)
			if result.ok then
				ClientAdminPanelProcessor.showSuccess('Playing EventVoice!', 3)
			else
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
			end
		end,
		SkyEffectPink = function()
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				'skyEffect',
				{ preset = 'pink' }
			)
			if result.ok then
				ClientAdminPanelProcessor.showSuccess('Sky set to pink', 3)
			else
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
			end
		end,
		SkyEffectGreen = function()
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				'skyEffect',
				{ preset = 'green' }
			)
			if result.ok then
				ClientAdminPanelProcessor.showSuccess('Sky set to green', 3)
			else
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
			end
		end,
		SkyEffectRed = function()
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				'skyEffect',
				{ preset = 'red' }
			)
			if result.ok then
				ClientAdminPanelProcessor.showSuccess('Sky set to red', 3)
			else
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
			end
		end,
	}

	for buttonName, handler in adminButtons do
		local button = container.AdminList:FindFirstChild(buttonName) :: TextButton
		if not button then
			warn(`EventsTab AdminList: button '{buttonName}' not found`)
			continue
		end
		button.Active = true
		button.Activated:Connect(handler)
	end
end

function ClientAdminPanelProcessor.initAnnouncementsTab()
	local tab = assert(ClientAdminPanelProcessor.adminTabs['announcements'], `Announcements tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.AnnouncementsTab)
	local sendAnnouncementButton = container.SendBtn
	local textBox = container.MessageInput

	sendAnnouncementButton.Active = true
	sendAnnouncementButton.Activated:Connect(function()
		local announcement = textBox.Text
		if #announcement == 0 then
			ClientAdminPanelProcessor.showError('No text input!', 3)
			return
		end
		local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
			'serverAnnounce',
			{ message = announcement }
		)
		if result.ok then
			ClientAdminPanelProcessor.showSuccess(result.err or 'Success', 3)
		else
			ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
		end
	end)
end

function ClientAdminPanelProcessor.initToolsTab()
	local tab = assert(ClientAdminPanelProcessor.adminTabs['tools'], `Tools tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.ToolsTab)

	local template = container.Template
	template.Visible = false

	for _, gunConfig in GunRegistry.gunConfigs do
		local card = template:Clone()
		card.Text = gunConfig.name
		card.Visible = true
		card.Active = true
		card.Activated:Connect(function()
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				'spawnGun',
				{ player = 'me', gunName = gunConfig.name }
			)
			if result.ok then
				ClientAdminPanelProcessor.showSuccess(result.err or 'Successfully spawned gun', 3)
			else
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
			end
		end)
		card.Parent = container
	end
end

function ClientAdminPanelProcessor.initTrollPanelTab()
	local tab = assert(ClientAdminPanelProcessor.adminTabs['troll_panel'], `Troll panel tab not found`)
	local container = tab.container::typeof(AdminPanelContentFrame.TrollPanelTab)
	local playerUsernameBox = container.PlayerUsername
	local executeBtn = container.ExecuteCmd
	local refreshBtn = container.RefreshCmd :: TextButton

	local selectedTrollCommands: {[string]: boolean} = {}
	local bestMatchName: string? = nil

	local trollButtons: {[string]: string} = {
		FlingUser         = 'flingUser',
		JumpscareUser     = 'jumpscareUser',
		EnlargeUser       = 'enlargeUser',
		MakeUserSmallUser = 'makeUserSmall',
		SpeedUser         = 'makeUserSpeedy',
		AntiStealUser     = 'antiSteal',
		InvisibleUser     = 'invisibleUser',
		BlindUser         = 'blindUser',
		FlyUser           = 'flyUser',
		ExplodeUser       = 'explodeUser',
	}

	for buttonName, commandName in trollButtons do
		local button = container.TypeDropdown:FindFirstChild(buttonName) :: TextButton
		if not button then
			warn(`TrollPanelTab: button '{buttonName}' not found`)
			continue
		end
		button.Active = true
		button.Activated:Connect(function()
			if selectedTrollCommands[commandName] then
				selectedTrollCommands[commandName] = nil
				ClientAdminPanelProcessor.toggleHighlightSelected(button :: GuiButton, false)
			else
				selectedTrollCommands[commandName] = true
				ClientAdminPanelProcessor.toggleHighlightSelected(button :: GuiButton, true)
			end
		end)
	end

	executeBtn.Active = true
	executeBtn.Activated:Connect(function()
		local username = playerUsernameBox.Text
		if #username == 0 then
			ClientAdminPanelProcessor.showError('No player username entered', 3)
			return
		end
		local commandList = {}
		for commandName in selectedTrollCommands do
			table.insert(commandList, commandName)
		end
		if #commandList == 0 then
			ClientAdminPanelProcessor.showError('No troll action selected', 3)
			return
		end
		local anyFailed = false
		for _, commandName in commandList do
			local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
				commandName,
				{ player = username }
			)
			if not result.ok then
				ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
				anyFailed = true
			end
		end
		if not anyFailed then
			ClientAdminPanelProcessor.showSuccess(
				`Executed {#commandList} command(s) on {username}`,
				3
			)
		end
	end)

	refreshBtn.Active = true
	refreshBtn.Activated:Connect(function()
		local username = playerUsernameBox.Text
		if #username == 0 then
			ClientAdminPanelProcessor.showError('No player username entered', 3)
			return
		end
		local result = ClientAdminPanelProcessor.requestExecuteCommandWithArgs(
			'refreshUser',
			{ player = username }
		)
		if result.ok then
			ClientAdminPanelProcessor.showSuccess(result.err or 'Successfully refreshed player', 3)
		else
			ClientAdminPanelProcessor.showError(result.err or 'Unknown error', 3)
		end
	end)

	playerUsernameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = playerUsernameBox.Text
		if #text == 0 then
			playerUsernameBox.PlaceholderText = 'Player Username..'
			bestMatchName = nil
			return
		end
		local lowerText = string.lower(text)
		local found: Player? = nil
		for _, player in Players:GetPlayers() do
			if string.find(string.lower(player.Name), lowerText, 1, true) then
				found = player
				break
			end
		end
		if found then
			bestMatchName = found.Name
			playerUsernameBox.PlaceholderText = `Found: {found.Name}`
		else
			bestMatchName = nil
			playerUsernameBox.PlaceholderText = 'No player found..'
		end
	end)

	playerUsernameBox.FocusLost:Connect(function()
		if bestMatchName then
			playerUsernameBox.Text = bestMatchName
		end
	end)
end

function ClientAdminPanelProcessor.startEventTimer(activeEvent: ActiveEvent)
	if ClientAdminPanelProcessor.eventTimerActive then return end
	ClientAdminPanelProcessor.eventTimerActive = true
	ClientAdminPanelProcessor.toggleStartEventButton(false)
	for id, card in eventCards do
		ClientAdminPanelProcessor.toggleHighlightSelected(card, false)
		ClientAdminPanelProcessor.toggleHighlightActive(card, false)
		if id == activeEvent.eventId then
			ClientAdminPanelProcessor.toggleHighlightActive(card, true)
		end
	end
	local function updateEventTimer(dt: number)
		if not ClientAdminPanelProcessor.eventTimerActive then return end
		ClientAdminPanelProcessor.tickEventTimer(activeEvent, dt);
		(Tick.Interval::any):ScheduleTask(1, updateEventTimer)
	end
	(Tick.Interval::any):ScheduleTask(1, updateEventTimer)
end

function ClientAdminPanelProcessor.tickEventTimer(activeEvent: ActiveEvent, dt: number)
	local now = workspace:GetServerTimeNow()
	local timeLeft = activeEvent.endTime - now
	ClientAdminPanelProcessor.updateEventTimer(timeLeft)
end

function ClientAdminPanelProcessor.stopEventTimer()
	ClientAdminPanelProcessor.eventTimerActive = false
	ClientAdminPanelProcessor.toggleStartEventButton(true)
	ClientAdminPanelProcessor.updateEventTimer(0)
	for _, card in eventCards do
		ClientAdminPanelProcessor.toggleHighlightActive(card, false)
	end
end

return ClientAdminPanelProcessor