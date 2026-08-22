--[[-- Generic factorio stubs for plugin module tests
Provides the surface a clusterio module touches, recording what the module does
to it. Every stub raises an error when an unimplemented property is read, which
mirrors the game api and catches mistakes in tests early.

Plugins compose these from their own test/lua/env.lua, adding stubs of their
own through `stubs.requires` and `Stubs.strict`.
]]

local Stubs = {}

--- Give a table an index metamethod which raises on unknown properties
--- @generic T : table
--- @param name string Shown in the error message
--- @param tbl T
--- @param allowed_nil string[]? Properties which may be read while unset
--- @return T
function Stubs.strict(name, tbl, allowed_nil)
    local allowed = {}
    for _, key in pairs(allowed_nil or {}) do
        allowed[key] = true
    end

    return setmetatable(tbl, {
        __index = function(_, key)
            if allowed[key] then return nil end
            error(name .. " does not implement: " .. tostring(key), 2)
        end,
    })
end

--- Create an independent set of stubs, installed as the lua globals
function Stubs.new()
    local stubs = {
        events = {},  -- events raised through script.raise_event
        printed = {}, -- game.print and player.print messages
        sent = {},    -- payloads sent through the clusterio api
        sounds = {},  -- sounds played to players
    }

    local next_event_id = 100
    script = Stubs.strict("script", {
        generate_event_name = function()
            next_event_id = next_event_id + 1
            return next_event_id
        end,
        raise_event = function(id, data)
            stubs.events[#stubs.events + 1] = { id = id, data = data }
        end,
        register_metatable = function() end,
    })

    defines = Stubs.strict("defines", {
        events = Stubs.strict("defines.events", {
            on_player_joined_game = 1,
            on_multiplayer_init = 2,
        }),
    })

    local players_by_name, players_by_index, connected = {}, {}, {}
    game = Stubs.strict("game", {
        tick = 1,
        players = players_by_name,
        connected_players = connected,
        print = function(message) stubs.printed[#stubs.printed + 1] = message end,
        get_player = function(key) return players_by_name[key] or players_by_index[key] end,
    }, { "player" })

    --- Add a player to the stubbed game
    function stubs.add_player(name, index, is_connected)
        local player = Stubs.strict("LuaPlayer " .. name, {
            name = name,
            index = index,
            connected = is_connected ~= false,
            valid = true,
            play_sound = function(opts)
                stubs.sounds[#stubs.sounds + 1] = name .. ":" .. opts.path
            end,
            print = function(message)
                stubs.printed[#stubs.printed + 1] = { to = name, message }
            end,
        })
        players_by_name[name] = player
        players_by_index[index] = player
        if player.connected then connected[#connected + 1] = player end
        return player
    end

    --- A player object which represents the server
    stubs.server = Stubs.strict("server player", { index = 0, name = "<server>" })

    --- Modules resolved by the stubbed require, extend before loading the module
    stubs.requires = {
        ["modules/clusterio/api"] = Stubs.strict("clusterio api", {
            send_json = function(channel, data)
                stubs.sent[#stubs.sent + 1] = { channel = channel, data = data }
            end,
        }),
        ["modules/clusterio/compat"] = Stubs.strict("clusterio compat", { script_data = {} }),
        ["modules/exp_util/async"] = Stubs.strict("exp_util async", {
            register = function(callback)
                return function(...) return callback(...) end
            end,
        }),
    }
    require = function(name)
        return assert(stubs.requires[name], "Unexpected require: " .. name)
    end

    --- Forget everything recorded so far
    function stubs.reset_log()
        stubs.events, stubs.printed, stubs.sent, stubs.sounds = {}, {}, {}, {}
    end

    return stubs
end

return Stubs
