--[[-- Test environment for module/control.lua
The module specific extension between the shared stubs and the test files: it
extends each environment with a fresh copy of the roles module and the
fixtures below, and hands each test file a suite built around that.

Run as a chunk by test/lua/runner.js, receiving the shared folder. The suite
returned here becomes `...` in each test file.
]]

local shared_root = ... --- @type string
local source = assert(debug.getinfo(1, "S")).source:gsub("\\", "/")
local plugin_root = assert(source:match("^@(.*)/test/module/env%.lua$"))

local Framework = assert(loadfile(shared_root .. "/framework.lua"))() --- @type Framework

--- Standard fixture: permission names sent once and referenced by zero based index
local permission_names = {
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
local function role_records()
    return {
        { id = 0, name = "Cluster Admin", permissions = { 0 }, meta = meta(1, { short_hand = "SYS" }) },
        { id = 5, name = "Moderator", permissions = { 1, 2, 3, 5 }, meta = meta(2, { color = { r = 0, g = 170, b = 0 } }) },
        { id = 6, name = "Regular", permissions = { 1 }, meta = meta(3) },
        { id = 7, name = "Jail", permissions = {}, meta = meta(4, { priority = 1, block_auto_assign = true }) },
        { id = 1, name = "Player", permissions = { 4 }, meta = meta(5), is_default = true },
        { id = 9, name = "Gone", permissions = {}, meta = meta(6), is_deleted = true },
    }
end

--- Fixture role ids by name, avoiding a search of the roles on every lookup
local role_ids = {}
for _, record in ipairs(role_records()) do
    role_ids[record.name] = record.id
end

--- The environment given to each test: the stubs extended with a fresh copy
--- of the roles module and the fixture helpers
--- @class ExpRoles.TestEnv : Stubs
--- @field Roles ExpRoles A fresh copy of the roles module
--- @field R fun(name: string): ExpRoles.Role Get a fixture role by name
--- @field assignment fun(player_name: string, role_names: string[]): { name: string, role_ids: number[], is_deleted: boolean? }
--- @field script_data fun(): ExpRoles.ScriptData The module's script data, for asserting on internal state
--- @field initialise fun(assignments: table[]?) Load the standard fixture and the given assignments

return Framework.suite(function(env)
    --- @cast env ExpRoles.TestEnv
    env.Roles = assert(loadfile(plugin_root .. "/module/control.lua"))() --- @type ExpRoles
    env.Roles.on_server_startup()

    --- Get a fixture role by name, failing the test when it does not exist
    --- Roles added by a test are found by a search instead
    function env.R(name)
        local role_id = role_ids[name]
        if role_id then
            return (assert(env.Roles.get_role(role_id), "No role with id " .. role_id))
        end
        return (assert(env.Roles.get_role_by_name(name), "No role named " .. name))
    end

    --- An assignment record as the controller would send it, roles by name
    function env.assignment(player_name, role_names)
        local ids = {}
        for index, role_name in ipairs(role_names) do
            ids[index] = assert(role_ids[role_name], "No fixture role named " .. role_name)
        end
        return { name = player_name, role_ids = ids }
    end

    --- The module's script data, for asserting on internal state
    function env.script_data()
        --- @diagnostic disable-next-line: access-invisible
        return env.Roles._script_data()
    end

    --- Load the standard fixture and the given assignments
    function env.initialise(assignments)
        env.Roles.initialise{
            permission_names = permission_names,
            roles = role_records(),
            assignments = assignments or {},
        }
    end

    return env
end)
