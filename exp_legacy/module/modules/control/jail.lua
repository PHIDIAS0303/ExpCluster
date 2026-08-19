--[[-- Control Module - Jail
    - Adds a way to jail players.
    @control Jail
    @alias Jail

    @usage
    -- import the module from the control modules
    local Jail = require("modules.exp_legacy.modules.control.jail") --- @dep modules.control.jail

    -- This will give 'MrBiter' the jail role, which suppresses all of their other roles
    -- the player name and reason are only so they can be included in the event for user feedback
    Jail.jail_player('MrBiter', 'Cooldude2606', 'Likes biters too much')

    -- This will remove the jail role from 'MrBiter', restoring their other roles
    -- again as above the player name is only used in the event for user feedback
    Jail.unjail_player('MrBiter', 'Cooldude2606')
]]

local Roles = require("modules/exp_roles")

local valid_player = function(p) return type(p) == "userdata" and p or game.get_player(p) end

--- The role given to jailed players, it has a higher priority than every other role
local function jail_role()
    return assert(Roles.get_role_by_name("Jail"), "The Jail role does not exist")
end

local Jail = {
    events = {
        --- When a player is assigned to jail
        -- @event on_player_jailed
        -- @tparam number player_index the index of the player who was jailed
        -- @tparam string by_player_name the name of the player who jailed the other player
        -- @tparam string reason the reason that the player was jailed
        on_player_jailed = script.generate_event_name(),
        --- When a player is unassigned from jail
        -- @event on_player_unjailed
        -- @tparam number player_index the index of the player who was unjailed
        -- @tparam string by_player_name the name of the player who unjailed the other player
        on_player_unjailed = script.generate_event_name(),
    },
}

--- Used to emit the jail related events
-- @tparam number event the name of the event that will be emited
-- @tparam LuaPlayer player the player who is being acted on
-- @tparam string by_player_name the player who is doing the action
-- @tparam string reason the reason for the action (jail)
local function event_emit(event, player, by_player_name, reason)
    script.raise_event(event, {
        name = event,
        tick = game.tick,
        player_index = player.index,
        by_player_name = by_player_name,
        reason = reason,
    })
end

--- Jail.
-- Functions related to jail
-- @section jail-functions

--- Checks if the player is currently in jail
-- @tparam LuaPlayer player the player to check if they are in jail
-- @treturn boolean whether the player is currently in jail
function Jail.is_jailed(player)
    local valid = valid_player(player)
    return valid ~= nil and jail_role():has_player(valid)
end

--- Moves a player to jail, which suppresses all of their other roles
-- @tparam LuaPlayer player the player who will be jailed
-- @tparam string by_player_name the name of the player who is doing the jailing
-- @tparam[opt='Non given.'] string reason the reason that the player is being jailed
-- @treturn boolean wheather the user was jailed successfully
function Jail.jail_player(player, by_player_name, reason)
    player = valid_player(player)
    if not player then return end
    if not by_player_name then return end

    reason = reason or "Non given."

    local role = jail_role()
    if role:has_player(player) then return end

    player.walking_state = { walking = false, direction = player.walking_state.direction }
    player.riding_state = { acceleration = defines.riding.acceleration.nothing, direction = player.riding_state.direction }
    player.mining_state = { mining = false }
    player.shooting_state = { state = defines.shooting.not_shooting, position = player.shooting_state.position }
    player.picking_state = false
    player.repair_state = { repairing = false, position = player.repair_state.position }

    role:assign(player, { by_player_name = by_player_name, silent = true })

    event_emit(Jail.events.on_player_jailed, player, by_player_name, reason)

    return true
end

--- Moves a player out of jail, which restores all of their other roles
-- @tparam LuaPlayer player the player that will be unjailed
-- @tparam string by_player_name the name of the player that is doing the unjail
-- @treturn boolean whether the player was unjailed successfully
function Jail.unjail_player(player, by_player_name)
    player = valid_player(player)
    if not player then return end
    if not by_player_name then return end

    local role = jail_role()
    if not role:has_player(player) then return end

    role:unassign(player, { by_player_name = by_player_name, silent = true })

    event_emit(Jail.events.on_player_unjailed, player, by_player_name)

    return true
end

return Jail
