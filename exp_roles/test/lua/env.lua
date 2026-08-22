--[[-- Test environment for module/control.lua
Composes the shared stubs and framework from the repository test folder with
the fixtures for this plugin. Each call to Env.new() is an independent
environment with a fresh copy of the roles module.

Run as a chunk by test/lua/runner.js, receiving the shared folder and
returning this table, which is in turn passed to each test chunk.
]]

local shared_root = ... --- @type string
local source = assert(debug.getinfo(1, "S")).source
local plugin_root = assert(source:match("^@(.*)/test/lua/env%.lua$"))

local Stubs = assert(loadfile(shared_root .. "/stubs.lua"))()
local Framework = assert(loadfile(shared_root .. "/framework.lua"))()

local Env = {
    --- Test registry for the file being run, see framework.lua
    Test = Framework.new(),
}

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
    local env = Stubs.new()

    env.Roles = assert(loadfile(plugin_root .. "/module/control.lua"))()
    env.Roles.on_server_startup()

    --- Get a role by name, failing the test when it does not exist
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

    return env
end

--- Run the declared tests, each against a fresh environment
function Env.finish()
    Env.Test.run(Env.new)
    return Env.Test.results_json()
end

return Env
