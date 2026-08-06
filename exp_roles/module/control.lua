--[[-- ExpRoles
Replaces the legacy role system with clusterio's roles and permissions.

Roles and the players who hold them are owned by the controller. This module
mirrors that state into the game and presents the same interface the legacy
`expcore.roles` module did, so existing call sites keep working.

Assignments made in game are applied locally first and then sent to the
controller, which avoids callers having to deal with the round trip. A local
assignment which is never sent, such as one earned from time on this map, can be
made with `assign_player_local`.
]]

local clusterio_api = require("modules/clusterio/api")
local compat = require("modules/clusterio/compat") --[[@as LibCompat]]
local Async = require("modules/exp_util/async")

--- @class ExpRoles
local ExpRoles = {
    config = {
        --- Role names in order, a lower index is a more privileged role
        order = {}, --- @type string[]
        --- Roles indexed by name, this table is never replaced
        roles = {}, --- @type table<string, ExpRoles.Role>
        --- Role names held by each player, includes local assignments
        players = {}, --- @type table<string, string[]>
        --- Async handles run when a flag is gained or lost
        flags = {}, --- @type table<string, Async.AsyncFunction>
    },
    events = {
        on_role_assigned = script.generate_event_name(),
        on_role_unassigned = script.generate_event_name(),
    },
}

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
--- @field custom_tag string
--- @field custom_color Color?
--- @field allowed_actions table<string, boolean> Permission names granted by this role
--- @field flags table<string, boolean> Legacy flag names granted by this role
--- @field block_auto_assign boolean

--- @class ExpRoles.ScriptData
--- @field roles table<number, ExpRoles.Role> Roles indexed by clusterio id
--- @field synced_players table<string, number[]> Role ids from the controller
--- @field local_players table<string, number[]> Role ids which only exist on this map
--- @field pending table<string, number[]> Local role ids waiting to be confirmed
--- @field default_role_id number? Role every player holds
--- @field emit_updates boolean
local script_data = {}

--[[
    Permission names
]]

--- Legacy actions which map onto core clusterio permissions
local core_action_permissions = {
    ["command/assign-role"] = "core.user.update_roles",
    ["command/unassign-role"] = "core.user.update_roles",
    ["command/get-roles"] = "core.role.list",
}

--- Cache for the action to permission mapping, this is a hot path
local action_permissions = {} --- @type table<string, string>
local flag_permissions = {} --- @type table<string, string>

--- Convert a legacy action such as `gui/warp-list/add` into a permission name
--- This must match permissionFromAction in exp_scenario/permissions.ts
--- @param action string
--- @return string
local function permission_from_action(action)
    local permission = action_permissions[action]
    if permission then return permission end

    permission = core_action_permissions[action]
    if not permission then
        local body = action:gsub("%-", "_"):gsub("/", ".")
        if not body:find(".", 1, true) then
            body = "action." .. body
        end
        permission = "exp_scenario." .. body
    end

    action_permissions[action] = permission
    return permission
end

--- Convert a legacy flag such as `report-immune` into a permission name
--- This must match permissionFromFlag in exp_scenario/permissions.ts
--- @param flag string
--- @return string
local function permission_from_flag(flag)
    local permission = flag_permissions[flag]
    if permission then return permission end

    permission = "exp_scenario.flag." .. (flag:gsub("%-", "_"))
    flag_permissions[flag] = permission
    return permission
end

--[[
    Role state
]]

--- Rebuild config.order and config.roles from the synced roles, in place
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

    local order, by_name = ExpRoles.config.order, ExpRoles.config.roles
    for key in pairs(order) do order[key] = nil end
    for key in pairs(by_name) do by_name[key] = nil end

    for index, role in ipairs(roles) do
        role.index = index
        order[index] = role.name
        by_name[role.name] = role
    end
end

--- Build a role from the record sent by the controller
--- @param record table
--- @param names string[]? When given, record.permissions holds indexes into it
--- @return ExpRoles.Role
local function decode_role(record, names)
    local meta = record.meta
    local allowed_actions = {}
    if names then
        -- Indexes are zero based, having come from javascript
        for _, index in pairs(record.permissions) do
            allowed_actions[names[index + 1]] = true
        end
    else
        for _, permission in pairs(record.permissions) do
            allowed_actions[permission] = true
        end
    end

    local flags = {}
    for permission in pairs(allowed_actions) do
        local flag = permission:match("^exp_scenario%.flag%.(.+)$")
        if flag then flags[flag] = true end
    end

    --- @type ExpRoles.Role
    return setmetatable({
        id = record.id,
        name = record.name,
        short_hand = meta.short_hand or record.name,
        order = meta.order or record.id,
        index = meta.order or record.id,
        priority = meta.priority or 0,
        custom_tag = meta.tag or "",
        custom_color = meta.color,
        allowed_actions = allowed_actions,
        flags = flags,
        block_auto_assign = meta.block_auto_assign or false,
    }, { __index = ExpRoles._prototype })
