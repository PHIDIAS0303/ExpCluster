--- Listing and printing to the players who hold a role
local Env = ...
local env = Env.new()
local check, eq, R = env.check, env.eq, env.R
local Roles = env.Roles

local alice = env.add_player("alice", 1)
env.add_player("bob", 2)
env.add_player("dave", 4, false) -- offline
env.initialise{
    Env.assignment("alice", { 5 }),
    Env.assignment("bob", { 6 }),
    Env.assignment("dave", { 5 }),
    Env.assignment("zed", { 5 }), -- has never joined this map
}
Roles.set_emit_events(true)

local mod = R("Moderator")
check(eq(env.sorted(mod:get_player_names()), { "alice", "dave", "zed" }),
    "player names include players not on this map")
check(eq(env.sorted(env.names(mod:get_players())), { "alice", "dave" }),
    "players are limited to this map")
check(eq(env.names(mod:get_players(true)), { "alice" }), "players can be filtered by connected state")
check(eq(env.names(mod:get_players(false)), { "dave" }), "players can be filtered to offline")

-- A player holding the role in both the synced and the local list counts once
R("Regular"):assign(alice, { silent = true, local_only = true })
Roles.receive_assignment_updates{ Env.assignment("alice", { 5, 6 }) }
local sd = Roles._script_data()
check(sd.local_players.alice ~= nil and sd.synced_players.alice ~= nil, "the role is held in both lists")
check(eq(env.sorted(R("Regular"):get_player_names()), { "alice", "bob" }),
    "a player in both lists is counted once")

env.reset_log()
check(mod:print("hello") == 1, "print returns the number of players reached")
check(#env.printed == 1 and env.printed[1].to == "alice", "print reaches only online holders")

env.reset_log()
for _, role in ipairs(Roles.get_higher_roles(R("Regular"))) do
    role:print("hello")
end
local got = {}
for _, entry in ipairs(env.printed) do got[#got + 1] = entry.to end
-- alice holds two of the roles, so like the legacy system the message can repeat
check(eq(env.sorted(got), { "alice", "alice", "bob" }), "printing to the higher roles reaches their online holders")

return Env.results_json(env)
