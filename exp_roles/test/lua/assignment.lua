--- Assignment through role methods, confirmation, and rejection
local Env = ...
local env = Env.new()
local check, eq, R = env.check, env.eq, env.R
local Roles = env.Roles
local sd = Roles._script_data()

local alice = env.add_player("alice", 1)
local bob = env.add_player("bob", 2)
env.initialise{
    Env.assignment("alice", { 5 }),
    Env.assignment("bob", { 6 }),
}
Roles.set_emit_events(true)
env.reset_log()

-- Assign with sync
R("Moderator"):assign(bob, { by_player_name = "alice" })
check(#env.sent == 1 and env.sent[1].channel == "exp_roles:assignment_update", "assignment is sent to the controller")
check(eq(env.sent[1].data.assign, { 5 }) and env.sent[1].data.name == "bob", "assignment payload")
check(R("Moderator"):has_player(bob), "the role applies before confirmation")
check(#env.events == 1 and eq(env.events[1].data.assigned, { 5 }), "event carries the assigned role id")
check(env.events[1].data.by_player_index == 1, "event carries who made the change")
check(#env.printed == 1 and env.printed[1][1] == "exp-roles.game-message-assign", "the change is announced")
check(#env.sounds == 1 and env.sounds[1] == "bob:utility/achievement_unlocked", "assign sound")
check(eq(sd.local_players.bob, { 5 }) and eq(sd.pending.bob, { 5 }), "held locally and pending")

env.reset_log()
R("Moderator"):assign(bob)
check(#env.sent == 0 and #env.events == 0, "assigning a held role is a no-op")

-- Controller confirms
env.reset_log()
Roles.receive_assignment_updates{ Env.assignment("bob", { 6, 5 }) }
check(#env.events == 0 and #env.printed == 0, "a confirmation raises nothing")
check(sd.local_players.bob == nil and sd.pending.bob == nil, "a confirmed role is no longer held locally")
check(R("Moderator"):has_player(bob), "the role is still held after confirmation")

-- Unassign a synced role
env.reset_log()
R("Moderator"):unassign(bob, { by_player_name = "alice", silent = true })
check(#env.sent == 1 and eq(env.sent[1].data.unassign, { 5 }), "unassignment is sent to the controller")
check(not R("Moderator"):has_player(bob), "the role is removed locally")
check(#env.events == 1 and eq(env.events[1].data.unassigned, { 5 }), "event carries the unassigned role id")
check(#env.printed == 0, "silent suppresses the announcement")
check(#env.sounds == 1 and env.sounds[1] == "bob:utility/game_lost", "unassign sound")
Roles.receive_assignment_updates{ Env.assignment("bob", { 6 }) }

-- Rejection rolls back
env.reset_log()
R("Jail"):assign(alice)
check(R("Jail"):has_player(alice), "the role applies before rejection")
env.reset_log()
Roles.reject_assignment{ name = "alice", role_ids = { 7 } }
check(not R("Jail"):has_player(alice), "a rejected role is rolled back")
check(#env.sent == 0, "the rollback is not sent to the controller")
check(#env.events == 1 and eq(env.events[1].data.unassigned, { 7 }), "the rollback raises the event")
check(sd.local_players.alice == nil and sd.pending.alice == nil, "the rollback clears the local state")

-- Local only roles
env.reset_log()
R("Regular"):assign(alice, { silent = true, local_only = true })
check(#env.sent == 0, "a local only role is not sent")
check(R("Regular"):has_player(alice), "a local only role applies")
check(sd.pending.alice == nil and eq(sd.local_players.alice, { 6 }), "a local only role is not pending")
Roles.receive_assignment_updates{ Env.assignment("alice", { 5 }) }
check(R("Regular"):has_player(alice), "a local only role survives controller updates")
env.reset_log()
R("Regular"):unassign(alice, { local_only = true })
check(not R("Regular"):has_player(alice) and #env.sent == 0, "a local only role is removed without sync")

-- Jail priority
env.reset_log()
R("Jail"):assign(alice, { by_player_name = "<server>", silent = true })
check(eq(env.names(Roles.get_player_roles(alice)), { "Jail" }), "jail suppresses every other role")
check(R("Moderator"):has_player(alice), "a suppressed role is still held")
check(not Roles.player_has_permission(alice, "exp_scenario.command.kill"), "a jailed player loses permissions")
check(not Roles.player_has_permission(alice, "exp_scenario.gui.readme"), "a jailed player loses the default role")
check(not Roles.player_outranks(alice, bob), "a jailed player no longer outranks")
check(eq(env.events[1].data.assigned, { 7 }) and #env.events[1].data.unassigned == 0,
    "the jail event lists only the jail role")
env.reset_log()
R("Jail"):unassign(alice, { by_player_name = "<server>", silent = true })
check(eq(env.sorted(env.names(Roles.get_player_roles(alice))), { "Moderator", "Player" }), "unjail restores the roles")
check(#env.events[1].data.assigned == 0 and eq(env.events[1].data.unassigned, { 7 }),
    "the unjail event lists only the jail role")

-- The server can not be assigned roles
env.reset_log()
R("Moderator"):assign(env.server)
check(#env.sent == 0 and #env.events == 0, "assigning to the server is a no-op")

return Env.results_json(env)
