--[[-- ExpRoles
Mirrors clusterio's roles and permissions into the game.

Roles, the permissions they grant, and the players who hold them are owned by
the controller. This module keeps a copy of that state and answers permission
checks from it, so a check such as `Roles.player_has_permission(player,
"exp_scenario.command.kill")` is answered from the same data the web ui shows.

Roles are objects, looked up by their clusterio id, and everything done to or
with a role is a method on it. Assignments made in game are applied locally
first and then sent to the controller, which avoids callers having to deal with
the round trip.

Only the roles with the highest priority a player holds apply. Jail sits above
every other role, so holding it suppresses the rest, including the default role
every player has.
]]

local clusterio_api = require("modules/clusterio/api")
local compat = require("modules/clusterio/compat") --[[@as LibCompat]]
local Async = require("modules/exp_util/async")
local Storage = require("modules/exp_util/storage")

--- @class ExpRoles
local ExpRoles = {
    events = {
        --- Raised when the roles a player holds change, or when a role they
        --- hold is changed on the controller. In the second case `assigned` and
        --- `unassigned` are both empty.
        --- @type EventData.ExpRoles.on_player_roles_changed
        on_player_roles_changed = script.generate_event_name(),
    },
}

--- @class EventData.ExpRoles.on_player_roles_changed : EventData
--- @field player_index uint
--- @field by_player_index uint 0 when the change did not come from a player
--- @field assigned number[] Ids of the roles which were assigned
--- @field unassigned number[] Ids of the roles which were unassigned

--- Methods shared by every role, kept apart from the fields so that defining
--- them does not count as injecting fields into the role itself
--- @class ExpRoles.RolePrototype
local Role = {}
ExpRoles._prototype = Role

--- Registered so roles keep their methods across save and load
local role_metatable = Storage.register_metatable("Role", { __index = Role })

--- @class ExpRoles.Role : ExpRoles.RolePrototype
--- @field id number Clusterio role id
--- @field name string
--- @field short_hand string
--- @field order number Position given by the controller, compare roles with the methods rather than this
--- @field priority number Only the highest priority roles a player holds apply
--- @field tag string
--- @field color Color?
--- @field permissions table<string, true> Permission names granted by this role
--- @field block_auto_assign boolean

--- @class ExpRoles.AssignOptions
--- @field by_player_name string? Shown in the game message, defaults to the current player or the server
--- @field silent boolean? When true no game message is printed
--- @field local_only boolean? When true the controller is not told, for roles earned on this map only

--- @class ExpRoles.ScriptData
--- @field roles table<number, ExpRoles.Role> Roles indexed by clusterio id
--- @field synced_players table<string, number[]> Role ids from the controller
--- @field local_players table<string, number[]> Role ids which only exist on this map
--- @field pending table<string, number[]> Local role ids waiting to be confirmed
--- @field default_role_id number? Role every player holds
--- @field emit_updates boolean
local script_data = {}

--- Async handlers run when the state of a permission may have changed
local permission_triggers = {} --- @type table<string, Async.AsyncFunction>

--[[
    Role state
]]

--- Build a role from the record sent by the controller
--- @param record table
--- @param names string[]? When given, record.permissions holds indexes into it
--- @return ExpRoles.Role
local function decode_role(record, names)
    local meta = record.meta
    local permissions = {}
    if names then
        -- Indexes are zero based, having come from javascript
        for _, index in pairs(record.permissions) do
            permissions[names[index + 1]] = true
        end
    else
        for _, permission in pairs(record.permissions) do
            permissions[permission] = true
        end
    end

    --- @type ExpRoles.Role
    return setmetatable({
        id = record.id,
        name = record.name,
        short_hand = meta.short_hand or record.name,
        order = meta.order or record.id,
        priority = meta.priority or 0,
        tag = meta.tag or "",
        color = meta.color,
        permissions = permissions,
        block_auto_assign = meta.block_auto_assign or false,
    }, role_metatable)
end

