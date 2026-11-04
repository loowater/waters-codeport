--!strict

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local Remotes = Source.AdminPanel.Remotes

local AdminPanelRegistry = require(Source.AdminPanel.Core.AdminPanelRegistry)

export type SavedPlayerAdminData = AdminPanelRegistry.SavedPlayerAdminData
export type PlayerAdminData = AdminPanelRegistry.PlayerAdminData
export type Command = AdminPanelRegistry.Command
export type Argument = AdminPanelRegistry.Argument

local AdminPanelProcessor = {}

function AdminPanelProcessor.convertType(value: any, typeName: string, playerId: number)
	: (any, string?)
	if typeName == "string" then
		return tostring(value)
	elseif typeName == "number" then
		local num = tonumber(value)
		return num, if num then nil else "Expected a number"

	elseif typeName == "Player" then
		if tostring(value) == 'me' then
			local player = Players:GetPlayerByUserId(playerId)
			return player, if player then nil else `Player not found: {value}`
		end
		local player = Players:FindFirstChild(tostring(value))
		return player, if player then nil else "Player not found: " .. value
	elseif typeName == "boolean" then
		local lower = string.lower(value)
		if lower == "true" or lower == "yes" or lower == "1" then
			return true
		elseif lower == "false" or lower == "no" or lower == "0" then
			return false
		end
		return nil, "Expected true/false"
	end

	return value
end

function AdminPanelProcessor.parseArguments(rawArgs: {string}, argumentsSchema: {Argument}, playerId: number)
	: {ok: boolean, err: string?, args: {any}?}
	local parsed: any = {}
	
	for i, argDef in argumentsSchema do
		local rawValue = rawArgs[i]
		
		if argDef.required and not rawValue then
			return {ok = false, err = string.format("Missing required argument: %s", argDef.name)}
		end
		
		if not rawValue then
			parsed[argDef.name] = nil
			continue
		end
		
		-- type conversion
		local value, err = AdminPanelProcessor.convertType(rawValue, argDef.typeOf, playerId)
		if err then
			return {ok = false, err = err}
		end
		
		parsed[argDef.name] = value
	end
	
	return {ok = true, args = parsed}
end

function AdminPanelProcessor.executeCommand(playerId: number, commandText: string)
	: {ok: boolean, err: string?}
	-- Parse command text
	local parts = string.split(commandText, ' ')
	local commandName = string.lower(parts[1])
	table.remove(parts, 1)
	
	-- Find command
	local command = AdminPanelRegistry.getCommand(commandName)
	if not command then
		return {ok = false, err = `Unknown command: {commandName}`}
	end
	
	-- Check permissions.
	if command.permission ~= nil and not AdminPanelProcessor.hasPermission(playerId, command.permission) then
		return {ok = false, err = `You don't have permission to use this command`}
	end
	
	-- Check cooldown
	if command.cooldown then
		local lastUsed = AdminPanelRegistry.getCommandCooldown(playerId, commandName)
		if lastUsed then
			local timeRemaining = command.cooldown - (os.clock() - lastUsed)
			if timeRemaining > 0 then
				return {ok = false, err = string.format("Command on cooldown. Wait %.1f seconds", timeRemaining)}
			end
		end
	end
	
	-- Parse arguments
	local parseResult = AdminPanelProcessor.parseArguments(parts, command.arguments, playerId)
	if not parseResult.ok or not parseResult.args then
		return {ok = false, err = `Invalid arguments: {parseResult.err}`}
	end
	
	local success, result = pcall(command.execute, playerId, parseResult.args)
	if not success then
		warn('Command error', result)
		return {ok = false, err = 'Command failed to execute'}
	end
	
	-- Set cooldown after successful execution
	if command.cooldown then
		AdminPanelRegistry.setCommandCooldown(playerId, commandName, os.clock())
	end
	
	return {ok = true}
end

