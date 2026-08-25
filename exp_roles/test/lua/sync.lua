--- Tests for the sync entry points of module/control.lua
local Suite = ... --- The suite this file adds its tests to, see test/lua/framework.lua
local test, check, eq, deep_eq = Suite.test, Suite.check, Suite.eq, Suite.deep_eq

--- alice is a moderator and carol has only the default role, both connected
local function setup(env)
    local players = {
        alice = env.add_player("alice", 1),
        carol = env.add_player("carol", 3),
    }
    env.admin_state = {}
    env.Roles.define_permission_trigger("exp_scenario.player.admin", function(player, state)
        env.admin_state[player.name] = state
    end)
    env.initialise{
        env.assignment("alice", { 5 }),
        env.assignment("zed", { 5, 6 }), -- has never joined this map
    }
    env.Roles.set_emit_events(true)
    return players
end

test("initialise applies triggers and raises empty events", function(env)
    setup(env)
    deep_eq(env.admin_state, { alice = true, carol = false }, "triggers run for connected players")
    check(#env.events == 2, "the event is raised once per connected player")
    check(#env.events[1].assigned == 0 and #env.events[1].unassigned == 0, "the events are empty")
    check(#env.printed == 0 and #env.sent == 0 and #env.sounds == 0, "initialise is silent and sends nothing")
end)

test("initialise is authoritative for pending roles", function(env)
    local players = setup(env)
    env.R("Moderator"):assign(players.carol)
    env.R("Jail"):assign(players.carol, { silent = true, local_only = true })

    local sd = env.Roles._script_data()
    eq(sd.pending.carol, { 5 }, "the role is pending before initialise")

    env.reset_log()
    env.initialise{ env.assignment("alice", { 5 }) }
    check(sd.pending.carol == nil, "pending roles are cleared")
    check(not env.R("Moderator"):has_player(players.carol), "an unconfirmed role is given up")
    eq(sd.local_players.carol, { 7 }, "local only roles are kept")
    check(#env.sent == 0, "initialise sends nothing")
end)

test("receive_assignment_updates applies controller changes", function(env)
    local players = setup(env)
    env.reset_log()
    env.Roles.receive_assignment_updates{ env.assignment("carol", { 5 }) }
    check(env.R("Moderator"):has_player(players.carol), "the assignment applies")
    deep_eq(env.events, {
        {
            name = env.Roles.events.on_player_roles_changed,
            tick = 1,
            player_index = 3,
            by_player_index = 0,
            assigned = { 5 },
            unassigned = {},
        },
    }, "the event carries the change with no by player")
    check(#env.printed == 1 and env.printed[1][4] == "<server>", "the change is announced by the server")
    check(env.admin_state.carol == true, "triggers follow the assignment")

    env.reset_log()
    env.Roles.receive_assignment_updates{ { name = "carol", role_ids = {}, is_deleted = true } }
    check(not env.R("Moderator"):has_player(players.carol), "a removal applies")
    eq(env.events[1].unassigned, { 5 }, "the removal raises the event")
    check(env.admin_state.carol == false, "triggers follow the removal")
end)

test("receive_assignment_updates for players not on this map raises nothing", function(env)
    setup(env)
    env.reset_log()
    env.Roles.receive_assignment_updates{ env.assignment("zed", { 5 }) }
    check(#env.events == 0 and #env.printed == 0, "no event and no announcement")
end)

test("receive_role_updates applies to the holders", function(env)
    setup(env)
    env.reset_log()
    env.Roles.receive_role_updates{
        { id = 6, name = "Regular", permissions = { "exp_scenario.command.jail" }, meta = { id = 0, order = 3 } },
    }
    check(env.R("Regular"):has_permission("exp_scenario.command.jail"), "the permission change applies")
    check(#env.events == 2, "a role change raises for every connected player")
    check(#env.events[1].assigned == 0, "role change events are empty")

    env.Roles.receive_role_updates{
        { id = 6, name = "Regular", permissions = {}, meta = { id = 0, order = 3 }, is_deleted = true },
    }
    check(env.Roles.get_role(6) == nil, "a deleted role is removed")
end)

test("receive_role_updates moves the default role", function(env)
    local players = setup(env)
    env.Roles.receive_role_updates{
        { id = 1, name = "Player", permissions = {}, meta = { id = 0, order = 5 } },
        { id = 8, name = "Guest", permissions = {}, meta = { id = 0, order = 7 }, is_default = true },
    }
    check(env.Roles.get_default_role() == env.R("Guest"), "the new default role is known")
    eq(Suite.names(env.Roles.get_player_roles(players.carol)), { "Guest" }, "players pick up the new default")
end)

test("set_emit_events gates what is sent", function(env)
    local players = setup(env)
    env.Roles.set_emit_events(false)
    env.reset_log()
    env.R("Regular"):assign(players.alice)
    check(#env.sent == 0, "the assignment is not sent")
    check(env.R("Regular"):has_player(players.alice), "the assignment still applies locally")
end)

test("on_load restores the state after a save and load", function(env)
    local players = setup(env)
    env.R("Jail"):assign(players.carol, { silent = true, local_only = true })
    env.save_load()
    env.Roles.on_load()

    check(env.R("Moderator"):is_higher_than(env.R("Regular")), "role methods survive through the registered metatable")
    check(env.R("Moderator"):has_player(players.alice), "synced roles survive")
    check(env.R("Jail"):has_player(players.carol), "local roles survive")
    check(env.Roles.player_has_permission(players.alice, "exp_scenario.command.kill"), "permission checks still answer")
end)

test("on_player_joined_game runs the triggers", function(env)
    setup(env)
    env.admin_state.alice = nil
    env.Roles.on_player_joined_game{ player_index = 1 }
    check(env.admin_state.alice ~= nil, "triggers run when a player joins")
end)

return Suite.run()
