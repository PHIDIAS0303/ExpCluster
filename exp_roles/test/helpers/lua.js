"use strict";
const path = require("node:path");
const fs = require("node:fs");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const moduleRoot = path.join(__dirname, "..", "..", "module");
const luaRoot = path.join(__dirname, "..", "lua");

/**
 * Run one lua test file in its own lua state and return its results.
 *
 * The state is created here, on first use by the caller, so every test file
 * gets an independent environment. The file receives the environment helpers
 * from env.lua and must return an array of { name, ok, detail? } results,
 * encoded as JSON.
 *
 * @param {string} name - File in test/lua to run, such as "lookup.lua".
 * @returns {{ name: string, ok: boolean, detail?: string }[]}
 */
function runLuaTests(name) {
	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);

	// Each file is run as a chunk taking one argument and returning one value
	const load = (file, chunkName) => {
		const code = fs.readFileSync(file);
		const status = lauxlib.luaL_loadbuffer(L, code, code.length, to_luastring(`@${chunkName}`));
		if (status !== lua.LUA_OK) {
			throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
		}
	};
	const call = () => {
		if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) {
			throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
		}
	};

	// The environment stubs factorio and loads module/control.lua from disk
	load(path.join(luaRoot, "env.lua"), "test/lua/env.lua");
	lua.lua_pushstring(L, to_luastring(moduleRoot));
	call();

	// The environment stays on the stack and is passed to the test chunk
	load(path.join(luaRoot, name), `test/lua/${name}`);
	lua.lua_insert(L, -2);
	call();

	const json = to_jsstring(lua.lua_tostring(L, -1));
	return JSON.parse(json);
}

/** Report lua results through a tap test object. */
function reportLuaTests(t, name) {
	const results = runLuaTests(name);
	t.ok(results.length > 0, `${name} produced results`);
	for (const result of results) {
		t.ok(result.ok, result.name, result.detail ? { detail: result.detail } : {});
	}
	t.end();
}

module.exports = { runLuaTests, reportLuaTests };
