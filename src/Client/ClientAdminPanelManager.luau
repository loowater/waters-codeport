--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source

local ClientAdminPanelProcessor = require(script.Parent.ClientAdminPanelProcessor)
local ClientEventRegistry = require(Source.Event.Visual.ClientEventRegistry)

local ClientAdminPanelManager = {}

function ClientAdminPanelManager.init()
	
	ClientAdminPanelProcessor.init()
	ClientAdminPanelManager.setupEventDrivers()
	
end

function ClientAdminPanelManager.setupEventDrivers()
	local activeEvent = ClientEventRegistry.getActiveEvent()
	if activeEvent then
		ClientAdminPanelProcessor.startEventTimer(activeEvent)
	end
	ClientEventRegistry.onEventStarted:Connect(function(activeEvent)
		ClientAdminPanelProcessor.startEventTimer(activeEvent)
	end)
	ClientEventRegistry.onEventStopped:Connect(function(activeEvent: any)
		assert(activeEvent)
		ClientAdminPanelProcessor.stopEventTimer(activeEvent)
	end)
end

return ClientAdminPanelManager
