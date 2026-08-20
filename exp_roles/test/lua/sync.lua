--- Initialise semantics and updates from the controller
local Env = ...
local env = Env.new()
local check, eq, R = env.check, env.eq, env.R
local Roles = env.Roles
local sd = Roles._script_data()

local alice = env.add_player("alice", 1)
local carol = env.add_player("carol", 3)

local admin_state = {}
Roles.define_permission_trigger("exp_scenario.player.admin", function(player, state)
    admin_state[player.name] = state
end)

env.initialise{
    Env.assignment("alice", { 5 }),
    Env.assignment("zed", { 5, 6 }), -- has never joined this map
}
Roles.set_emit_events(true)

check(admin_state.alice == true and admin_state.carol == false, "triggers run for connected players on initialise")
check(#env.events == 2, "the roles changed event is raised once per connected player on initialise")
check(#env.events[1].data.assigned == 0 and #env.events[1].data.unassigned == 0, "initialise events are empty")
check(#env.printed == 0 and #env.sent == 0 and #env.sounds == 0, "initialise is silent and sends nothing")

-- Changes to the roles a player holds, made on the controller
env.reset_log()
Roles.receive_assignment_updates{ Env.assignment("carol", { 5 }) }
check(R("Moderator"):has_player(carol), "a controller assignment applies")
check(#env.events == 1 and eq(env.events[1].data.assigned, { 5 }), "a controller assignment raises the event")
check(env.events[1].data.by_player_index == 0, "controller changes have no by player")
check(#env.printed == 1 and env.printed[1][4] == "<server>", "a controller assignment is announced by the server")
check(admin_state.carol == true, "triggers follow controller assignments")

env.reset_log()
Roles.receive_assignment_updates{ { name = "carol", role_ids = {}, is_deleted = true } }
check(not R("Moderator"):has_player(carol), "a controller removal applies")
check(#env.events == 1 and eq(env.events[1].data.unassigned, { 5 }), "a controller removal raises the event")
check(admin_state.carol == false, "triggers follow controller removals")

env.reset_log()
Roles.receive_assignment_updates{ Env.assignment("zed", { 5 }) }
check(#env.events == 0 and #env.printed == 0, "changes for players not on this map raise nothing")

-- Changes to the roles themselves
env.reset_log()
Roles.receive_role_updates{
    { id = 6, name = "Regular", permissions = { "exp_scenario.command.jail" }, meta = { id = 0, order = 3 } },
}
check(R("Regular"):has_permission("exp_scenario.command.jail"), "a role permission change applies")
check(#env.events == 2, "a role change raises for every connected player")
check(#env.events[1].data.assigned == 0, "role change events are empty")

env.reset_log()
Roles.receive_role_updates{ { id = 6, name = "Regular", permissions = {}, meta = { id = 0, order = 3 }, is_deleted = true } }
check(Roles.get_role(6) == nil, "a deleted role is removed")

env.reset_log()
Roles.receive_role_updates{
    { id = 1, name = "Player", permissions = {}, meta = { id = 0, order = 5 } },
    { id = 8, name = "Guest", permissions = {}, meta = { id = 0, order = 7 }, is_default = true },
}
check(Roles.get_default_role() == R("Guest"), "the default role follows is_default")
check(eq(env.names(Roles.get_player_roles(carol)), { "Guest" }), "players pick up the new default role")

-- Initialise is authoritative for pending roles
R("Moderator"):assign(carol)
R("Jail"):assign(carol, { silent = true, local_only = true })
check(eq(sd.pending.carol, { 5 }), "the role is pending before initialise")
env.reset_log()
env.initialise{ Env.assignment("alice", { 5 }) }
check(sd.pending.carol == nil, "initialise clears pending roles")
check(not R("Moderator"):has_player(carol), "an unconfirmed role is given up")
check(eq(sd.local_players.carol, { 7 }), "local only roles are kept")
check(#env.sent == 0, "initialise sends nothing")

-- Emit updates gate and load
Roles.set_emit_events(false)
env.reset_log()
R("Regular"):assign(alice)
check(#env.sent == 0, "nothing is sent while emit is disabled")
Roles.on_load()
check(R("Moderator"):is_higher_than(R("Regular")), "roles are usable after load")

-- Triggers on join
admin_state.alice = nil
Roles.on_player_joined_game{ player_index = 1 }
check(admin_state.alice ~= nil, "triggers run when a player joins")

return Env.results_json(env)
