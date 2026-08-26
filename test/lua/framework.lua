--[[-- Test framework for plugin module tests
A suite is a collection of named tests. Test files declare them with
`Suite.test(name, function(env) ... end)`, naming each test after the function
or method it covers. Every test function receives a fresh environment: the
stubs extended by the function the suite was created with, so tests are
independent and can not leak state into each other.
]]

local source = assert(debug.getinfo(1, "S")).source
local shared_root = assert(source:match("^@(.*)/framework%.lua$"))
local Stubs = assert(loadfile(shared_root .. "/stubs.lua"))()

local Framework = {}

--- Turn a value into a string for failure messages
local function repr(value, depth)
    if type(value) ~= "table" then return tostring(value) end
    if depth > 3 then return "{...}" end

    local parts = {}
    for key, entry in pairs(value) do
        parts[#parts + 1] = tostring(key) .. " = " .. repr(entry, depth + 1)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

--- Create a suite of tests, one is made per test file
--- @param extend_env fun(env: table): table Extends the stubs given to each test
function Framework.suite(extend_env)
    --- @class Suite
    local Suite = {
        tests = {},   -- { name, fn } in declaration order
        results = {}, -- { name, ok, detail? } accumulated across tests
    }

    local current_test --- @type string?

    --- Declare a named test, its function receives a fresh environment
    --- @param name string
    --- @param fn fun(env: table)
    function Suite.test(name, fn)
        Suite.tests[#Suite.tests + 1] = { name = name, fn = fn }
    end

    --- Record a passing check within the current test
    --- @param name string
    function Suite.pass(name)
        Suite.results[#Suite.results + 1] = {
            name = current_test and (current_test .. ": " .. name) or name,
            ok = true,
        }
    end

    --- Record a failing check within the current test
    --- @param name string
    --- @param detail string?
    function Suite.fail(name, detail)
        Suite.results[#Suite.results + 1] = {
            name = current_test and (current_test .. ": " .. name) or name,
            ok = false,
            detail = detail,
        }
    end

    --- Check a condition
    --- @param ok any Truthy when the check passed
    --- @param name string
    --- @param detail string?
    function Suite.check(ok, name, detail)
        if ok then
            Suite.pass(name)
        else
            Suite.fail(name, detail)
        end
    end

    --- Recursive table equality, keys checked from both sides
    local function deep_equal(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        for key, value in pairs(a) do
            if not deep_equal(value, b[key]) then return false end
        end
        for key in pairs(b) do
            if a[key] == nil then return false end
        end
        return true
    end

    --- Check two values are equal, comparing tables recursively
    function Suite.eq(a, b, name)
        Suite.check(deep_equal(a, b), name, ("%s ~= %s"):format(repr(a, 1), repr(b, 1)))
    end

    --- Check a table has no entries
    function Suite.empty(value, name)
        Suite.check(next(value) == nil, name, repr(value, 1))
    end

    --- Check a function raises an error containing the message
    --- @param fn fun()
    --- @param message string
    --- @param name string
    function Suite.throws(fn, message, name)
        local ok, err = pcall(fn)
        if ok then
            Suite.fail(name, "did not error")
        elseif not tostring(err):find(message, 1, true) then
            Suite.fail(name, ("%s does not contain %s"):format(tostring(err), message))
        else
            Suite.pass(name)
        end
    end

    --- Names of an array of values with a name property, such as roles,
    --- players, forces, or events
    --- @param values { name: string }[]
    --- @return string[]
    function Suite.names(values)
        local rtn = {}
        for index, value in ipairs(values) do
            rtn[index] = value.name
        end
        return rtn
    end

    --- Sorted copy of an array of strings
    function Suite.sorted(list)
        local rtn = {}
        for index, value in ipairs(list) do rtn[index] = value end
        table.sort(rtn)
        return rtn
    end

    --- Run every declared test, each against a fresh environment, and return
    --- the results as JSON for the javascript side
    function Suite.run()
        for _, test in ipairs(Suite.tests) do
            current_test = test.name
            local ok, err = pcall(function()
                test.fn(extend_env(Stubs.new()))
            end)
            if not ok then
                Suite.fail("did not error", tostring(err))
            end
        end
        current_test = nil

        local function escape(value)
            return (value:gsub('[%c"\\]', function(c)
                return string.format("\\u%04x", c:byte())
            end))
        end

        local parts = {}
        for index, result in ipairs(Suite.results) do
            local detail = result.detail and string.format(',"detail":"%s"', escape(result.detail)) or ""
            parts[index] = string.format('{"name":"%s","ok":%s%s}', escape(result.name), tostring(result.ok), detail)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    return Suite
end

return Framework