end

--- Refresh the legacy view of the roles a player holds
--- @param player_name string
local function rebuild_player_view(player_name)
    local role_ids = {}
    for _, role_id in pairs(script_data.synced_players[player_name] or {}) do
        role_ids[#role_ids + 1] = role_id
    end
    for _, role_id in pairs(script_data.local_players[player_name] or {}) do
        role_ids[#role_ids + 1] = role_id
    end

    if #role_ids == 0 then
        ExpRoles.config.players[player_name] = nil
        return
    end

    local names, seen = {}, {}
    for _, role_id in pairs(role_ids) do
        local role = script_data.roles[role_id]
        if role and not seen[role.name] then
            seen[role.name] = true
            names[#names + 1] = role.name
        end
    end

    ExpRoles.config.players[player_name] = names
end

--- Rebuild the legacy view for every known player
local function rebuild_all_player_views()
    local players = ExpRoles.config.players
    for key in pairs(players) do players[key] = nil end

    local seen = {}
    for player_name in pairs(script_data.synced_players) do seen[player_name] = true end
    for player_name in pairs(script_data.local_players) do seen[player_name] = true end
    for player_name in pairs(seen) do rebuild_player_view(player_name) end
end

--[[
    Role lookup
]]

--- Get a role by its name
--- @param name string
--- @return ExpRoles.Role?
function ExpRoles.get_role_by_name(name)
    return ExpRoles.config.roles[name]
end

--- Get a role by its position in the role order
--- @param index number
--- @return ExpRoles.Role?
function ExpRoles.get_role_by_order(index)
    local name = ExpRoles.config.order[index]
    return name and ExpRoles.config.roles[name]
end

--- Get a role from a name, order index, or role
--- @param any string | number | ExpRoles.Role
--- @return ExpRoles.Role?
function ExpRoles.get_role_from_any(any)
    local t_any = type(any)
    local as_number = tonumber(any)
    if as_number then
        return ExpRoles.get_role_by_order(as_number)
    elseif t_any == "string" then
        return ExpRoles.get_role_by_name(any)
    elseif t_any == "table" then
        return ExpRoles.get_role_by_name(any.name)
    end
end

--- Get all roles in order, the most privileged first
--- @return ExpRoles.Role[]
function ExpRoles.get_roles_ordered()
    local rtn = {}
    for index, role_name in ipairs(ExpRoles.config.order) do
        rtn[index] = ExpRoles.config.roles[role_name]
    end
    return rtn
end

--- Role used when there is no player, such as for commands run by the server
--- It bypasses every permission check the same way the legacy root role did
local server_role = setmetatable({
    id = -1,
    name = "<server>",
    short_hand = "SRV",
    order = 0,
    index = 0,
    priority = 0,
    custom_tag = "",
    custom_color = nil,
    allowed_actions = { ["core.admin"] = true },
    flags = {},
    block_auto_assign = true,
}, { __index = ExpRoles._prototype })

--- Get the roles a player holds, including the default role
--- Only the roles with the highest priority are returned, which lets a role
--- such as Jail suppress every other role a player holds
--- @param player LuaPlayer | string | nil
--- @return ExpRoles.Role[]
function ExpRoles.get_player_roles(player)
    local player_name = type(player) == "table" and player.name or player --[[@as string?]]
    -- The server is not a player and is allowed to do anything
    if player_name == nil then return { server_role } end

    local role_ids = {}
    if script_data.default_role_id then
        role_ids[#role_ids + 1] = script_data.default_role_id
    end
    for _, role_id in pairs(script_data.synced_players[player_name] or {}) do
        role_ids[#role_ids + 1] = role_id
    end
    for _, role_id in pairs(script_data.local_players[player_name] or {}) do
        role_ids[#role_ids + 1] = role_id
    end

    local roles, highest_priority, seen = {}, nil, {}
    for _, role_id in pairs(role_ids) do
        local role = script_data.roles[role_id]
        if role and not seen[role_id] then
            seen[role_id] = true
            if highest_priority == nil or role.priority > highest_priority then
                highest_priority = role.priority
            end
            roles[#roles + 1] = role
        end
    end

    local rtn = {}
    for _, role in pairs(roles) do
        if role.priority == highest_priority then
            rtn[#rtn + 1] = role
        end
    end

    table.sort(rtn, function(a, b) return a.index < b.index end)
    return rtn
end

--- Get the most privileged role a player holds
--- @param player LuaPlayer | string | nil
--- @return ExpRoles.Role?
function ExpRoles.get_player_highest_role(player)
    return ExpRoles.get_player_roles(player)[1]
end

--[[
    Permission checks
]]

--- Check if a player is allowed to perform an action
--- @param player LuaPlayer | string | nil
--- @param action string A legacy action such as `command/kill`
--- @return boolean
function ExpRoles.player_allowed(player, action)
    local permission = permission_from_action(action)
    for _, role in pairs(ExpRoles.get_player_roles(player)) do
        local allowed = role.allowed_actions
        if allowed["core.admin"] or allowed[permission] then
            return true
        end
    end

    return false
end

--- Check if a player has a flag set by at least one of their roles
--- @param player LuaPlayer | string | nil
--- @param flag_name string
--- @return boolean
function ExpRoles.player_has_flag(player, flag_name)
    local permission = permission_from_flag(flag_name)
    for _, role in pairs(ExpRoles.get_player_roles(player)) do
        if role.allowed_actions[permission] then
            return true
        end
    end

    return false
end

--- Check if a player holds a role
--- @param player LuaPlayer | string | nil
--- @param search_role string | number | ExpRoles.Role
--- @return boolean
function ExpRoles.player_has_role(player, search_role)
    local role = ExpRoles.get_role_from_any(search_role)
    if not role then return false end

    for _, player_role in pairs(ExpRoles.get_player_roles(player)) do
        if player_role.name == role.name then return true end
    end

    return false
end

--- Check if a player bypasses all permission checks
--- This replaces the legacy root role
--- @param player LuaPlayer | string | nil
--- @return boolean
function ExpRoles.is_root(player)
    for _, role in pairs(ExpRoles.get_player_roles(player)) do
        if role.allowed_actions["core.admin"] then return true end
    end

    return false
end

--[[
    Role prototype
]]

--- Check if this role allows an action
--- @param self ExpRoles.Role
--- @param action string
--- @return boolean
function Role:is_allowed(action)
    local allowed = self.allowed_actions
    return allowed["core.admin"] or allowed[permission_from_action(action)] or false
end

--- Check if this role sets a flag
--- @param self ExpRoles.Role
--- @param name string
--- @return boolean
function Role:has_flag(name)
    return self.allowed_actions[permission_from_flag(name)] or false
end

--- Get the players who hold this role
--- @param self ExpRoles.Role
--- @param online boolean? When given, filter by connected state
--- @return LuaPlayer[]
function Role:get_players(online)
    local players = {}
    for player_name, role_names in pairs(ExpRoles.config.players) do
        for _, role_name in pairs(role_names) do
            if role_name == self.name then
                local player = game.players[player_name]
                if player and (online == nil or player.connected == online) then
                    players[#players + 1] = player
                end
                break
            end
        end
    end

    return players
end

--- Print a message to every online player who holds this role
--- @param self ExpRoles.Role
--- @param message LocalisedString
--- @return number # Number of players the message was sent to
function Role:print(message)
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
        local resolved = ExpRoles.get_role_from_any(role)
        if resolved then resolved:print(message) end
    end
end

--- Print a message to every player holding the given role or a more privileged one
--- @param role string | number | ExpRoles.Role
--- @param message LocalisedString
function ExpRoles.print_to_roles_higher(role, message)
    local resolved = ExpRoles.get_role_from_any(role)
    if not resolved then return end

    local roles = {}
    for index, role_name in ipairs(ExpRoles.config.order) do
        if index <= resolved.index and role_name ~= ExpRoles.get_default_role_name() then
            roles[#roles + 1] = role_name
        end
    end

    ExpRoles.print_to_roles(roles, message)
end

--- Print a message to every player holding the given role or a less privileged one
--- @param role string | number | ExpRoles.Role
--- @param message LocalisedString
function ExpRoles.print_to_roles_lower(role, message)
    local resolved = ExpRoles.get_role_from_any(role)
    if not resolved then return end

    local roles = {}
    for index, role_name in ipairs(ExpRoles.config.order) do
        if index >= resolved.index and role_name ~= ExpRoles.get_default_role_name() then
            roles[#roles + 1] = role_name
        end
    end

    ExpRoles.print_to_roles(roles, message)
end

--- Get the name of the role every player holds
--- @return string?
function ExpRoles.get_default_role_name()
    local role = script_data.default_role_id and script_data.roles[script_data.default_role_id]
    return role and role.name or nil
end

--[[
    Flags
]]

--- Register a callback run when a player gains or loses a flag
--- @param name string
--- @param callback fun(player: LuaPlayer, state: boolean)
function ExpRoles.define_flag_trigger(name, callback)
    ExpRoles.config.flags[name] = Async.register(callback)
end

--- Run every flag trigger for a player
--- @param player LuaPlayer
local function apply_flag_triggers(player)
    for flag, async_function in pairs(ExpRoles.config.flags) do
        async_function(player, ExpRoles.player_has_flag(player, flag))
    end
end

--[[
    Assignment
]]

--- Raise the assigned or unassigned event and tell the player what changed
--- @param player LuaPlayer
--- @param change_type "assign" | "unassign"
--- @param roles ExpRoles.Role[]
--- @param by_player_name string?
--- @param silent boolean?
local function emit_player_roles_updated(player, change_type, roles, by_player_name, silent)
    by_player_name = by_player_name or (game.player and game.player.name) or "<server>"
    local by_player = game.players[by_player_name]

    local role_names = {}
    for index, role in ipairs(roles) do
        role_names[index] = role.name
    end

    if not silent then
        local joined = table.concat(role_names, ", ")
        game.print(change_type == "assign"
            and { "exp-roles.game-message-assign", player.name, joined, by_player_name }
            or { "exp-roles.game-message-unassign", player.name, joined, by_player_name })
    end

    if change_type == "assign" then
        player.play_sound{ path = "utility/achievement_unlocked" }
    else
        player.play_sound{ path = "utility/game_lost" }
    end

    local event = change_type == "assign" and ExpRoles.events.on_role_assigned or ExpRoles.events.on_role_unassigned
    script.raise_event(event, {
        name = event,
        tick = game.tick,
        player_index = player.index,
        by_player_index = by_player and by_player.index or 0,
        roles = role_names,
    })

    apply_flag_triggers(player)
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
        local resolved = ExpRoles.get_role_from_any(role)
        if resolved then rtn[#rtn + 1] = resolved end
    end

    return rtn
end

--- Apply a role change locally and tell the controller about it
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
    rebuild_player_view(player_name)

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
    local player_name = type(player) == "table" and player.name or player --[[@as string?]]
    if not player_name then return end

    local role_objects = resolve_roles(roles)
    if #role_objects == 0 then return end

    local changed = apply_local_change(player_name, role_objects, change_type, sync)
    if #changed == 0 then return end

    if sync then
        emit_assignment_update(player_name, changed, change_type)
    end

    local valid_player = game.get_player(player_name)
    if valid_player then
        emit_player_roles_updated(valid_player, change_type, changed, by_player_name, silent)
    end
end

--- Give a player one or more roles, the change is sent to the controller
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string?
--- @param skip_checks boolean? Unused, kept for compatibility
--- @param silent boolean?
function ExpRoles.assign_player(player, roles, by_player_name, skip_checks, silent)
    change_player_roles(player, roles, "assign", by_player_name, silent, true)
end

--- Take one or more roles from a player, the change is sent to the controller
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string?
--- @param skip_checks boolean? Unused, kept for compatibility
--- @param silent boolean?
function ExpRoles.unassign_player(player, roles, by_player_name, skip_checks, silent)
    change_player_roles(player, roles, "unassign", by_player_name, silent, true)
end

--- Give a player one or more roles on this map only, the controller is not told
--- Use this for roles earned from progress which does not leave this map
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string?
--- @param silent boolean?
function ExpRoles.assign_player_local(player, roles, by_player_name, silent)
    change_player_roles(player, roles, "assign", by_player_name, silent, false)
end

--- Take one or more local roles from a player, the controller is not told
--- @param player LuaPlayer | string
--- @param roles any A role, role name, or array of either
--- @param by_player_name string?
--- @param silent boolean?
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
        rebuild_all_player_views()
    end
end

--- Enable or disable sending role changes back to the controller
--- @param enabled boolean?
function ExpRoles.set_emit_events(enabled)
    script_data.emit_updates = enabled ~= false
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
    rebuild_all_player_views()

    for _, player in pairs(game.connected_players) do
        apply_flag_triggers(player)
    end

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
    rebuild_all_player_views()

    for _, player in pairs(game.connected_players) do
        apply_flag_triggers(player)
    end
end

--- Receive changes to the roles held by players from the controller
--- @param records table[]
function ExpRoles.receive_assignment_updates(records)
    for _, record in pairs(records) do
        local player_name = record.name
        if record.is_deleted then
            script_data.synced_players[player_name] = nil
        else
            script_data.synced_players[player_name] = record.role_ids or {}
        end

        drop_confirmed_local(player_name)
        rebuild_player_view(player_name)

        local player = game.get_player(player_name)
        if player then apply_flag_triggers(player) end
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

--- Apply the flag triggers for a player who just joined
--- @param event EventData.on_player_joined_game
function ExpRoles.on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if player then apply_flag_triggers(player) end
end

return ExpRoles
