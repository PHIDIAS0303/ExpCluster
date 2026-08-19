--[[-- ExpRoles
Mirrors clusterio's roles and permissions into the game.

Roles, the permissions they grant, and the players who hold them are owned by
the controller. This module keeps a copy of that state and answers permission
checks from it, so a check such as `Roles.player_has_permission(player,
"exp_scenario.command.kill")` is answered from the same data the web ui shows.

Assignments made in game are applied locally first and then sent to the
controller, which avoids callers having to deal with the round trip. A local
assignment which is never sent, such as one earned from time on this map, can be
made with `assign_player_local`.

Only the roles with the highest priority a player holds are considered. Jail
sits above every other role, so holding it suppresses the rest, including the
default role every player has.
]]

local clusterio_api = require("modules/clusterio/api")
local compat = require("modules/clusterio/compat") --[[@as LibCompat]]
local Async = require("modules/exp_util/async")

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
--- @field assigned string[] Names of the roles which were assigned
--- @field unassigned string[] Names of the roles which were unassigned

--- Methods shared by every role, kept apart from the fields so that defining
--- them does not count as injecting fields into the role itself
--- @class ExpRoles.RolePrototype
local Role = {}
ExpRoles._prototype = Role

--- @class ExpRoles.Role : ExpRoles.RolePrototype
--- @field id number Clusterio role id
--- @field name string
--- @field short_hand string
--- @field order number Order given by the controller, which can have gaps
--- @field index number Position within the role order, with no gaps
--- @field priority number Only the highest priority roles a player holds apply
--- @field tag string
--- @field color Color?
--- @field permissions table<string, true> Permission names granted by this role
--- @field permission_group string? Factorio permission group holders are moved to
--- @field block_auto_assign boolean

--- @class ExpRoles.ScriptData
--- @field roles table<number, ExpRoles.Role> Roles indexed by clusterio id
--- @field synced_players table<string, number[]> Role ids from the controller
--- @field local_players table<string, number[]> Role ids which only exist on this map
--- @field pending table<string, number[]> Local role ids waiting to be confirmed
--- @field default_role_id number? Role every player holds
--- @field emit_updates boolean
local script_data = {}

--- Roles in order, the most privileged first, rebuilt from script data
local ordered_roles = {} --- @type ExpRoles.Role[]
--- Roles indexed by name, rebuilt from script data
local roles_by_name = {} --- @type table<string, ExpRoles.Role>
--- Async handlers run when the state of a permission may have changed
local permission_triggers = {} --- @type table<string, Async.AsyncFunction>

--- Move a player into a permission group, done async because the game does not
--- allow it from within every event
local set_permission_group_async = Async.register(function(player, group)
    --- @cast player LuaPlayer
    --- @cast group LuaPermissionGroup
    if player.valid and group.valid then
        group.add_player(player)
    end
end)

--[[
    Role state
]]

