--- Role lookup, decoding, and comparisons
local Env = ...
local Test = Env.Test
local test, check, eq = Test.test, Test.check, Test.eq

test("roles are ordered most privileged first", function(env)
    env.initialise{}
    check(eq(Test.names(env.Roles.get_ordered_roles()), { "Cluster Admin", "Moderator", "Regular", "Jail", "Player" }),
        "ordered roles follow their order with deleted roles skipped")
    check(#env.Roles.get_roles() == 5, "get_roles returns every role")

    local sorted = env.Roles.sort_roles{ env.R("Player"), env.R("Cluster Admin"), env.R("Regular") }
    check(eq(Test.names(sorted), { "Cluster Admin", "Regular", "Player" }), "sort_roles orders most privileged first")
end)

test("roles are looked up by id", function(env)
    env.initialise{}
    check(env.Roles.get_role(6).name == "Regular", "get_role looks up by clusterio id")
    check(env.Roles.get_role_by_name("Moderator").id == 5, "get_role_by_name searches the roles")
    check(env.Roles.get_role(env.R("Jail").id) == env.R("Jail"), "lookups return the same object")
    check(env.Roles.get_role(9) == nil and env.Roles.get_role_by_name("Gone") == nil, "deleted roles are not known")
    check(env.Roles.get_default_role() == env.R("Player"), "the default role comes from is_default")
end)

test("role records are decoded", function(env)
    env.initialise{}
    check(env.R("Cluster Admin").short_hand == "SYS", "short hand decoded")
    check(env.R("Moderator").short_hand == "Moderator", "short hand falls back to the name")
    check(env.R("Moderator").color.g == 170, "color decoded")
    check(env.R("Jail").priority == 1 and env.R("Jail").block_auto_assign, "priority and block auto assign decoded")
end)

test("roles compare on their order", function(env)
    env.initialise{}
    check(env.R("Moderator"):is_higher_than(env.R("Player")), "a lower order is more privileged")
    check(env.R("Player"):is_lower_than(env.R("Moderator")), "is_lower_than is the reverse")
    check(not env.R("Moderator"):is_higher_than(env.R("Moderator")), "a role is not higher than itself")
end)

test("higher and lower roles", function(env)
    env.initialise{}
    check(eq(Test.sorted(Test.names(env.Roles.get_higher_roles(env.R("Regular")))), { "Cluster Admin", "Moderator", "Regular" }),
        "higher roles include the role itself and exclude the default role")
    check(eq(Test.sorted(Test.names(env.Roles.get_lower_roles(env.R("Regular")))), { "Jail", "Regular" }),
        "lower roles include the role itself and exclude the default role")
end)

return Env.finish()
