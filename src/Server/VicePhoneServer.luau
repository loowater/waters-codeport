local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MessagesManager = require(script.MessagesManager)

local SendMessageRemote = ReplicatedStorage.RSendMessage
local ReportUserRemote = ReplicatedStorage.ReportUser
local BackpackAllToolsRemote = ReplicatedStorage.BackpackAllTools
local ShowPhoneRemote = ReplicatedStorage.ShowPhone
local ChangePhoneDisplayRemote = ReplicatedStorage.ChangePhoneDisplay
local PhoneTemplate = ReplicatedStorage.PhoneModel

local MESSAGE_COOLDOWN = 1
local WELCOME_MESSAGE = "Welcome, to VicePhone."

local function createDebounce(player: Player)
	local debounce = Instance.new("BoolValue")
	debounce.Name = "MessagesDebounce"
	debounce.Value = false
	debounce.Parent = player

	debounce:GetPropertyChangedSignal("Value"):Connect(function()
		if debounce.Value then
			task.wait(MESSAGE_COOLDOWN)
			debounce.Value = false
		end
	end)
end

local function attachPhone(character: Model)
	local arm = character["Right Arm"]
	local phone = PhoneTemplate:Clone()
	phone.Parent = arm

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arm
	weld.Part1 = phone
	weld.Parent = phone

	phone.CFrame = arm.CFrame

	character.Humanoid.Died:Connect(function()
		phone:Destroy()
	end)
end

local function broadcast(remote: RemoteEvent)
	remote.OnServerEvent:Connect(function(player, statement)
		remote:FireAllClients(player, statement)
	end)
end

local function onPlayerAdded(player: Player)
	createDebounce(player)
	player.CharacterAdded:Connect(attachPhone)
	MessagesManager.SendMessageToPlayerAsSystem(player, WELCOME_MESSAGE)
end

local function onSendMessage(player: Player, recipient, message)
	local debounce = player.MessagesDebounce

	if debounce.Value then
		return "debounce"
	end

	debounce.Value = true

	return MessagesManager.SendMessage(player, recipient, message, true)
end

local function onReportUser(_player: Player, user: Player, messages)
	warn(`{user.Name} reported`)

	for _, message in messages do
		print(message)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

SendMessageRemote.OnServerInvoke = onSendMessage
ReportUserRemote.OnServerEvent:Connect(onReportUser)

BackpackAllToolsRemote.OnServerEvent:Connect(function(player)
	player.Character.Humanoid:UnequipTools()
end)

broadcast(ShowPhoneRemote)
broadcast(ChangePhoneDisplayRemote)