--- Sort roles in place, the most privileged first
--- @param roles ExpRoles.Role[]
--- @return ExpRoles.Role[]
local function sort_roles(roles)
    table.sort(roles, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    return roles
end

--- The server is represented by nil, or by a player object with index 0
--- @param player LuaPlayer?
--- @return LuaPlayer? # The player when it is not the server
local function not_server(player)
    if player == nil or player.index == 0 then return nil end
    return player
end

--- Role ids a player has been given, without the default role or priority applied
--- @param player_name string
--- @return number[]
local function get_held_role_ids(player_name)
    local role_ids, seen = {}, {}
    for _, list in pairs{ script_data.synced_players[player_name], script_data.local_players[player_name] } do
        for _, role_id in pairs(list) do
            if not seen[role_id] then
                seen[role_id] = true
                role_ids[#role_ids + 1] = role_id
            end
        end
    end
    return role_ids
end

--- Role ids a player has been given, as a set
--- @param player_name string
--- @return table<number, true>
local function get_held_role_set(player_name)
    local rtn = {}
    for _, role_id in pairs(get_held_role_ids(player_name)) do
        rtn[role_id] = true
    end
    return rtn
end

--- Roles which apply to a player, with the default role and priority applied
--- @param player_name string
--- @return ExpRoles.Role[]
local function get_effective_roles(player_name)
    local role_ids = get_held_role_ids(player_name)
    if script_data.default_role_id then
        role_ids[#role_ids + 1] = script_data.default_role_id
    end

    local roles, highest_priority = {}, nil
    for _, role_id in pairs(role_ids) do
        local role = script_data.roles[role_id]
        if role then
            roles[#roles + 1] = role
            if highest_priority == nil or role.priority > highest_priority then
                highest_priority = role.priority
            end
        end
    end

    local rtn = {}
    for _, role in pairs(roles) do
        if role.priority == highest_priority then
            rtn[#rtn + 1] = role
        end
    end
    return sort_roles(rtn)
end

--[[
    Role lookup
]]

--- Get a role from its clusterio id
--- @param role_id number
--- @return ExpRoles.Role?
function ExpRoles.get_role(role_id)
    return script_data.roles[role_id]
end

--- Get a role from its name, roles should be referred to by id where possible
--- @param name string
--- @return ExpRoles.Role?
function ExpRoles.get_role_by_name(name)
    for _, role in pairs(script_data.roles) do
        if role.name == name then return role end
    end
    return nil
end

--- Get every role, the most privileged first
--- @return ExpRoles.Role[]
function ExpRoles.get_roles()
    local rtn = {}
    for _, role in pairs(script_data.roles) do
        rtn[#rtn + 1] = role
    end
    return sort_roles(rtn)
end

--- Get the role every player holds
--- @return ExpRoles.Role?
function ExpRoles.get_default_role()
    return script_data.default_role_id and script_data.roles[script_data.default_role_id] or nil
end

--- Get a role and every role more privileged than it, the default role excluded
--- @param role ExpRoles.Role
--- @return ExpRoles.Role[]
function ExpRoles.get_higher_roles(role)
    local rtn = {}
    for _, other in pairs(script_data.roles) do
        if not other:is_lower_than(role) and other.id ~= script_data.default_role_id then
            rtn[#rtn + 1] = other
        end
    end
    return sort_roles(rtn)
end

--- Get a role and every role less privileged than it, the default role excluded
--- @param role ExpRoles.Role
--- @return ExpRoles.Role[]
function ExpRoles.get_lower_roles(role)
    local rtn = {}
    for _, other in pairs(script_data.roles) do
        if not other:is_higher_than(role) and other.id ~= script_data.default_role_id then
            rtn[#rtn + 1] = other
        end
    end
    return sort_roles(rtn)
end

--- Role used when there is no player, such as for commands run by the server
--- It has core.admin so it passes every permission check
local server_role = setmetatable({
    id = -1,
    name = "<server>",
    short_hand = "SRV",
    order = -math.huge,
    priority = 0,
    tag = "",
    color = nil,
    permissions = { ["core.admin"] = true },
    block_auto_assign = true,
}, role_metatable)

--- Get the roles which apply to a player, including the default role
--- Only the roles with the highest priority are returned, which lets a role
--- such as Jail suppress every other role a player holds
--- @param player LuaPlayer? nil for the server
--- @return ExpRoles.Role[]
function ExpRoles.get_player_roles(player)
    -- The server is not a player and is allowed to do anything
    local valid = not_server(player)
    if not valid then return { server_role } end
    return get_effective_roles(valid.name)
end

--- Get the most privileged role which applies to a player
--- @param player LuaPlayer? nil for the server
--- @return ExpRoles.Role
function ExpRoles.get_player_highest_role(player)
    local role = ExpRoles.get_player_roles(player)[1]
    return (assert(role, "Player has no roles, is the default role set and exp_roles syncing?"))
end

--[[
    Permission checks
]]

--- Check if a player has a permission through any of their roles
--- @param player LuaPlayer? nil for the server
--- @param permission string A clusterio permission such as `exp_scenario.command.kill`
--- @return boolean
function ExpRoles.player_has_permission(player, permission)
    for _, role in pairs(ExpRoles.get_player_roles(player)) do
        local permissions = role.permissions
        if permissions["core.admin"] or permissions[permission] then
            return true
        end
    end

    return false
end

--- Check if a player is more privileged than another player
--- A player with core.admin, which includes the server, outranks every player
--- @param player LuaPlayer? nil for the server
--- @param other LuaPlayer? nil for the server
--- @return boolean
function ExpRoles.player_outranks(player, other)
    if ExpRoles.player_has_permission(player, "core.admin") then return true end
    local highest = ExpRoles.get_player_roles(player)[1]
    local other_highest = ExpRoles.get_player_roles(other)[1]
    if highest == nil then return false end
    return other_highest == nil or highest:is_higher_than(other_highest)
end

--[[
    Role methods
]]

--- Check if this role grants a permission
--- @param self ExpRoles.Role
--- @param permission string
--- @return boolean
function Role.has_permission(self, permission)
    local permissions = self.permissions
    return permissions["core.admin"] or permissions[permission] or false
end

--- Check if this role is more privileged than another
--- @param self ExpRoles.Role
--- @param other ExpRoles.Role
--- @return boolean
function Role.is_higher_than(self, other)
    if self.order == other.order then return self.id < other.id end
    return self.order < other.order
end

--- Check if this role is less privileged than another
--- @param self ExpRoles.Role
--- @param other ExpRoles.Role
--- @return boolean
function Role.is_lower_than(self, other)
    return other:is_higher_than(self)
end

--- Check if a player has been given this role, or it is the default role
--- A role a player holds does not always apply, see ExpRoles.get_player_roles
--- @param self ExpRoles.Role
--- @param player LuaPlayer? nil for the server
--- @return boolean
function Role.has_player(self, player)
    local valid = not_server(player)
    if not valid then return self == server_role end
    if self.id == script_data.default_role_id then return true end
    return get_held_role_set(valid.name)[self.id] == true
end

--- Get the names of every player who has been given this role
--- This includes players who have never joined this map, and is not affected
--- by priority, so a jailed moderator is still listed under moderator
--- @param self ExpRoles.Role
--- @return string[]
function Role.get_player_names(self)
    local names, seen = {}, {}
    for _, players in pairs{ script_data.synced_players, script_data.local_players } do
        for player_name, role_ids in pairs(players) do
            if not seen[player_name] then
                for _, role_id in pairs(role_ids) do
                    if role_id == self.id then
                        seen[player_name] = true
                        names[#names + 1] = player_name
                        break
                    end
                end
            end
        end
    end

    return names
end

--- Get the players on this map who have been given this role
--- @param self ExpRoles.Role
--- @param online boolean? When given, filter by connected state
--- @return LuaPlayer[]
function Role.get_players(self, online)
    local players = {}
    for _, player_name in pairs(self:get_player_names()) do
        local player = game.get_player(player_name)
        if player and (online == nil or player.connected == online) then
            players[#players + 1] = player
        end
    end

    return players
end

--- Print a message to every online player who has been given this role
--- @param self ExpRoles.Role
--- @param message LocalisedString
--- @return number # Number of players the message was sent to
function Role.print(self, message)
    local players = self:get_players(true)
    for _, player in pairs(players) do
        player.print(message)
    end

    return #players
end

--[[
    Permission triggers
]]

--- Register a callback run with the state of a permission whenever the roles
--- of a player may have changed, and when they join the game
--- @param permission string
--- @param callback fun(player: LuaPlayer, state: boolean)
function ExpRoles.define_permission_trigger(permission, callback)
    permission_triggers[permission] = Async.register(callback)
end

--- Run every permission trigger for a player
--- @param player LuaPlayer
local function apply_permission_triggers(player)
    for permission, async_function in pairs(permission_triggers) do
        async_function(player, ExpRoles.player_has_permission(player, permission))
    end
end

--[[
    Assignment
]]

--- Raise the roles changed event and tell the player what changed
--- @param player LuaPlayer
--- @param assigned ExpRoles.Role[]
--- @param unassigned ExpRoles.Role[]
--- @param by_player_name string?
--- @param silent boolean?
local function emit_player_roles_changed(player, assigned, unassigned, by_player_name, silent)
    by_player_name = by_player_name or (game.player and game.player.name) or "<server>"
    local by_player = game.get_player(by_player_name)

    local assigned_ids, unassigned_ids = {}, {}
    local assigned_names, unassigned_names = {}, {}
    for index, role in ipairs(assigned) do
        assigned_ids[index], assigned_names[index] = role.id, role.name
    end
    for index, role in ipairs(unassigned) do
        unassigned_ids[index], unassigned_names[index] = role.id, role.name
    end

    if not silent then
        if #assigned > 0 then
            game.print{ "exp-roles.game-message-assign", player.name, table.concat(assigned_names, ", "), by_player_name }
        end
        if #unassigned > 0 then
            game.print{ "exp-roles.game-message-unassign", player.name, table.concat(unassigned_names, ", "), by_player_name }
        end
    end

    if #assigned > 0 then
        player.play_sound{ path = "utility/achievement_unlocked" }
    elseif #unassigned > 0 then
        player.play_sound{ path = "utility/game_lost" }
    end

    script.raise_event(ExpRoles.events.on_player_roles_changed, {
        name = ExpRoles.events.on_player_roles_changed,
        tick = game.tick,
        player_index = player.index,
        by_player_index = by_player and by_player.index or 0,
        assigned = assigned_ids,
        unassigned = unassigned_ids,
    })

    apply_permission_triggers(player)
end

--- Compare the roles a player had been given before and after a change and
--- raise the event for what differs
--- @param player_name string
--- @param before table<number, true>
--- @param by_player_name string?
--- @param silent boolean?
local function emit_held_diff(player_name, before, by_player_name, silent)
    local player = game.get_player(player_name)
    if not player then return end

    local after = get_held_role_set(player_name)
    local assigned, unassigned = {}, {}
    for role_id in pairs(after) do
        if not before[role_id] then assigned[#assigned + 1] = script_data.roles[role_id] end
    end
    for role_id in pairs(before) do
        if not after[role_id] then unassigned[#unassigned + 1] = script_data.roles[role_id] end
    end

    if #assigned > 0 or #unassigned > 0 then
        emit_player_roles_changed(player, sort_roles(assigned), sort_roles(unassigned), by_player_name, silent)
    end
end

--- Remove a role id from a list, returns true when it was present
--- @param list number[]?
--- @param role_id number
--- @return boolean
local function remove_role_id(list, role_id)
    if not list then return false end
    for index, value in ipairs(list) do
        if value == role_id then
            table.remove(list, index)
            return true
        end
    end
    return false
end

--- Add a role id to a list unless it is already present
--- @param list number[]
--- @param role_id number
--- @return boolean
local function add_role_id(list, role_id)
    for _, value in ipairs(list) do
        if value == role_id then return false end
    end
    list[#list + 1] = role_id
    return true
end

--- Apply a role change to the local state, returns true when something changed
--- @param player_name string
--- @param role ExpRoles.Role
--- @param assign boolean
--- @param sync boolean
--- @return boolean
local function apply_local_change(player_name, role, assign, sync)
    local local_roles = script_data.local_players[player_name] or {}
    local pending = script_data.pending[player_name] or {}
    local changed

    if assign then
        local synced = script_data.synced_players[player_name] or {}
        local already_synced = false
        for _, role_id in pairs(synced) do
            if role_id == role.id then already_synced = true break end
        end
        changed = not already_synced and add_role_id(local_roles, role.id)
        if changed and sync then add_role_id(pending, role.id) end
    else
        changed = remove_role_id(local_roles, role.id)
        remove_role_id(pending, role.id)
        -- A synced role is only taken away here when the controller is
        -- being told as well, otherwise the next update would restore it
        if sync then
            changed = remove_role_id(script_data.synced_players[player_name], role.id) or changed
        end
    end

    script_data.local_players[player_name] = next(local_roles) and local_roles or nil
    script_data.pending[player_name] = next(pending) and pending or nil

    return changed
end

--- Send a role change to the controller
--- @param player_name string
--- @param role ExpRoles.Role
--- @param assign boolean
local function emit_assignment_update(player_name, role, assign)
    if not script_data.emit_updates then return end

    clusterio_api.send_json("exp_roles:assignment_update", {
        name = player_name,
        assign = assign and { role.id } or nil,
        unassign = not assign and { role.id } or nil,
    })
end

--- Change whether a player holds a role
--- @param role ExpRoles.Role
--- @param player LuaPlayer
--- @param assign boolean
--- @param options ExpRoles.AssignOptions?
local function change_player_role(role, player, assign, options)
    local valid = not_server(player)
    if not valid then return end
    options = options or {}

    local player_name = valid.name
    local before = get_held_role_set(player_name)
    if not apply_local_change(player_name, role, assign, not options.local_only) then return end

    if not options.local_only then
        emit_assignment_update(player_name, role, assign)
    end

    emit_held_diff(player_name, before, options.by_player_name, options.silent)
end

--- Give a player this role, the change is sent to the controller unless local_only is set
--- @param self ExpRoles.Role
--- @param player LuaPlayer
--- @param options ExpRoles.AssignOptions?
function Role.assign(self, player, options)
    change_player_role(self, player, true, options)
end

--- Take this role from a player, the change is sent to the controller unless local_only is set
--- @param self ExpRoles.Role
--- @param player LuaPlayer
--- @param options ExpRoles.AssignOptions?
function Role.unassign(self, player, options)
    change_player_role(self, player, false, options)
end

--[[
    Sync entry points
]]

--- Stop holding a pending role locally once the controller has confirmed it
--- Roles assigned with local_only are never pending so are untouched
--- @param player_name string
local function drop_confirmed_local(player_name)
    local pending = script_data.pending[player_name]
    if pending then
        for _, role_id in pairs(script_data.synced_players[player_name] or {}) do
            if remove_role_id(pending, role_id) then
                remove_role_id(script_data.local_players[player_name], role_id)
            end
        end
        if not next(pending) then script_data.pending[player_name] = nil end
    end

    local local_roles = script_data.local_players[player_name]
    if local_roles and not next(local_roles) then
        script_data.local_players[player_name] = nil
    end
end

--- Restore local references to persistent script data after load
function ExpRoles.on_load()
    script_data = compat.script_data["exp_roles"]
end

--- Enable or disable sending role changes back to the controller
--- @param enabled boolean?
function ExpRoles.set_emit_events(enabled)
    script_data.emit_updates = enabled ~= false
end

--- Apply the triggers of every connected player, and raise the event so guis
--- can refresh, after the roles themselves have changed
local function roles_changed()
    for _, player in pairs(game.connected_players) do
        emit_player_roles_changed(player, {}, {}, "<server>", true)
    end
end

--- Replace all local state with the state held by the controller
--- Permission names are sent once and referenced by index, see encodeRolesForLua
--- @param payload { permission_names: string[], roles: table[], assignments: table[] }
function ExpRoles.initialise(payload)
    local emit_updates = script_data.emit_updates
    script_data.emit_updates = false

    local names = payload.permission_names
    script_data.roles = {}
    script_data.default_role_id = nil
    for _, record in pairs(payload.roles) do
        if not record.is_deleted then
            script_data.roles[record.id] = decode_role(record, names)
            if record.is_default then
                script_data.default_role_id = record.id
            end
        end
    end

    script_data.synced_players = {}
    for _, record in pairs(payload.assignments) do
        if not record.is_deleted and record.role_ids then
            script_data.synced_players[record.name] = record.role_ids
        end
    end

    -- The state received here is authoritative, so a pending role is either
    -- confirmed and now held by synced_players, or it never landed and has to
    -- be given up; either way it stops being held locally
    for player_name, pending in pairs(script_data.pending) do
        drop_confirmed_local(player_name)
        for _, role_id in pairs(pending) do
            remove_role_id(script_data.local_players[player_name], role_id)
        end
        local local_roles = script_data.local_players[player_name]
        if local_roles and not next(local_roles) then
            script_data.local_players[player_name] = nil
        end
    end
    script_data.pending = {}

    roles_changed()
    script_data.emit_updates = emit_updates
end

--- Receive changes to roles from the controller
--- @param records table[]
function ExpRoles.receive_role_updates(records)
    for _, record in pairs(records) do
        if record.is_deleted then
            script_data.roles[record.id] = nil
            if script_data.default_role_id == record.id then
                script_data.default_role_id = nil
            end
        else
            script_data.roles[record.id] = decode_role(record)
            if record.is_default then
                script_data.default_role_id = record.id
            elseif script_data.default_role_id == record.id then
                script_data.default_role_id = nil
            end
        end
    end

    roles_changed()
end

--- Receive changes to the roles held by players from the controller
--- @param records table[]
function ExpRoles.receive_assignment_updates(records)
    for _, record in pairs(records) do
        local player_name = record.name
        local before = get_held_role_set(player_name)

        if record.is_deleted then
            script_data.synced_players[player_name] = nil
        else
            script_data.synced_players[player_name] = record.role_ids or {}
        end

        drop_confirmed_local(player_name)
        emit_held_diff(player_name, before, "<server>")
    end
end

--- Roll back a local assignment which the controller rejected
--- @param payload { name: string, role_ids: number[] }
function ExpRoles.reject_assignment(payload)
    local player = game.get_player(payload.name)
    for _, role_id in pairs(payload.role_ids) do
        local role = script_data.roles[role_id]
        if role and player then
            role:unassign(player, { by_player_name = "<server>", silent = true, local_only = true })
        elseif role then
            apply_local_change(payload.name, role, false, false)
        end
    end
end

--- Get the current script data for debugging purposes
--- @package
function ExpRoles._script_data()
    return script_data
end

--[[
    Event handlers, these are wired up by events.lua
]]

--- Create persistent script data if this is the first startup
function ExpRoles.on_server_startup()
    if compat.script_data["exp_roles"] == nil then
        --- @type ExpRoles.ScriptData
        compat.script_data["exp_roles"] = {
            roles = {},
            synced_players = {},
            local_players = {},
            pending = {},
            default_role_id = nil,
            emit_updates = false,
        }
    end

    ExpRoles.on_load()
end

--- Apply the permission triggers for a player who just joined
--- @param event EventData.on_player_joined_game
function ExpRoles.on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if player then apply_permission_triggers(player) end
end

return ExpRoles
