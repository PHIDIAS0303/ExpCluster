--- Tests for the assignment methods of module/control.lua
local Suite = ... --- The suite this file adds its tests to, see test/lua/framework.lua
local test, check, eq, deep_eq = Suite.test, Suite.check, Suite.eq, Suite.deep_eq

--- alice is a moderator and bob a regular, with changes sent to the controller
local function setup(env)
    local players = {
        alice = env.add_player("alice", 1),
        bob = env.add_player("bob", 2),
    }
    env.initialise{
        env.assignment("alice", { 5 }),
        env.assignment("bob", { 6 }),
    }
    env.Roles.set_emit_events(true)
    env.reset_log()
    return players
end

test("role:assign applies locally and is sent to the controller", function(env)
    local players = setup(env)
    env.R("Moderator"):assign(players.bob, { by_player_name = "alice" })
    deep_eq(env.sent, {
        { channel = "exp_roles:assignment_update", data = { name = "bob", assign = { 5 } } },
    }, "the assignment is sent to the controller")
    check(env.R("Moderator"):has_player(players.bob), "the role applies before confirmation")
    deep_eq(env.events, {
        {
            name = env.Roles.events.on_player_roles_changed,
            tick = 1,
            player_index = 2,
            by_player_index = 1,
            assigned = { 5 },
            unassigned = {},
        },
    }, "the event carries the change")
    check(#env.printed == 1 and env.printed[1][1] == "exp-roles.game-message-assign", "the change is announced")
    eq(env.sounds, { "bob:utility/achievement_unlocked" }, "the assign sound plays")

    local sd = env.Roles._script_data()
    eq(sd.local_players.bob, { 5 }, "the role is held locally")
    eq(sd.pending.bob, { 5 }, "the role is pending")

    env.reset_log()
    env.R("Moderator"):assign(players.bob)
    check(#env.sent == 0 and #env.events == 0, "assigning a held role is a no-op")
end)

test("receive_assignment_updates releases the local hold once confirmed", function(env)
    local players = setup(env)
    env.R("Moderator"):assign(players.bob)
    env.reset_log()
    env.Roles.receive_assignment_updates{ env.assignment("bob", { 6, 5 }) }
    check(#env.events == 0 and #env.printed == 0, "a confirmation raises nothing")

    local sd = env.Roles._script_data()
    check(sd.local_players.bob == nil and sd.pending.bob == nil, "the role is no longer held locally")
    check(env.R("Moderator"):has_player(players.bob), "the role is still held after confirmation")
end)

test("role:unassign removes a synced role", function(env)
    local players = setup(env)
    env.R("Regular"):unassign(players.bob, { by_player_name = "alice", silent = true })
    deep_eq(env.sent, {
        { channel = "exp_roles:assignment_update", data = { name = "bob", unassign = { 6 } } },
    }, "the unassignment is sent to the controller")
    check(not env.R("Regular"):has_player(players.bob), "the role is removed locally")
    deep_eq(env.events, {
        {
            name = env.Roles.events.on_player_roles_changed,
            tick = 1,
            player_index = 2,
            by_player_index = 1,
            assigned = {},
            unassigned = { 6 },
        },
    }, "the event carries the change")
    check(#env.printed == 0, "silent suppresses the announcement")
    eq(env.sounds, { "bob:utility/game_lost" }, "the unassign sound plays")
end)

test("reject_assignment rolls the assignment back", function(env)
    local players = setup(env)
    env.R("Jail"):assign(players.alice)
    check(env.R("Jail"):has_player(players.alice), "the role applies before rejection")

    env.reset_log()
    env.Roles.reject_assignment{ name = "alice", role_ids = { 7 } }
    check(not env.R("Jail"):has_player(players.alice), "the rejected role is rolled back")
    check(#env.sent == 0, "the rollback is not sent to the controller")
    deep_eq(env.events, {
        {
            name = env.Roles.events.on_player_roles_changed,
            tick = 1,
            player_index = 1,
            by_player_index = 0,
            assigned = {},
            unassigned = { 7 },
        },
    }, "the rollback raises the event")

    local sd = env.Roles._script_data()
    check(sd.local_players.alice == nil and sd.pending.alice == nil, "the rollback clears the local state")
end)

test("role:assign with local_only never reaches the controller", function(env)
    local players = setup(env)
    env.R("Regular"):assign(players.alice, { silent = true, local_only = true })
    check(#env.sent == 0, "the assignment is not sent")
    check(env.R("Regular"):has_player(players.alice), "the role applies")

    local sd = env.Roles._script_data()
    check(sd.pending.alice == nil, "the role is not pending")
    eq(sd.local_players.alice, { 6 }, "the role is held locally")

    env.Roles.receive_assignment_updates{ env.assignment("alice", { 5 }) }
    check(env.R("Regular"):has_player(players.alice), "the role survives controller updates")

    env.reset_log()
    env.R("Regular"):unassign(players.alice, { local_only = true })
    check(not env.R("Regular"):has_player(players.alice) and #env.sent == 0, "removed without sync")
end)

test("role:assign of a higher priority role suppresses the rest", function(env)
    local players = setup(env)
    env.R("Jail"):assign(players.alice, { by_player_name = "<server>", silent = true })
    eq(Suite.names(env.Roles.get_player_roles(players.alice)), { "Jail" }, "only the jail role applies")
    check(env.R("Moderator"):has_player(players.alice), "a suppressed role is still held")
    check(not env.Roles.player_has_permission(players.alice, "exp_scenario.command.kill"), "permissions are lost")
    check(not env.Roles.player_has_permission(players.alice, "exp_scenario.gui.readme"), "the default role is lost")
    check(not env.Roles.player_outranks(players.alice, players.bob), "a jailed player no longer outranks")
    eq(env.events[1].assigned, { 7 }, "the event lists the jail role")
    check(#env.events[1].unassigned == 0, "the suppressed roles are not listed as unassigned")

    env.reset_log()
    env.R("Jail"):unassign(players.alice, { by_player_name = "<server>", silent = true })
    eq(Suite.sorted(Suite.names(env.Roles.get_player_roles(players.alice))), { "Moderator", "Player" },
        "unjail restores the roles")
    check(#env.events[1].assigned == 0, "the restored roles are not listed as assigned")
    eq(env.events[1].unassigned, { 7 }, "the unjail event lists the jail role")
end)

test("role:assign ignores the server", function(env)
    setup(env)
    env.R("Moderator"):assign(env.server)
    check(#env.sent == 0 and #env.events == 0, "assigning to the server is a no-op")
end)

return Suite.run()
