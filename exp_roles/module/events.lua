--[[-- ExpRoles - Events
Wires the role sync into the factorio event handler.

This is kept apart from control.lua because `ExpRoles.events` holds the ids of
the events this module raises, which is the interface the legacy role system
had, and event_handler expects `events` to be the handlers to register.
]]

local clusterio_api = require("modules/clusterio/api")
local ExpRoles = require("modules/exp_roles/control")

return {
    on_load = ExpRoles.on_load,
    events = {
        [clusterio_api.events.on_server_startup] = ExpRoles.on_server_startup,
        [defines.events.on_multiplayer_init] = ExpRoles.on_server_startup,
        [defines.events.on_player_joined_game] = ExpRoles.on_player_joined_game,
    },
}
