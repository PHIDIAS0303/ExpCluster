--- Listing and printing to the players who hold a role
local Env = ...
local Test = Env.Test
local test, check, eq = Test.test, Test.check, Test.eq

--- alice and dave are moderators with dave offline, zed has never joined
local function setup(env)
    local players = {
        alice = env.add_player("alice", 1),
        bob = env.add_player("bob", 2),
        dave = env.add_player("dave", 4, false),
    }
    env.initialise{
        Env.assignment("alice", { 5 }),
        Env.assignment("bob", { 6 }),
        Env.assignment("dave", { 5 }),
        Env.assignment("zed", { 5 }),
    }
    env.Roles.set_emit_events(true)
    return players
end

test("player names include players not on this map", function(env)
    setup(env)
    check(eq(Test.sorted(env.R("Moderator"):get_player_names()), { "alice", "dave", "zed" }),
        "every player given the role is listed")
end)

test("players are limited to this map and can be filtered", function(env)
    setup(env)
    local mod = env.R("Moderator")
    check(eq(Test.sorted(Test.names(mod:get_players())), { "alice", "dave" }), "players are limited to this map")
    check(eq(Test.names(mod:get_players(true)), { "alice" }), "filtered to connected players")
    check(eq(Test.names(mod:get_players(false)), { "dave" }), "filtered to offline players")
end)

test("a player holding the role in both lists is counted once", function(env)
    local players = setup(env)
    env.R("Regular"):assign(players.alice, { silent = true, local_only = true })
    env.Roles.receive_assignment_updates{ Env.assignment("alice", { 5, 6 }) }

    local sd = env.Roles._script_data()
    check(sd.local_players.alice ~= nil and sd.synced_players.alice ~= nil, "the role is held in both lists")
    check(eq(Test.sorted(env.R("Regular"):get_player_names()), { "alice", "bob" }), "the player is counted once")
end)

test("print reaches online holders", function(env)
    setup(env)
    env.reset_log()
    check(env.R("Moderator"):print("hello") == 1, "print returns the number of players reached")
    check(#env.printed == 1 and env.printed[1].to == "alice", "only online holders are reached")
end)

test("printing to the higher roles", function(env)
    local players = setup(env)
    env.R("Regular"):assign(players.alice, { silent = true, local_only = true })
    env.reset_log()
    for _, role in ipairs(env.Roles.get_higher_roles(env.R("Regular"))) do
        role:print("hello")
    end

    local got = {}
    for _, entry in ipairs(env.printed) do got[#got + 1] = entry.to end
    -- alice holds two of the roles, so like the legacy system the message can repeat
    check(eq(Test.sorted(got), { "alice", "alice", "bob" }), "the online holders of each role are reached")
end)

test("deep equality helper", function(env)
    check(Test.deep_eq({ a = { 1, 2 }, b = "x" }, { a = { 1, 2 }, b = "x" }), "equal nested tables")
    check(not Test.deep_eq({ a = { 1, 2 } }, { a = { 1, 3 } }), "differing nested values")
    check(not Test.deep_eq({ a = 1 }, { a = 1, b = 2 }), "extra keys on the right")
    check(not Test.deep_eq({ a = 1, b = 2 }, { a = 1 }), "extra keys on the left")
    check(Test.deep_eq(env.Roles._script_data().pending, {}), "works against module state")
end)

return Env.finish()
