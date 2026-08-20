"use strict";
const t = require("tap");
const { reportLuaTests } = require("./helpers/lua");

// Each file runs in its own lua state with a fresh copy of the module
for (const file of ["lookup.lua", "players.lua", "assignment.lua", "sync.lua", "holders.lua"]) {
	t.test(file, subtest => reportLuaTests(subtest, file));
}