function AdminPanelProcessor.executeCommandWithArgs(playerId: number, commandName: string, args: {[string]: any})
	: {ok: boolean, err: string?, result: any?}

	-- Find command
	local command = AdminPanelRegistry.getCommand(commandName)
	if not command then
		return {ok = false, err = `Unknown command: {commandName}`}
	end

	-- Check permissions
	if command.permission ~= nil and not AdminPanelProcessor.hasPermission(playerId, command.permission) then
		return {ok = false, err = `You don't have permission to use this command`}
	end
	
	-- Check cooldown
	if command.cooldown then
		local lastUsed = AdminPanelRegistry.getCommandCooldown(playerId, commandName)
		if lastUsed then
			local timeRemaining = command.cooldown - (os.clock() - lastUsed)
			if timeRemaining > 0 then
				return {ok = false, err = string.format("Command on cooldown. Wait %.1f seconds", timeRemaining)}
			end
		end
	end

	-- Validate and convert argument types
	local validatedArgs: any = {}

	for _, argDef in command.arguments do
		local rawValue = args[argDef.name]

		-- Check required arguments
		if argDef.required and rawValue == nil then
			return {ok = false, err = string.format("Missing required argument: %s", argDef.name)}
		end

		if rawValue == nil then
			validatedArgs[argDef.name] = nil
			continue
		end

		-- Type conversion/validation
		local value, err = AdminPanelProcessor.convertType(rawValue, argDef.typeOf, playerId)
		if err then
			return {ok = false, err = string.format("Invalid argument '%s': %s", argDef.name, err)}
		end

		validatedArgs[argDef.name] = value
	end

	-- Execute command
	local success, result = pcall(command.execute, playerId, validatedArgs)
	if not success then
		warn('Command error', result)
		return {ok = false, err = 'Command failed to execute'}
	elseif typeof(result) == 'table' and typeof(result.ok) == 'boolean' then
		if not result.ok then
			return {ok = false, err = result.err}
		end
	end
	
	-- Set cooldown after successful execution
	if command.cooldown then
		AdminPanelRegistry.setCommandCooldown(playerId, commandName, os.clock())
	end

	return {ok = true, result = result}
end

function AdminPanelProcessor.hasPermission(playerId: number, requiredRole: string)
	: boolean
	local playerAdminData = AdminPanelRegistry.getPlayerAdminData(playerId)
	if not playerAdminData then
		return false
	end
	
	local playerLevel = AdminPanelRegistry.roleHierarchy[playerAdminData.userRole]
	local requiredLevel = AdminPanelRegistry.roleHierarchy[requiredRole]
	
	if not playerLevel or not requiredLevel then
		return false
	end
	
	-- Higher or equal level = has permissions
	return playerLevel >= requiredLevel
end

function AdminPanelProcessor.resolveRoleHierarchy()
	for _, groupId in AdminPanelRegistry.getAdminGroups() do
		while true do
			local s, info = pcall(function()
				return GroupService:GetGroupInfoAsync(groupId)
			end)
			if not s then
				task.wait(.1)
				continue
			end
			if typeof(info.Roles) == 'table' then
				for _, roleInfo in info.Roles do
					local name = roleInfo.Name::string
					local rank = roleInfo.Rank::number
					if name and rank then
						AdminPanelRegistry.registerRole(name, rank)
					end
				end
			end
			break
		end
	end
end

function AdminPanelProcessor.resolvePlayerAdminData(
	playerId: number,
	playerAdminData: PlayerAdminData,
	savedPlayerAdminData: SavedPlayerAdminData
)
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	
	-- initialize user role for the first time.
	if playerAdminData.userRole == 'BLANK_ROLE' then
		for _, groupId in AdminPanelRegistry.getAdminGroups() do
			task.spawn(function()
				while playerAdminData.userRole == 'BLANK_ROLE' do
					local s, e = pcall(function()
						return player:IsInGroupAsync(groupId)
					end)
					if s then
						if e then
							if playerAdminData.userRole ~= 'BLANK_ROLE' then
								return
							end
							local role = player:GetRoleInGroupAsync(groupId)
							playerAdminData.userRole = role
						end
						break
					else
						task.wait(.1)
					end
				end

			end)
		end
	end
end

return AdminPanelProcessor
