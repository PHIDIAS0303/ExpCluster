--[[-- Command Types - Roles
The data types that are used with exp_roles
A lower role index indicates it is more privileged

Adds parsers for:
    role
    lower_role
    lower_role_player
    lower_role_player_online
    lower_role_player_alive
]]

local ExpUtil = require("modules/exp_util")
local auto_complete = ExpUtil.auto_complete

local Commands = require("modules/exp_commands")
local add, parse = Commands.add_data_type, Commands.parse_input
local valid, invalid = Commands.status.success, Commands.status.invalid_input

local Roles = require("modules/exp_roles")
local player_outranks = Roles.player_outranks
local player_has_permission = Roles.player_has_permission

local types = {} --- @class (partial) Commands.types

--- A role known to exp roles, matched on its name
types.role =
    add("role", function(input)
        local names = {}
        for index, role in ipairs(Roles.get_roles()) do
            names[index] = role.name
        end

        local name = auto_complete(names, input)
        if name == nil then
            return invalid{ "exp-commands-parse.string-options", table.concat(names, ", ") }
        else
            return valid(Roles.get_role_by_name(name))
        end
    end)

--- A role which is lower than the players highest role
types.lower_role =
    add("lower_role", function(input, player)
        local success, status, result = parse(input, player, types.role)
        if not success then return status, result end
        --- @cast result ExpRoles.Role

        if not player_has_permission(player, "core.admin") and not Roles.get_player_highest_role(player):is_higher_than(result) then
            return invalid{ "exp-commands-parse_role.lower-role" }
        else
            return valid(result)
        end
    end)

--- A player who is of a lower role than the executing player
types.lower_role_player =
    add("lower_role_player", function(input, player)
        local success, status, result = parse(input, player, Commands.types.player)
        if not success then return status, result end
        --- @cast result LuaPlayer

        if not player_outranks(player, result) then
            return invalid{ "exp-commands-parse_role.lower-role-player" }
        else
            return valid(result)
        end
    end)

--- A player who is of a lower role than the executing player
types.lower_role_player_online =
    add("lower_role_player_online", function(input, player)
        local success, status, result = parse(input, player, Commands.types.player_online)
        if not success then return status, result end
        --- @cast result LuaPlayer

        if not player_outranks(player, result) then
            return invalid{ "exp-commands-parse_role.lower-role-player" }
        else
            return valid(result)
        end
    end)

--- A player who is of a lower role than the executing player
types.lower_role_player_alive =
    add("lower_role_player_alive", function(input, player)
        local success, status, result = parse(input, player, Commands.types.player_alive)
        if not success then return status, result end
        --- @cast result LuaPlayer

        if not player_outranks(player, result) then
            return invalid{ "exp-commands-parse_role.lower-role-player" }
        else
            return valid(result)
        end
    end)

return types
