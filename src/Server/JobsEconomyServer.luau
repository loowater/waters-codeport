local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local GameFolder = ReplicatedStorage.Game
local Events = GameFolder.Events
local MiscFolder = GameFolder.Misc
local Settings = GameFolder.Settings

local EconomyConfig = require(Settings.Economy)
local GameConfig = require(Settings.Game)

local GameWorkspace = workspace.Game
local GarbageBags = GameWorkspace.Garbage.Bags

local BankEvent = Events.Bank
local CheckUIEvent = Events.CheckUI
local StartJobEvent = Events.StartJob
local EndJobEvent = Events.EndJob
local TransferEvent = Events.Transfer
local SendNotification = ReplicatedStorage.SendNotification

local ToolsFolder = script.Tools
local ActionModules = script.Action_Modules
local ClothingFolder = script.Clothing

local PlayerDatastore = DataStoreService:GetDataStore("Player")

local REMOVABLE_GUIS = { "ATM", "JobUI", "CarSpawnerGui" }
local JOB_ITEMS = { "Mailbox", "Garbage", "FoodDelivery" }
local JOBS = { "Garbage", "Mail", "DeliverFood" }
local GARBAGE_RESPAWN_TIME = 60

local JobUniforms = {
	Garbage = "Garbageman",
	Mail = "Mailman",
}

local JobTargetFolders = {
	Mail = "Mail",
	DeliverFood = "DeliverFood",
}

local DeliveryPrompts = {
	DeliverMail = { Job = "Mail", RequiresJob = false },
	DeliverFood = { Job = "DeliverFood", RequiresJob = true },
}

local JobTools = {
	Mailbox = "Mail",
	FoodDelivery = "DeliverFood",
}

local jobTargets = {}
local originalClothing = {}

local function weld(part0: BasePart, part1: BasePart)
	local joint = Instance.new("Weld")
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = CFrame.new()
	joint.C1 = part1.CFrame:ToObjectSpace(part0.CFrame)
	joint.Parent = part0
end

local function createValue(className: string, name: string, value: any, parent: Instance): Instance
	local object = Instance.new(className)
	object.Name = name
	object.Value = value
	object.Parent = parent
	return object
end

local function setupPrompts()
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("ProximityPrompt") and instance.Name == "BuyItem" then
			local price = instance:GetAttribute("Price")
			local actionText = "Buy (" .. price .. " " .. EconomyConfig.Currency .. ") "

			if instance:GetAttribute("GamepassRequired") ~= 0 then
				actionText ..= "[GAMEPASS]"
			end

			instance.ObjectText = instance:GetAttribute("Name")
			instance.ActionText = actionText
		end
	end
end

local function attachModel(character: Model, template: Model, limb: BasePart)
	template.PrimaryPart = template:FindFirstChild("Middle")

	local model = template:Clone()
	model.Name = template.Name
	model:SetPrimaryPartCFrame(limb.CFrame)
	model.PrimaryPart:Destroy()

	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			weld(limb, child)
			child.CanCollide = false
			child.Anchored = false
		end
	end

	model.Parent = character
end

local function removeModel(character: Model, name: string)
	for _, child in character:GetChildren() do
		if child.Name == name then
			child:Destroy()
		end
	end
end

local function giveUniform(character: Model, name: string)
	for _, clothingName in { "Shirt", "Pants" } do
		local existing = character:FindFirstChild(clothingName)
		if existing then
			existing:Destroy()
		end
	end

	for _, item in ClothingFolder[name]:GetChildren() do
		item:Clone().Parent = character
	end
end

local function equipJobGear(character: Model, job: string)
	if job == "DeliverFood" then
		attachModel(character, MiscFolder.FoodBackpack, character:FindFirstChild("Torso"))
	elseif JobUniforms[job] then
		giveUniform(character, JobUniforms[job])
	end
end

local function clearJobItems(container: Instance)
	for _, item in container:GetChildren() do
		if table.find(JOB_ITEMS, item.Name) then
			item:Destroy()
		end
	end
end

