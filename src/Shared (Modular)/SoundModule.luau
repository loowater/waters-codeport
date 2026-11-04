-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Variables
local SFX = ReplicatedStorage.SFX
-- Module
local Sounds = {
	-- UNITS
	["Unit 1"] = SFX["unit sound1"],
	["Unit 2"] = SFX["unit sound2"],
	["Unit 3"] = SFX["unit sound3"],
	["Unit 7"] = SFX["unit sound4"],
	["Unit 8"] = SFX["unit sound5"],
	["Unit 9"] = SFX["unit sound6"],
	
	-- REASONS
	["Medical Emergency"] = SFX["reason sound"],
	["Robbery"] = SFX["reason sound1"],
	["Trouble Breathing"] = SFX["reason sound2"],
	["Chest Pain"] = SFX["reason sound3"],
	["Structure Fire"] = SFX["reason sound4"],
	["Residential Fire"] = SFX["reason sound5"],
	["Unstable Patient"] = SFX["reason sound6"],
	["PANIC Alarm"] = SFX["reason sound7"],
	
	-- CHANNELS
	["Channel 1"] = SFX["channel sound1"],
	["FireTAC 1"] = SFX["channel sound2"],
	["Firegrounds"] = SFX["channel sound3"],
	
	-- LOCATIONS
	["230 Robloxian Way"] = SFX["location sound1"],
}
return Sounds