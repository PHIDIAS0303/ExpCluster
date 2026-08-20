--[[-- Test environment for module/control.lua
Stubs the factorio globals and the clusterio modules, then loads a fresh copy
of the roles module. Each call to Env.new() is independent.

Run as a chunk by test/helpers/lua.js, receiving the module directory and
returning this table, which is in turn passed to each test chunk.
]]

local module_root = ... --- @type string

local Env = {}

--- Standard fixture: permission names sent once and referenced by zero based index
Env.permission_names = {
    "core.admin",                       -- 0
    "exp_scenario.command.kill",        -- 1
    "exp_scenario.command.jail",        -- 2
    "exp_scenario.player.admin",        -- 3
    "exp_scenario.gui.readme",          -- 4
    "exp_scenario.command.assign_role", -- 5
}

local function meta(order, extra)
    local m = { id = 0, order = order }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end

--- Standard fixture: the roles as the controller would send them on initialise
function Env.role_records()
    return {
        { id = 0, name = "Cluster Admin", permissions = { 0 }, meta = meta(1, { short_hand = "SYS" }) },
        { id = 5, name = "Moderator", permissions = { 1, 2, 3, 5 }, meta = meta(2, { color = { r = 0, g = 170, b = 0 } }) },
        { id = 6, name = "Regular", permissions = { 1 }, meta = meta(3) },
        { id = 7, name = "Jail", permissions = {}, meta = meta(4, { priority = 1, block_auto_assign = true }) },
        { id = 1, name = "Player", permissions = { 4 }, meta = meta(5), is_default = true },
        { id = 9, name = "Gone", permissions = {}, meta = meta(6), is_deleted = true },
    }
end

function Env.assignment(name, role_ids)
    return { name = name, role_ids = role_ids }
end

--- Create an independent environment with a fresh copy of the roles module
function Env.new()
    local env = {
        events = {},   -- events raised through script.raise_event
        printed = {},  -- game.print and player.print messages
        sent = {},     -- payloads sent to the controller
        sounds = {},   -- sounds played to players
        results = {},  -- test results collected by env.check
    }

    local next_event_id = 100
    script = {
        generate_event_name = function()
            next_event_id = next_event_id + 1
            return next_event_id
        end,
        raise_event = function(id, data)
            env.events[#env.events + 1] = { id = id, data = data }
        end,
        register_metatable = function() end,
    }
    defines = { events = { on_player_joined_game = 1, on_multiplayer_init = 2 } }

    local players_by_name, players_by_index, connected = {}, {}, {}
    game = {
        tick = 1,
        player = nil,
        players = players_by_name,
        connected_players = connected,
        print = function(message) env.printed[#env.printed + 1] = message end,
        get_player = function(key) return players_by_name[key] or players_by_index[key] end,
    }

    local stubs = {
        ["modules/clusterio/api"] = {
            send_json = function(channel, data)
                env.sent[#env.sent + 1] = { channel = channel, data = data }
            end,
        },
        ["modules/clusterio/compat"] = { script_data = {} },
        ["modules/exp_util/async"] = {
            register = function(callback)
                return function(...) return callback(...) end
            end,
        },
    }
    require = function(name)
        return assert(stubs[name], "Unexpected require: " .. name)
    end

    --- Add a player to the stubbed game
    function env.add_player(name, index, is_connected)
        local player = {
            name = name,
            index = index,
            connected = is_connected ~= false,
            valid = true,
            play_sound = function(opts)
                env.sounds[#env.sounds + 1] = name .. ":" .. opts.path
            end,
            print = function(message)
                env.printed[#env.printed + 1] = { to = name, message }
            end,
        }
        players_by_name[name] = player
        players_by_index[index] = player
        if player.connected then connected[#connected + 1] = player end
        return player
    end

    --- A player object which represents the server
    env.server = setmetatable({ index = 0, name = "<server>" }, {
        __index = function(_, key) error("Server player field accessed: " .. tostring(key)) end,
    })

    env.Roles = assert(loadfile(module_root .. "/control.lua"))()
    env.Roles.on_server_startup()

    --- Get a role by name, failing the test file when it does not exist
    function env.R(name)
        return (assert(env.Roles.get_role_by_name(name), "No role named " .. name))
    end

    --- Load the standard fixture and the given assignments
    function env.initialise(assignments)
        env.Roles.initialise{
            permission_names = Env.permission_names,
            roles = Env.role_records(),
            assignments = assignments or {},
        }
    end

    --- Forget everything recorded so far
    function env.reset_log()
        env.events, env.printed, env.sent, env.sounds = {}, {}, {}, {}
    end

    --- Record one test result
    function env.check(ok, name, detail)
        env.results[#env.results + 1] = { name = name, ok = not not ok, detail = detail }
    end

    --- Shallow array equality
    function env.eq(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        if #a ~= #b then return false end
        for i = 1, #a do
            if a[i] ~= b[i] then return false end
        end
        return true
    end

    --- Names of an array of roles
    function env.names(roles)
        local rtn = {}
        for index, role in ipairs(roles) do
            rtn[index] = role.name
        end
        return rtn
    end

    --- Sorted copy of an array of strings
    function env.sorted(list)
        local rtn = {}
        for index, value in ipairs(list) do rtn[index] = value end
        table.sort(rtn)
        return rtn
    end

    return env
end

--- Encode the results of an environment as JSON for the javascript side
function Env.results_json(env)
    local function escape(value)
        return (value:gsub('[%c"\\]', function(c)
            return string.format("\\u%04x", c:byte())
        end))
    end

    local parts = {}
    for index, result in ipairs(env.results) do
        local detail = result.detail and string.format(',"detail":"%s"', escape(result.detail)) or ""
        parts[index] = string.format('{"name":"%s","ok":%s%s}', escape(result.name), tostring(result.ok), detail)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

return Env
