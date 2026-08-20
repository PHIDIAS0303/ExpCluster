--- Player role and permission checks
local Env = ...
local env = Env.new()
local check, eq, names, R = env.check, env.eq, env.names, env.R
local Roles = env.Roles

local alice = env.add_player("alice", 1)  -- moderator
local bob = env.add_player("bob", 2)      -- regular
local carol = env.add_player("carol", 3)  -- only the default role
env.initialise{
    Env.assignment("alice", { 5 }),
    Env.assignment("bob", { 6 }),
}

check(eq(env.sorted(names(Roles.get_player_roles(alice))), { "Moderator", "Player" }),
    "player roles include the default role")
check(eq(names(Roles.get_player_roles(carol)), { "Player" }), "a player with no roles has the default role")
check(eq(names(Roles.get_player_roles(nil)), { "<server>" }), "nil is the server")
check(eq(names(Roles.get_player_roles(env.server)), { "<server>" }), "a player with index 0 is the server")
check(Roles.get_player_highest_role(alice) == R("Moderator"), "highest role")
check(Roles.get_player_highest_role(carol) == R("Player"), "highest role is the default role when none are held")

check(Roles.player_has_permission(alice, "exp_scenario.command.kill"), "permission through a held role")
check(Roles.player_has_permission(alice, "exp_scenario.gui.readme"), "permission through the default role")
check(not Roles.player_has_permission(bob, "exp_scenario.command.jail"), "permission not granted")
check(Roles.player_has_permission(nil, "anything.at.all"), "the server has every permission")
check(Roles.player_has_permission(env.server, "anything.at.all"), "an index 0 player has every permission")

check(Roles.player_has_any_permission(bob, "exp_scenario.command.jail", "exp_scenario.command.kill"),
    "has any passes when one permission is granted")
check(not Roles.player_has_any_permission(bob, "exp_scenario.command.jail", "exp_scenario.command.assign_role"),
    "has any fails when none are granted")
check(not Roles.player_has_any_permission(bob), "has any with no permissions is false")
check(Roles.player_has_all_permission(alice, "exp_scenario.command.jail", "exp_scenario.command.kill"),
    "has all passes when every permission is granted")
check(not Roles.player_has_all_permission(bob, "exp_scenario.command.jail", "exp_scenario.command.kill"),
    "has all fails when one is missing")
check(Roles.player_has_all_permission(bob), "has all with no permissions is true")
check(Roles.player_has_any_permission(nil, "anything.at.all"), "the server passes has any")

check(R("Moderator"):has_permission("exp_scenario.command.kill"), "role has_permission")
check(not R("Regular"):has_permission("exp_scenario.command.jail"), "role has_permission not granted")
check(R("Cluster Admin"):has_permission("anything.at.all"), "core.admin grants everything")

check(R("Moderator"):has_player(alice), "has_player for a held role")
check(not R("Moderator"):has_player(bob), "has_player for a role not held")
check(R("Player"):has_player(carol), "everyone has the default role")
check(not R("Player"):has_player(nil), "the server does not have the default role")

check(Roles.player_outranks(alice, bob), "a higher role outranks a lower one")
check(not Roles.player_outranks(bob, alice), "a lower role does not outrank a higher one")
check(not Roles.player_outranks(alice, alice), "nobody outranks themselves")
check(Roles.player_outranks(nil, alice), "the server outranks everyone")
check(not Roles.player_outranks(alice, nil), "nobody outranks the server")

return Env.results_json(env)
