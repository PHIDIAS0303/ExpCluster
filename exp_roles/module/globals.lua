--[[
It is best practice to not expose any globals because all modules share a global environment
However, sometimes you need globals, for example to access functions within rcon commands
Therefore, we advise that this should be the only file in your module to expose globals
]]

--- @diagnostic disable: global-in-non-module

-- Access using `/sc exp_roles.foo()`
exp_roles = require("modules/exp_roles/control")
