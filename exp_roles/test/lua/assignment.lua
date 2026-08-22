--- Assignment through role methods, confirmation, and rejection
local Env = ...
local Test = Env.Test
local test, check, eq = Test.test, Test.check, Test.eq

--- alice is a moderator and bob a regular, with changes sent to the controller
local function setup(env)
    local players = {
        alice = env.add_player("alice", 1),
        bob = env.add_player("bob", 2),
    }
    env.initialise{
        Env.assignment("alice", { 5 }),
        Env.assignment("bob", { 6 }),
    }
    env.Roles.set_emit_events(true)
    env.reset_log()
    return players
end

test("assign applies locally and is sent to the controller", function(env)
    local players = setup(env)
    env.R("Moderator"):assign(players.bob, { by_player_name = "alice" })
    check(#env.sent == 1 and env.sent[1].channel == "exp_roles:assignment_update", "the assignment is sent")
    check(eq(env.sent[1].data.assign, { 5 }) and env.sent[1].data.name == "bob", "the payload names the role and player")
    check(env.R("Moderator"):has_player(players.bob), "the role applies before confirmation")
    check(#env.events == 1 and eq(env.events[1].data.assigned, { 5 }), "the event carries the assigned role id")
    check(env.events[1].data.by_player_index == 1, "the event carries who made the change")
    check(#env.printed == 1 and env.printed[1][1] == "exp-roles.game-message-assign", "the change is announced")
    check(#env.sounds == 1 and env.sounds[1] == "bob:utility/achievement_unlocked", "the assign sound plays")

    local sd = env.Roles._script_data()
    check(eq(sd.local_players.bob, { 5 }) and eq(sd.pending.bob, { 5 }), "the role is held locally and pending")

    env.reset_log()
    env.R("Moderator"):assign(players.bob)
    check(#env.sent == 0 and #env.events == 0, "assigning a held role is a no-op")
end)

test("a confirmation releases the local hold", function(env)
    local players = setup(env)
    env.R("Moderator"):assign(players.bob)
    env.reset_log()
    env.Roles.receive_assignment_updates{ Env.assignment("bob", { 6, 5 }) }
    check(#env.events == 0 and #env.printed == 0, "a confirmation raises nothing")

    local sd = env.Roles._script_data()
    check(sd.local_players.bob == nil and sd.pending.bob == nil, "the role is no longer held locally")
    check(env.R("Moderator"):has_player(players.bob), "the role is still held after confirmation")
end)

test("unassign a synced role", function(env)
    local players = setup(env)
    env.R("Regular"):unassign(players.bob, { by_player_name = "alice", silent = true })
    check(#env.sent == 1 and eq(env.sent[1].data.unassign, { 6 }), "the unassignment is sent")
    check(not env.R("Regular"):has_player(players.bob), "the role is removed locally")
    check(#env.events == 1 and eq(env.events[1].data.unassigned, { 6 }), "the event carries the unassigned role id")
    check(#env.printed == 0, "silent suppresses the announcement")
    check(#env.sounds == 1 and env.sounds[1] == "bob:utility/game_lost", "the unassign sound plays")
end)

test("a rejection rolls the assignment back", function(env)
    local players = setup(env)
    env.R("Jail"):assign(players.alice)
    check(env.R("Jail"):has_player(players.alice), "the role applies before rejection")

    env.reset_log()
    env.Roles.reject_assignment{ name = "alice", role_ids = { 7 } }
    check(not env.R("Jail"):has_player(players.alice), "the rejected role is rolled back")
    check(#env.sent == 0, "the rollback is not sent to the controller")
    check(#env.events == 1 and eq(env.events[1].data.unassigned, { 7 }), "the rollback raises the event")

    local sd = env.Roles._script_data()
    check(sd.local_players.alice == nil and sd.pending.alice == nil, "the rollback clears the local state")
end)

test("local only roles never reach the controller", function(env)
    local players = setup(env)
    env.R("Regular"):assign(players.alice, { silent = true, local_only = true })
    check(#env.sent == 0, "a local only role is not sent")
    check(env.R("Regular"):has_player(players.alice), "a local only role applies")

    local sd = env.Roles._script_data()
    check(sd.pending.alice == nil and eq(sd.local_players.alice, { 6 }), "a local only role is not pending")

    env.Roles.receive_assignment_updates{ Env.assignment("alice", { 5 }) }
    check(env.R("Regular"):has_player(players.alice), "a local only role survives controller updates")

    env.reset_log()
    env.R("Regular"):unassign(players.alice, { local_only = true })
    check(not env.R("Regular"):has_player(players.alice) and #env.sent == 0, "removed without sync")
end)

test("jail suppresses every other role", function(env)
    local players = setup(env)
    env.R("Jail"):assign(players.alice, { by_player_name = "<server>", silent = true })
    check(eq(Test.names(env.Roles.get_player_roles(players.alice)), { "Jail" }), "only the jail role applies")
    check(env.R("Moderator"):has_player(players.alice), "a suppressed role is still held")
    check(not env.Roles.player_has_permission(players.alice, "exp_scenario.command.kill"), "permissions are lost")
    check(not env.Roles.player_has_permission(players.alice, "exp_scenario.gui.readme"), "the default role is lost")
    check(not env.Roles.player_outranks(players.alice, players.bob), "a jailed player no longer outranks")
    check(eq(env.events[1].data.assigned, { 7 }) and #env.events[1].data.unassigned == 0,
        "the event lists only the jail role")

    env.reset_log()
    env.R("Jail"):unassign(players.alice, { by_player_name = "<server>", silent = true })
    check(eq(Test.sorted(Test.names(env.Roles.get_player_roles(players.alice))), { "Moderator", "Player" }),
        "unjail restores the roles")
    check(#env.events[1].data.assigned == 0 and eq(env.events[1].data.unassigned, { 7 }),
        "the unjail event lists only the jail role")
end)

test("the server can not be assigned roles", function(env)
    setup(env)
    env.R("Moderator"):assign(env.server)
    check(#env.sent == 0 and #env.events == 0, "assigning to the server is a no-op")
end)

return Env.finish()
