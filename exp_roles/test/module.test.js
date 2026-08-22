"use strict";
const path = require("node:path");
const t = require("tap");
const { reportLuaTests } = require("../../test/lua/runner");

const envFile = path.join(__dirname, "lua", "env.lua");

// Each file runs in its own lua state, and each test in a fresh environment
for (const file of ["lookup.lua", "players.lua", "assignment.lua", "sync.lua", "holders.lua"]) {
	t.test(file, subtest => reportLuaTests(subtest, envFile, path.join(__dirname, "lua", file)));
}
