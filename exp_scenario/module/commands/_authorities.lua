--[[-- Command Authorities - Roles
Adds a permission authority which checks the clusterio permission for a command
]]

local Commands = require("modules/exp_commands")
local add, allow, deny = Commands.add_permission_authority, Commands.status.success, Commands.status.unauthorised

local Roles = require("modules/exp_roles")
local player_has_permission = Roles.player_has_permission

local authorities = {}

--- Every command requires the permission `exp_scenario.command.<name>`, with
--- hyphens replaced by underscores, see permissions.ts for their definitions
authorities.exp_permission =
    add(function(player, command)
        local permission = "exp_scenario.command." .. command.name:gsub("%-", "_")
        if not player_has_permission(player, permission) then
            return deny{ "exp-commands-authorities_role.deny" }
        else
            return allow()
        end
    end)

Roles.define_permission_trigger("exp_scenario.player.system_commands", function(player, state)
    if state then
        Commands.unlock_system_commands(player.name)
    else
        Commands.lock_system_commands(player.name)
    end
end)

return authorities
