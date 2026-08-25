--- Tests for listing and printing to the players who hold a role
local Suite = ... --- The suite this file adds its tests to, see test/lua/framework.lua
local test, check, eq = Suite.test, Suite.check, Suite.eq

--- alice and dave are moderators with dave offline, zed has never joined
local function setup(env)
    local players = {
        alice = env.add_player("alice", 1),
        bob = env.add_player("bob", 2),
        dave = env.add_player("dave", 4, false),
    }
    env.initialise{
        env.assignment("alice", { 5 }),
        env.assignment("bob", { 6 }),
        env.assignment("dave", { 5 }),
        env.assignment("zed", { 5 }),
    }
    env.Roles.set_emit_events(true)
    return players
end

test("role:get_player_names includes players not on this map", function(env)
    setup(env)
    eq(Suite.sorted(env.R("Moderator"):get_player_names()), { "alice", "dave", "zed" },
        "every player given the role is listed")
end)

test("role:get_player_names counts a player in both lists once", function(env)
    local players = setup(env)
    env.R("Regular"):assign(players.alice, { silent = true, local_only = true })
    env.Roles.receive_assignment_updates{ env.assignment("alice", { 5, 6 }) }

    local sd = env.Roles._script_data()
    check(sd.local_players.alice ~= nil and sd.synced_players.alice ~= nil, "the role is held in both lists")
    eq(Suite.sorted(env.R("Regular"):get_player_names()), { "alice", "bob" }, "the player is counted once")
end)

test("role:get_players is limited to this map and can be filtered", function(env)
    setup(env)
    local mod = env.R("Moderator")
    eq(Suite.sorted(Suite.names(mod:get_players())), { "alice", "dave" }, "players are limited to this map")
    eq(Suite.names(mod:get_players(true)), { "alice" }, "filtered to connected players")
    eq(Suite.names(mod:get_players(false)), { "dave" }, "filtered to offline players")
end)

test("role:print reaches online holders", function(env)
    setup(env)
    env.reset_log()
    check(env.R("Moderator"):print("hello") == 1, "print returns the number of players reached")
    check(#env.printed == 1 and env.printed[1].to == "alice", "only online holders are reached")
end)

test("role:print over get_higher_roles can repeat", function(env)
    local players = setup(env)
    env.R("Regular"):assign(players.alice, { silent = true, local_only = true })
    env.reset_log()
    for _, role in ipairs(env.Roles.get_higher_roles(env.R("Regular"))) do
        role:print("hello")
    end

    local got = {}
    for _, entry in ipairs(env.printed) do got[#got + 1] = entry.to end
    -- alice holds two of the roles, so like the legacy system the message can repeat
    eq(Suite.sorted(got), { "alice", "alice", "bob" }, "the online holders of each role are reached")
end)

return Suite.run()