local function startJob(player: Player, job: string)
	local targetFolder = JobTargetFolders[job]
	if targetFolder then
		jobTargets[player][job] = math.random(1, #GameWorkspace[targetFolder]:GetChildren())
	end

	equipJobGear(player.Character, job)
end

local function endJob(player: Player)
	local status = player:FindFirstChild("CurrentJob")

	clearJobItems(player.Backpack)
	clearJobItems(player.Character)
	removeModel(player.Character, "FoodBackpack")

	EndJobEvent:FireClient(player)
	jobTargets[player] = {}
	status.Value = "None"

	local shirt = player.Character:FindFirstChildOfClass("Shirt")
	local pants = player.Character:FindFirstChildOfClass("Pants")
	shirt.ShirtTemplate = originalClothing[player.Name].ShirtID
	pants.PantsTemplate = originalClothing[player.Name].PantsID
end

local function getPromptPosition(prompt: ProximityPrompt): Vector3
	local parent = prompt.Parent
	if parent:IsA("Attachment") then
		return parent.WorldCFrame.Position
	end
	return parent.Position
end

local function grantTool(player: Player, template: Tool, job: string, onlyOne: boolean?)
	if not onlyOne then
		template:Clone().Parent = player.Backpack
		return
	end

	if player.Backpack:FindFirstChild(template.Name) or player.Character:FindFirstChild(template.Name) then
		return
	end

	local tool = template:Clone()
	tool.Parent = player.Backpack
	tool.Number.Value = jobTargets[player][job]
end

local function handleDelivery(prompt: ProximityPrompt, player: Player, delivery)
	if delivery.RequiresJob and player:FindFirstChild("CurrentJob").Value ~= delivery.Job then
		return
	end

	local targets = jobTargets[player]
	if prompt.Parent.Name ~= tostring(targets[delivery.Job]) then
		return
	end

	local actionModule = require(ActionModules:FindFirstChild(prompt.Name))
	if actionModule.Execute(prompt, player) then
		local targetFolder = GameWorkspace[JobTargetFolders[delivery.Job]]
		targets[delivery.Job] = math.random(1, #targetFolder:GetChildren())
	end
end

local function handleGetTool(prompt: ProximityPrompt, player: Player)
	local toolName = prompt.Parent.Name
	local job = JobTools[toolName]
	local template = ToolsFolder:FindFirstChild(toolName)

	if not template or player:FindFirstChild("CurrentJob").Value ~= job then
		return
	end

	grantTool(player, template, job, prompt:GetAttribute("OnlyOne"))
end

local function startPaychecks(player: Player, wallet: IntValue, bank: IntValue)
	for teamName, paycheck in EconomyConfig.PaycheckList do
		if player.Team.Name ~= teamName then
			continue
		end

		local amount, minutes, toWallet = table.unpack(paycheck)

		task.spawn(function()
			while player.Team.Name == teamName do
				task.wait(minutes * 60)

				if toWallet == false then
					bank.Value += amount
				else
					wallet.Value += amount
				end
			end
		end)
	end
end

local function startHunger(humanoid: Humanoid, hunger: IntValue)
	local drain, interval = table.unpack(GameConfig.HungerRate)

	task.spawn(function()
		while humanoid.Health > 0 do
			task.wait(interval)

			if hunger.Value <= 0 then
				humanoid.Health -= 10
				task.wait(interval * 2)
			else
				hunger.Value -= drain
			end
		end
	end)
end

local function onCharacterLoaded(player: Player, character: Model, jobStatus: StringValue, wallet: IntValue, bank: IntValue)
	local hunger = character:WaitForChild("Stats"):WaitForChild("Hunger")
	local humanoid = character:WaitForChild("Humanoid")

	local shirt = character:FindFirstChildOfClass("Shirt")
	local pants = character:FindFirstChildOfClass("Pants")
	local defaults = ClothingFolder.Default

	originalClothing[player.Name] = {
		ShirtID = shirt.ShirtTemplate or defaults.Shirt.ShirtTemplate,
		PantsID = pants.PantsTemplate or defaults.Pants.PantsTemplate,
	}

	equipJobGear(character, jobStatus.Value)

	if EconomyConfig.EnablePaycheks then
		startPaychecks(player, wallet, bank)
	end

	if GameConfig.EnableHunger then
		startHunger(humanoid, hunger)
	end
end

local function onPlayerAdded(player: Player)
	local savedData = PlayerDatastore:GetAsync(player.UserId)
	local walletAmount, bankAmount = table.unpack(savedData or EconomyConfig.StartingMoney)

	local jobStatus = createValue("StringValue", "CurrentJob", "None", player)

	local dataFolder = Instance.new("Folder")
	dataFolder.Name = "PlayerData"
	local wallet = createValue("IntValue", "Wallet", walletAmount, dataFolder)
	local bank = createValue("IntValue", "Bank", bankAmount, dataFolder)
	dataFolder.Parent = player

	jobTargets[player] = {}

	player.CharacterAppearanceLoaded:Connect(function(character)
		onCharacterLoaded(player, character, jobStatus, wallet, bank)
	end)
end

local function onPlayerRemoving(player: Player)
	local data = player:FindFirstChild("PlayerData")
	PlayerDatastore:SetAsync(player.UserId, { data.Wallet.Value, data.Bank.Value })
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	local distance = (getPromptPosition(prompt) - rootPart.Position).Magnitude

	if distance > prompt.MaxActivationDistance then
		return
	end

	local delivery = DeliveryPrompts[prompt.Name]

	if delivery then
		handleDelivery(prompt, player, delivery)
	elseif prompt.Name == "GetTool" then
		handleGetTool(prompt, player)
	else
		local actionModule = ActionModules:FindFirstChild(prompt.Name)
		if actionModule then
			require(actionModule).Execute(prompt, player)
		end
	end
end

local function onBankRequest(player: Player, deposit: boolean, amount: number)
	local data = player:FindFirstChild("PlayerData")
	local source, destination = data.Bank, data.Wallet

	if deposit then
		source, destination = data.Wallet, data.Bank
	end

	if source.Value >= amount then
		source.Value -= amount
		destination.Value += amount
	end
end

local function onTransferRequest(player: Player, targetName: string, amount: number)
	if not amount or amount <= 0 then
		return
	end

	if player.Name == targetName then
		return
	end

	local target = Players:FindFirstChild(targetName)
	if not target then
		return
	end

	local senderBank = player:FindFirstChild("PlayerData").Bank
	local targetBank = target:FindFirstChild("PlayerData").Bank

	if senderBank.Value < amount then
		return
	end

	senderBank.Value -= amount
	targetBank.Value += amount

	SendNotification:FireClient(player, `Success transfer to {target.Name}`)
	SendNotification:FireClient(target, `You got {amount} by {player.Name}`)
end

local function onCheckUI(player: Player, name: string)
	if not table.find(REMOVABLE_GUIS, name) then
		return
	end

	local gui = player.PlayerGui:FindFirstChild(name)
	if gui then
		gui:Destroy()
	end
end

local function onStartJob(player: Player, job: string)
	local currentJob = player:FindFirstChild("CurrentJob")

	if currentJob.Value ~= "None" or not table.find(JOBS, job) then
		return
	end

	currentJob.Value = job
	startJob(player, job)
end

local function watchGarbageBag(bag: BasePart)
	bag.Changed:Connect(function(property)
		if property ~= "Transparency" then
			return
		end

		task.delay(GARBAGE_RESPAWN_TIME, function()
			bag.Transparency = 0
			bag:FindFirstChildOfClass("ProximityPrompt").Enabled = true
			bag.CanCollide = false
		end)
	end)
end

setupPrompts()

for _, bag in GarbageBags:GetChildren() do
	watchGarbageBag(bag)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

BankEvent.OnServerEvent:Connect(onBankRequest)
TransferEvent.OnServerEvent:Connect(onTransferRequest)
CheckUIEvent.OnServerEvent:Connect(onCheckUI)
StartJobEvent.OnServerEvent:Connect(onStartJob)
EndJobEvent.OnServerEvent:Connect(endJob)
