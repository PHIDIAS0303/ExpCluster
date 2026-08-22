--- Initialise semantics and updates from the controller
local Env = ...
local Test = Env.Test
local test, check, eq = Test.test, Test.check, Test.eq

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
        Env.assignment("alice", { 5 }),
        Env.assignment("zed", { 5, 6 }), -- has never joined this map
    }
    env.Roles.set_emit_events(true)
    return players
end

test("initialise applies triggers and raises empty events", function(env)
    setup(env)
    check(env.admin_state.alice == true and env.admin_state.carol == false,
        "triggers run for connected players")
    check(#env.events == 2, "the event is raised once per connected player")
    check(#env.events[1].data.assigned == 0 and #env.events[1].data.unassigned == 0, "the events are empty")
    check(#env.printed == 0 and #env.sent == 0 and #env.sounds == 0, "initialise is silent and sends nothing")
end)

test("controller assignments apply and are announced", function(env)
    local players = setup(env)
    env.reset_log()
    env.Roles.receive_assignment_updates{ Env.assignment("carol", { 5 }) }
    check(env.R("Moderator"):has_player(players.carol), "the assignment applies")
    check(#env.events == 1 and eq(env.events[1].data.assigned, { 5 }), "the event is raised")
    check(env.events[1].data.by_player_index == 0, "controller changes have no by player")
    check(#env.printed == 1 and env.printed[1][4] == "<server>", "the change is announced by the server")
    check(env.admin_state.carol == true, "triggers follow the assignment")

    env.reset_log()
    env.Roles.receive_assignment_updates{ { name = "carol", role_ids = {}, is_deleted = true } }
    check(not env.R("Moderator"):has_player(players.carol), "a removal applies")
    check(#env.events == 1 and eq(env.events[1].data.unassigned, { 5 }), "the removal raises the event")
    check(env.admin_state.carol == false, "triggers follow the removal")
end)

test("changes for players not on this map raise nothing", function(env)
    setup(env)
    env.reset_log()
    env.Roles.receive_assignment_updates{ Env.assignment("zed", { 5 }) }
    check(#env.events == 0 and #env.printed == 0, "no event and no announcement")
end)

test("role updates apply to their holders", function(env)
    setup(env)
    env.reset_log()
    env.Roles.receive_role_updates{
        { id = 6, name = "Regular", permissions = { "exp_scenario.command.jail" }, meta = { id = 0, order = 3 } },
    }
    check(env.R("Regular"):has_permission("exp_scenario.command.jail"), "the permission change applies")
    check(#env.events == 2, "a role change raises for every connected player")
    check(#env.events[1].data.assigned == 0, "role change events are empty")

    env.Roles.receive_role_updates{
        { id = 6, name = "Regular", permissions = {}, meta = { id = 0, order = 3 }, is_deleted = true },
    }
    check(env.Roles.get_role(6) == nil, "a deleted role is removed")
end)

test("the default role follows is_default", function(env)
    local players = setup(env)
    env.Roles.receive_role_updates{
        { id = 1, name = "Player", permissions = {}, meta = { id = 0, order = 5 } },
        { id = 8, name = "Guest", permissions = {}, meta = { id = 0, order = 7 }, is_default = true },
    }
    check(env.Roles.get_default_role() == env.R("Guest"), "the new default role is known")
    check(eq(Test.names(env.Roles.get_player_roles(players.carol)), { "Guest" }), "players pick up the new default")
end)

test("initialise is authoritative for pending roles", function(env)
    local players = setup(env)
    env.R("Moderator"):assign(players.carol)
    env.R("Jail"):assign(players.carol, { silent = true, local_only = true })

    local sd = env.Roles._script_data()
    check(eq(sd.pending.carol, { 5 }), "the role is pending before initialise")

    env.reset_log()
    env.initialise{ Env.assignment("alice", { 5 }) }
    check(sd.pending.carol == nil, "pending roles are cleared")
    check(not env.R("Moderator"):has_player(players.carol), "an unconfirmed role is given up")
    check(eq(sd.local_players.carol, { 7 }), "local only roles are kept")
    check(#env.sent == 0, "initialise sends nothing")
end)

test("nothing is sent while emit is disabled", function(env)
    local players = setup(env)
    env.Roles.set_emit_events(false)
    env.reset_log()
    env.R("Regular"):assign(players.alice)
    check(#env.sent == 0, "the assignment is not sent")
    check(env.R("Regular"):has_player(players.alice), "the assignment still applies locally")
end)

test("roles are usable after load and triggers run on join", function(env)
    setup(env)
    env.Roles.on_load()
    check(env.R("Moderator"):is_higher_than(env.R("Regular")), "roles are usable after load")

    env.admin_state.alice = nil
    env.Roles.on_player_joined_game{ player_index = 1 }
    check(env.admin_state.alice ~= nil, "triggers run when a player joins")
end)

return Env.finish()