--- Rebuild the ordered and by name views of the roles
local function rebuild_role_views()
    local roles = {}
    for _, role in pairs(script_data.roles) do
        roles[#roles + 1] = role
    end

    -- Sorted on the order given by the controller, which can have gaps, the
    -- index each role is given is its position within that order
    table.sort(roles, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)

    ordered_roles, roles_by_name = {}, {}
    for index, role in ipairs(roles) do
        role.index = index
        ordered_roles[index] = role
        roles_by_name[role.name] = role
    end
end

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

    local group = meta.permission_group
    if group == "" then group = nil end

    --- @type ExpRoles.Role
    return setmetatable({
        id = record.id,
        name = record.name,
        short_hand = meta.short_hand or record.name,
        order = meta.order or record.id,
        index = meta.order or record.id,
        priority = meta.priority or 0,
        tag = meta.tag or "",
        color = meta.color,
        permissions = permissions,
        permission_group = group,
        block_auto_assign = meta.block_auto_assign or false,
    }, { __index = ExpRoles._prototype })
end

--- Get the name of a player from a player or a name, nil for the server
--- The server is represented by nil, or by a player object with index 0
--- @param player LuaPlayer | string | nil
--- @return string?
local function player_name_of(player)
    if type(player) == "string" then return player end
    if player and player.index ~= 0 then return player.name end
    return nil
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

--- Role ids which apply to a player, with the default role and priority applied
--- @param player_name string
--- @return table<number, true>
local function get_effective_role_ids(player_name)
    local role_ids = get_held_role_ids(player_name)
    if script_data.default_role_id then
        role_ids[#role_ids + 1] = script_data.default_role_id
    end

    local highest_priority
    for _, role_id in pairs(role_ids) do
        local role = script_data.roles[role_id]
        if role and (highest_priority == nil or role.priority > highest_priority) then
            highest_priority = role.priority
        end
    end

    local rtn = {}
    for _, role_id in pairs(role_ids) do
        local role = script_data.roles[role_id]
        if role and role.priority == highest_priority then
            rtn[role_id] = true
        end
    end
    return rtn
end

--[[
    Role lookup
]]

--- Get a role from its name, its clusterio id, or a role
--- @param any string | number | ExpRoles.Role
--- @return ExpRoles.Role?
function ExpRoles.get_role(any)
    local t_any = type(any)
    if t_any == "string" then
        return roles_by_name[any]
    elseif t_any == "number" then
        return script_data.roles[any]
    elseif t_any == "table" then
        return script_data.roles[any.id]
    end
end

--- Get every role in order, the most privileged first
--- @return ExpRoles.Role[]
function ExpRoles.get_roles()
    local rtn = {}
    for index, role in ipairs(ordered_roles) do
        rtn[index] = role
    end
    return rtn
end

--- Get the role every player holds
--- @return ExpRoles.Role?
function ExpRoles.get_default_role()
    return script_data.default_role_id and script_data.roles[script_data.default_role_id] or nil
end

--- Role used when there is no player, such as for commands run by the server
--- It has core.admin so it passes every permission check
local server_role = setmetatable({
    id = -1,
    name = "<server>",
    short_hand = "SRV",
    order = 0,
    index = 0,
    priority = 0,
    tag = "",
    color = nil,
    permissions = { ["core.admin"] = true },
    permission_group = nil,
    block_auto_assign = true,
}, { __index = ExpRoles._prototype })

--- Get the roles which apply to a player, including the default role
--- Only the roles with the highest priority are returned, which lets a role
--- such as Jail suppress every other role a player holds
--- @param player LuaPlayer | string | nil
--- @return ExpRoles.Role[]
function ExpRoles.get_player_roles(player)
    local player_name = player_name_of(player)
    -- The server is not a player and is allowed to do anything
    if player_name == nil then return { server_role } end

    local rtn = {}
    for role_id in pairs(get_effective_role_ids(player_name)) do
        rtn[#rtn + 1] = script_data.roles[role_id]
    end

    table.sort(rtn, function(a, b) return a.index < b.index end)
    return rtn
end

--- Get the most privileged role which applies to a player
--- @param player LuaPlayer | string | nil
--- @return ExpRoles.Role
function ExpRoles.get_player_highest_role(player)
    local role = ExpRoles.get_player_roles(player)[1]
    return (assert(role, "Player has no roles, is the default role set and exp_roles syncing?"))
end

--[[
    Permission checks
]]

--- Check if a player has a permission through any of their roles
--- @param player LuaPlayer | string | nil
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

--- Check if a role applies to a player
--- @param player LuaPlayer | string | nil
--- @param search_role string | number | ExpRoles.Role
--- @return boolean
function ExpRoles.player_has_role(player, search_role)
    local role = ExpRoles.get_role(search_role)
    if not role then return false end

    for _, player_role in pairs(ExpRoles.get_player_roles(player)) do
        if player_role.id == role.id then return true end
    end

    return false
end

--- Check if a player is more privileged than a role
--- A player with core.admin, which includes the server, outranks every role
--- @param player LuaPlayer | string | nil
--- @param role string | number | ExpRoles.Role
--- @return boolean
function ExpRoles.player_outranks_role(player, role)
    local resolved = ExpRoles.get_role(role)
    if not resolved then return false end
    if ExpRoles.player_has_permission(player, "core.admin") then return true end
    local highest = ExpRoles.get_player_roles(player)[1]
    return highest ~= nil and highest.index < resolved.index
end

--- Check if a player is more privileged than another player
--- A player with core.admin, which includes the server, outranks every player
--- @param player LuaPlayer | string | nil
--- @param other LuaPlayer | string | nil
--- @return boolean
function ExpRoles.player_outranks(player, other)
    if ExpRoles.player_has_permission(player, "core.admin") then return true end
    local highest = ExpRoles.get_player_roles(player)[1]
    local other_highest = ExpRoles.get_player_roles(other)[1]
    if highest == nil then return false end
    return other_highest == nil or highest.index < other_highest.index
end

--[[
    Role prototype
]]

--- Check if this role grants a permission
--- @param self ExpRoles.Role
--- @param permission string
--- @return boolean
function Role.has_permission(self, permission)
    local permissions = self.permissions
    return permissions["core.admin"] or permissions[permission] or false
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
    Printing to roles
]]

--- Print a message to every player holding one of the given roles
--- @param roles (string | number | ExpRoles.Role)[]
--- @param message LocalisedString
function ExpRoles.print_to_roles(roles, message)
    for _, role in pairs(roles) do
        local resolved = ExpRoles.get_role(role)
        if resolved then resolved:print(message) end
    end
end

--- Print a message to every player holding the given role or a more privileged one
--- The default role is never included
--- @param role string | number | ExpRoles.Role
--- @param message LocalisedString
function ExpRoles.print_to_roles_higher(role, message)
    local resolved = ExpRoles.get_role(role)
    if not resolved then return end

    local roles = {}
    for _, other in ipairs(ordered_roles) do
        if other.index <= resolved.index and other.id ~= script_data.default_role_id then
            roles[#roles + 1] = other
        end
    end

    ExpRoles.print_to_roles(roles, message)
end

--- Print a message to every player holding the given role or a less privileged one
--- The default role is never included
--- @param role string | number | ExpRoles.Role
--- @param message LocalisedString
function ExpRoles.print_to_roles_lower(role, message)
    local resolved = ExpRoles.get_role(role)
    if not resolved then return end

    local roles = {}
    for _, other in ipairs(ordered_roles) do
        if other.index >= resolved.index and other.id ~= script_data.default_role_id then
            roles[#roles + 1] = other
        end
    end

    ExpRoles.print_to_roles(roles, message)
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

--- Run every permission trigger for a player and move them into the permission
--- group of their most privileged role which names one
--- @param player LuaPlayer
local function apply_player_state(player)
    for permission, async_function in pairs(permission_triggers) do
        async_function(player, ExpRoles.player_has_permission(player, permission))
    end

    for _, role in ipairs(ExpRoles.get_player_roles(player)) do
        if role.permission_group then
            local group = game.permissions.get_group(role.permission_group)
            if group and (not player.permission_group or player.permission_group.name ~= group.name) then
                set_permission_group_async(player, group)
            end
            break
        end
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

    local assigned_names, unassigned_names = {}, {}
    for index, role in ipairs(assigned) do assigned_names[index] = role.name end
    for index, role in ipairs(unassigned) do unassigned_names[index] = role.name end

    if not silent then
        if #assigned_names > 0 then
            game.print{ "exp-roles.game-message-assign", player.name, table.concat(assigned_names, ", "), by_player_name }
        end
        if #unassigned_names > 0 then
            game.print{ "exp-roles.game-message-unassign", player.name, table.concat(unassigned_names, ", "), by_player_name }
        end
    end

    if #assigned_names > 0 then
        player.play_sound{ path = "utility/achievement_unlocked" }
    elseif #unassigned_names > 0 then
        player.play_sound{ path = "utility/game_lost" }
    end

    script.raise_event(ExpRoles.events.on_player_roles_changed, {
        name = ExpRoles.events.on_player_roles_changed,
        tick = game.tick,
        player_index = player.index,
        by_player_index = by_player and by_player.index or 0,
        assigned = assigned_names,
        unassigned = unassigned_names,
    })

    apply_player_state(player)
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
        table.sort(assigned, function(a, b) return a.index < b.index end)
        table.sort(unassigned, function(a, b) return a.index < b.index end)
        emit_player_roles_changed(player, assigned, unassigned, by_player_name, silent)
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

--- Convert a role, role name, or array of either into an array of roles
--- @param roles any
--- @return ExpRoles.Role[]
local function resolve_roles(roles)
    if type(roles) ~= "table" or roles.name then
        roles = { roles }
    end

    local rtn = {}
    for _, role in pairs(roles) do
        local resolved = ExpRoles.get_role(role)
        if resolved then rtn[#rtn + 1] = resolved end
    end

    return rtn
end

--- Apply a role change to the local state
--- @param player_name string
--- @param roles ExpRoles.Role[]
--- @param change_type "assign" | "unassign"
--- @param sync boolean
--- @return ExpRoles.Role[] # The roles which actually changed
local function apply_local_change(player_name, roles, change_type, sync)
    local local_roles = script_data.local_players[player_name] or {}
    local pending = script_data.pending[player_name] or {}
    local changed = {}

    for _, role in pairs(roles) do
        if change_type == "assign" then
            local synced = script_data.synced_players[player_name] or {}
            local already_synced = false
            for _, role_id in pairs(synced) do
                if role_id == role.id then already_synced = true break end
            end
            if not already_synced and add_role_id(local_roles, role.id) then
                changed[#changed + 1] = role
                if sync then add_role_id(pending, role.id) end
            end
        else
            local removed = remove_role_id(local_roles, role.id)
            remove_role_id(pending, role.id)
            -- A synced role is only taken away here when the controller is
            -- being told as well, otherwise the next update would restore it
            if sync then
                removed = remove_role_id(script_data.synced_players[player_name], role.id) or removed
            end
            if removed then
                changed[#changed + 1] = role
            end
        end
    end

    script_data.local_players[player_name] = next(local_roles) and local_roles or nil
    script_data.pending[player_name] = next(pending) and pending or nil

    return changed
end

--- Send a role change to the controller
--- @param player_name string
--- @param roles ExpRoles.Role[]
--- @param change_type "assign" | "unassign"
local function emit_assignment_update(player_name, roles, change_type)
    if not script_data.emit_updates then return end

    local role_ids = {}
    for index, role in ipairs(roles) do
        role_ids[index] = role.id
    end

    clusterio_api.send_json("exp_roles:assignment_update", {
        name = player_name,
        assign = change_type == "assign" and role_ids or nil,
        unassign = change_type == "unassign" and role_ids or nil,
    })
end

--- Change the roles a player holds
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param change_type "assign" | "unassign"
--- @param by_player_name string?
--- @param silent boolean?
--- @param sync boolean
local function change_player_roles(player, roles, change_type, by_player_name, silent, sync)
    local player_name = player_name_of(player)
    if not player_name then return end

    local role_objects = resolve_roles(roles)
    if #role_objects == 0 then return end

    local before = get_held_role_set(player_name)
    local changed = apply_local_change(player_name, role_objects, change_type, sync)
    if #changed == 0 then return end

    if sync then
        emit_assignment_update(player_name, changed, change_type)
    end

    emit_held_diff(player_name, before, by_player_name, silent)
end

--- Give a player one or more roles, the change is sent to the controller
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string? Shown in the game message, defaults to the current player or the server
--- @param silent boolean? When true no game message is printed
function ExpRoles.assign_player(player, roles, by_player_name, silent)
    change_player_roles(player, roles, "assign", by_player_name, silent, true)
end

--- Take one or more roles from a player, the change is sent to the controller
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string? Shown in the game message, defaults to the current player or the server
--- @param silent boolean? When true no game message is printed
function ExpRoles.unassign_player(player, roles, by_player_name, silent)
    change_player_roles(player, roles, "unassign", by_player_name, silent, true)
end

--- Give a player one or more roles on this map only, the controller is not told
--- Use this for roles earned from progress which does not leave this map
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string? Shown in the game message, defaults to the current player or the server
--- @param silent boolean? When true no game message is printed
function ExpRoles.assign_player_local(player, roles, by_player_name, silent)
    change_player_roles(player, roles, "assign", by_player_name, silent, false)
end

--- Take one or more local roles from a player, the controller is not told
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string? Shown in the game message, defaults to the current player or the server
--- @param silent boolean? When true no game message is printed
function ExpRoles.unassign_player_local(player, roles, by_player_name, silent)
    change_player_roles(player, roles, "unassign", by_player_name, silent, false)
end

--[[
    Sync entry points
]]

--- Stop holding a pending role locally once the controller has confirmed it
--- Roles assigned with assign_player_local are never pending so are untouched
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
    if script_data then
        rebuild_role_views()
    end
end

--- Enable or disable sending role changes back to the controller
--- @param enabled boolean?
function ExpRoles.set_emit_events(enabled)
    script_data.emit_updates = enabled ~= false
end

--- Apply the state of every connected player, and raise the event so guis
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

    rebuild_role_views()
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

    rebuild_role_views()
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
    local player_name = payload.name
    local roles = {}
    for _, role_id in pairs(payload.role_ids) do
        local role = script_data.roles[role_id]
        if role then roles[#roles + 1] = role end
    end

    if #roles == 0 then return end

    -- Sync is false, so this is never sent back to the controller
    change_player_roles(player_name, roles, "unassign", "<server>", true, false)
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

--- Apply the permission triggers and group for a player who just joined
--- @param event EventData.on_player_joined_game
function ExpRoles.on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if player then apply_player_state(player) end
end

return ExpRoles
