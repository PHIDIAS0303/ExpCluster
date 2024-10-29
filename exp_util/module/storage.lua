--[[ Util Module - Storage
Provides a method of using storage with the guarantee that keys will not conflict

--- Drop in boiler plate:
-- Below is a drop in boiler plate which ensures your storage access will not conflict with other modules
local storage =
    Storage.register({
        my_table = {},
        my_primitive = 1,
    }, function(tbl)
        storage = tbl
    end)

--- Registering new storage tables:
-- The boiler plate above is not recommend because it is not descriptive in its function
-- Best practice is to list out all variables you are storing in storage and their function
local MyModule = {
    public_data = {}
}

-- The use of root level primitives is discouraged, but if you must use them then
-- they can not be stored directly in locals and instead within a local table
local primitives = {
    my_primitive = 1,
}

local private_data = {}
local my_table = {}
-- You can not store a whole module in storage because not all data types are serialisable
Storage.register({
    MyModule.public_data,
    primitives,
    private_data,
    my_table,
}, function(tbl)
    MyModule.public_data = tbl[1]
    primitives = tbl[2]
    private_data = tbl[3]
    my_table = tbl[4]
end)

--- Registering metatables
-- Metatables are needed to create instances of a class, these used to be restored manually but not script.register_metatable exists
-- However it is possible for name conflicts to occur so it is encouraged to use Storage.register_metatable to avoid this
local my_metatable = Storage.register_metatable("MyMetaTable", {
    __call = function(self) game.print("I got called!") end
})

]]

local Clustorio = require("modules/clusterio/api")
local ExpUtil = require("modules/exp_util/common")

local Storage = {
    --- @package
    registered = {}, --- @type { [string]: { init: table, callback: fun(tbl: table) } } Map of all registered values and their initial values
}

--- Register a new table to be stored in storage, can only be called once per file, can not be called during runtime
--- @param tbl table The initial value for the table you are registering, this should be a local variable
--- @param callback fun(tbl: table) The callback used to replace local references and metatables
--- @return table # The table passed as the first argument
function Storage.register(tbl, callback)
    ExpUtil.assert_not_runtime()
    ExpUtil.assert_argument_type(tbl, "table", 1, "tbl")
    ExpUtil.assert_argument_type(callback, "function", 2, "callback")

    local name = ExpUtil.safe_file_path(2)
    if Storage.registered[name] then
        error("Storage.register can only be called once per file", 2)
    end

    Storage.registered[name] = {
        init = tbl,
        callback = callback,
    }

    return tbl
end

--- Register a metatable which will be automatically restored during on_load
--- @param name string The name of the metatable to register, must be unique within your module
--- @param tbl table The metatable to register
--- @return table # The metatable passed as the second argument
function Storage.register_metatable(name, tbl)
    local module_name = ExpUtil.get_module_name(2)
    script.register_metatable(module_name .. "." .. name, tbl)
    return tbl
end

--- Restore aliases on load, we do not need to initialise data during this event
--- @package
function Storage.on_load()
    --- @type { [string]: table }
    local exp_storage = storage.exp_storage
    if exp_storage == nil then return end
    for name, info in pairs(Storage.registered) do
        if exp_storage[name] ~= nil then
            info.callback(exp_storage[name])
        end
    end
end

--- Event Handler, sets initial values if needed and calls all callbacks
--- @package
function Storage.on_init()
    --- @type { [string]: table }
    local exp_storage = storage.exp_storage
    if exp_storage == nil then
        exp_storage = {}
        storage.exp_storage = exp_storage
    end

    for name, info in pairs(Storage.registered) do
        if exp_storage[name] == nil then
            exp_storage[name] = info.init
        end
        info.callback(exp_storage[name])
    end
end

--- @package
Storage.events = {
    [Clustorio.events.on_server_startup] = Storage.on_init,
}

return Storage
