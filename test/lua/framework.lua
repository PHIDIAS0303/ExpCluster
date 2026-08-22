--[[-- Test framework for plugin module tests
Test files declare named tests with `Test.test(name, function(env) ... end)`.
The runner creates a fresh environment for every test, so tests are
independent and can not leak state into each other.
]]

local Framework = {}

--- Create a test registry, one is made per test file
function Framework.new()
    --- @class Test
    local Test = {
        tests = {},   -- { name, fn } in declaration order
        results = {}, -- { name, ok, detail? } accumulated across tests
    }

    local current_test --- @type string?

    --- Declare a named test, its function receives a fresh environment
    --- @param name string
    --- @param fn fun(env: table)
    function Test.test(name, fn)
        Test.tests[#Test.tests + 1] = { name = name, fn = fn }
    end

    --- Record one check within the current test
    --- @param ok any Truthy when the check passed
    --- @param name string
    --- @param detail string?
    function Test.check(ok, name, detail)
        Test.results[#Test.results + 1] = {
            name = current_test and (current_test .. ": " .. name) or name,
            ok = not not ok,
            detail = detail,
        }
    end

    --- Shallow array equality
    function Test.eq(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        if #a ~= #b then return false end
        for i = 1, #a do
            if a[i] ~= b[i] then return false end
        end
        return true
    end

    --- Recursive table equality, keys checked from both sides
    function Test.deep_eq(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        for key, value in pairs(a) do
            if not Test.deep_eq(value, b[key]) then return false end
        end
        for key in pairs(b) do
            if a[key] == nil then return false end
        end
        return true
    end

    --- Names of an array of roles
    function Test.names(roles)
        local rtn = {}
        for index, role in ipairs(roles) do
            rtn[index] = role.name
        end
        return rtn
    end

    --- Sorted copy of an array of strings
    function Test.sorted(list)
        local rtn = {}
        for index, value in ipairs(list) do rtn[index] = value end
        table.sort(rtn)
        return rtn
    end

    --- Run every declared test against a fresh environment
    --- @param make_env fun(): table
    function Test.run(make_env)
        for _, test in ipairs(Test.tests) do
            current_test = test.name
            local ok, err = pcall(test.fn, make_env())
            if not ok then
                Test.check(false, "did not error", tostring(err))
            end
        end
        current_test = nil
    end

    --- Encode the results as JSON for the javascript side
    function Test.results_json()
        local function escape(value)
            return (value:gsub('[%c"\\]', function(c)
                return string.format("\\u%04x", c:byte())
            end))
        end

        local parts = {}
        for index, result in ipairs(Test.results) do
            local detail = result.detail and string.format(',"detail":"%s"', escape(result.detail)) or ""
            parts[index] = string.format('{"name":"%s","ok":%s%s}', escape(result.name), tostring(result.ok), detail)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    return Test
end

return Framework
