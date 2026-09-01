--- Tests for the role lookup functions of module/control.lua
local Suite = ... --- @type Suite<ExpRoles.TestEnv> The suite this file adds its tests to, see test/lua/framework.lua
local test, check, eq = Suite.test, Suite.check, Suite.eq

test("get_role() returns the role with the given clusterio id", function(env)
    env.initialise{}
    check(env.Roles.get_role(env.R("Regular").id) == env.R("Regular"), "the role is found by id")
    eq(env.Roles.get_role(9), nil, "deleted roles are not known")
end)

test("get_role_by_name() searches the roles", function(env)
    env.initialise{}
    check(env.Roles.get_role_by_name("Moderator") == env.R("Moderator"), "the role is found by name")
    eq(env.Roles.get_role_by_name("Gone"), nil, "deleted roles are not known")
end)

test("get_roles() returns every role", function(env)
    env.initialise{}
    eq(Suite.sorted(Suite.names(env.Roles.get_roles())),
        { "Cluster Admin", "Jail", "Moderator", "Player", "Regular" },
        "every role is returned with deleted roles skipped")
end)

test("get_ordered_roles() returns the most privileged first", function(env)
    env.initialise{}
    eq(Suite.names(env.Roles.get_ordered_roles()), { "Cluster Admin", "Moderator", "Regular", "Jail", "Player" },
        "roles follow their order")
end)

test("sort_roles() orders most privileged first and breaks ties on the id", function(env)
    env.initialise{}
    local sorted = env.Roles.sort_roles{ env.R("Player"), env.R("Cluster Admin"), env.R("Regular") }
    eq(Suite.names(sorted), { "Cluster Admin", "Regular", "Player" }, "the list is sorted in place")

    -- A role with the same order as Regular but a higher id sorts after it
    env.Roles.receive_role_updates{
        { id = 10, name = "Twin", permissions = {}, meta = { id = 0, order = env.R("Regular").order } },
    }
    local tied = env.Roles.sort_roles{ env.R("Twin"), env.R("Regular") }
    eq(Suite.names(tied), { "Regular", "Twin" }, "order ties break on the id")
end)

test("get_default_role() follows is_default", function(env)
    env.initialise{}
    check(env.Roles.get_default_role() == env.R("Player"), "the default role is known")
end)

test("get_higher_roles() and get_lower_roles() include the role and exclude the default", function(env)
    env.initialise{}
    eq(Suite.sorted(Suite.names(env.Roles.get_higher_roles(env.R("Regular")))),
        { "Cluster Admin", "Moderator", "Regular" }, "higher roles")
    eq(Suite.sorted(Suite.names(env.Roles.get_lower_roles(env.R("Regular")))),
        { "Jail", "Regular" }, "lower roles")
end)

test(".is_higher_than() and .is_lower_than() compare on order", function(env)
    env.initialise{}
    check(env.R("Moderator"):is_higher_than(env.R("Player")), "a lower order is more privileged")
    check(env.R("Player"):is_lower_than(env.R("Moderator")), "is_lower_than is the reverse")
    check(not env.R("Moderator"):is_higher_than(env.R("Moderator")), "a role is not higher than itself")
end)

test("initialise() decodes the role records", function(env)
    env.initialise{}
    eq(env.R("Cluster Admin").short_hand, "SYS", "short hand decoded")
    eq(env.R("Moderator").short_hand, "Moderator", "short hand falls back to the name")
    eq(env.R("Moderator").color, { r = 0, g = 170, b = 0 }, "color decoded")
    check(env.R("Jail").priority == 1 and env.R("Jail").block_auto_assign, "priority and block auto assign decoded")
end)

return Suite.run()
