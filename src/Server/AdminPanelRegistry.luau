--!strict

export type Argument = {name: string, typeOf: string, required: boolean?}
export type Command = {
	name: string,
	aliases: {string},
	description: string,
	cooldown: number,
	permission: string?,
	arguments: {Argument},
	execute: (playerId: number, args: {any}) -> {ok: boolean, err: string?}
}
export type SavedPlayerAdminData = {
	userRole: string,
}
export type PlayerAdminData = {
	userRole: string,
}

local AdminPanelRegistry = {}

AdminPanelRegistry.ADMIN_GROUPS = {}::{number}
AdminPanelRegistry.commands = {}::{[string]: Command}
AdminPanelRegistry.commandsByAlias = {}::{[string]: Command}
AdminPanelRegistry.roleHierarchy = {}::{[string]: number}
AdminPanelRegistry.savedPlayerAdminData = {}::{[number]: SavedPlayerAdminData}
AdminPanelRegistry.playerAdminData = {}::{[number]: PlayerAdminData}
AdminPanelRegistry.commandCooldowns = {}::{[number]: {[string]: number}}

function AdminPanelRegistry.registerAdminGroup(groupId: number)
	if table.find(AdminPanelRegistry.ADMIN_GROUPS, groupId) then
		return
	end
	table.insert(AdminPanelRegistry.ADMIN_GROUPS, groupId)
end

function AdminPanelRegistry.getAdminGroups()
	return AdminPanelRegistry.ADMIN_GROUPS
end

function AdminPanelRegistry.registerRole(roleName: string, hierarchyLevel: number)
	if AdminPanelRegistry.roleHierarchy[roleName] then
		return
	end
	AdminPanelRegistry.roleHierarchy[roleName] = hierarchyLevel
end

function AdminPanelRegistry.getCommandCooldown(playerId: number, commandName: string): number?
	if AdminPanelRegistry.commandCooldowns[playerId] then
		return AdminPanelRegistry.commandCooldowns[playerId][string.lower(commandName)]
	end
	return nil
end

function AdminPanelRegistry.setCommandCooldown(playerId: number, commandName: string, timestamp: number)
	if not AdminPanelRegistry.commandCooldowns[playerId] then
		AdminPanelRegistry.commandCooldowns[playerId] = {}
	end
	AdminPanelRegistry.commandCooldowns[playerId][string.lower(commandName)] = timestamp
end

function AdminPanelRegistry.registerCommand(command: Command)
	local key = string.lower(command.name)
	if AdminPanelRegistry.commands[key] then
		return AdminPanelRegistry.commands[key]
	end
	AdminPanelRegistry.commands[key] = command
	for _, alias in command.aliases do
		AdminPanelRegistry.commandsByAlias[string.lower(alias)] = command
	end
	return command
end

function AdminPanelRegistry.getCommand(name: string)
	: Command?
	local key = string.lower(name)
	return AdminPanelRegistry.commands[key] or AdminPanelRegistry.commandsByAlias[key]
end

function AdminPanelRegistry.onPlayerAdded(playerId: number)
	if AdminPanelRegistry.playerAdminData[playerId] then
		return AdminPanelRegistry.playerAdminData[playerId]
	end
	local savedPlayerAdminData = {
		userRole = 'BLANK_ROLE',
	}
	AdminPanelRegistry.savedPlayerAdminData[playerId] = savedPlayerAdminData
	AdminPanelRegistry.playerAdminData[playerId] = savedPlayerAdminData
	return AdminPanelRegistry.playerAdminData[playerId]
end

function AdminPanelRegistry.onPlayerRemoving(playerId: number)
	AdminPanelRegistry.playerAdminData[playerId] = nil
	AdminPanelRegistry.savedPlayerAdminData[playerId] = nil
end

function AdminPanelRegistry.getPlayerAdminData(playerId: number)
	: PlayerAdminData?
	return AdminPanelRegistry.playerAdminData[playerId]
end

return AdminPanelRegistry