--- Role lookup, decoding, and comparisons
local Env = ...
local env = Env.new()
local check, eq, names, R = env.check, env.eq, env.names, env.R
local Roles = env.Roles

env.initialise{}

check(eq(names(Roles.get_ordered_roles()), { "Cluster Admin", "Moderator", "Regular", "Jail", "Player" }),
    "ordered roles are most privileged first with deleted roles skipped")
check(#Roles.get_roles() == 5, "get_roles returns every role")
check(Roles.get_role(6).name == "Regular", "get_role looks up by clusterio id")
check(Roles.get_role_by_name("Moderator").id == 5, "get_role_by_name searches the roles")
check(Roles.get_role(R("Jail").id) == R("Jail"), "lookups return the same object")
check(Roles.get_role(9) == nil and Roles.get_role_by_name("Gone") == nil, "deleted roles are not known")
check(Roles.get_default_role() == R("Player"), "the default role comes from is_default")

check(R("Moderator").short_hand == "Mod" or R("Moderator").short_hand == "Moderator",
    "short hand falls back to the name")
check(R("Cluster Admin").short_hand == "SYS", "short hand decoded")
check(R("Moderator").color.g == 170, "color decoded")
check(R("Jail").priority == 1 and R("Jail").block_auto_assign, "priority and block auto assign decoded")

check(R("Moderator"):is_higher_than(R("Player")), "roles compare on their order")
check(R("Player"):is_lower_than(R("Moderator")), "is_lower_than is the reverse")
check(not R("Moderator"):is_higher_than(R("Moderator")), "a role is not higher than itself")

check(eq(env.sorted(names(Roles.get_higher_roles(R("Regular")))), { "Cluster Admin", "Moderator", "Regular" }),
    "higher roles include the role itself and exclude the default role")
check(eq(env.sorted(names(Roles.get_lower_roles(R("Regular")))), { "Jail", "Regular" }),
    "lower roles include the role itself and exclude the default role")

local sorted = Roles.sort_roles{ R("Player"), R("Cluster Admin"), R("Regular") }
check(eq(names(sorted), { "Cluster Admin", "Regular", "Player" }), "sort_roles orders most privileged first")

return Env.results_json(env)
