"use strict";
const t = require("tap");
const lib = require("@clusterio/lib");
const { seedRoles, flattenSeedPermissions } = require("../dist/node/seed");

// Importing this defines the exp_scenario permissions the seed grants
require("@expcluster/scenario/dist/node/permissions");

t.test("seedRoles grant only defined permissions", subtest => {
	for (const role of seedRoles) {
		for (const permission of flattenSeedPermissions(role)) {
			subtest.ok(lib.permissions.has(permission), `${role.name} grants defined permission ${permission}`);
		}
	}
	subtest.end();
});

t.test("flattenSeedPermissions() carries parents into their children", subtest => {
	const byName = new Map(seedRoles.map(role => [role.name, role]));
	for (const role of seedRoles) {
		if (role.parent === undefined) {
			continue;
		}
		const parent = byName.get(role.parent);
		subtest.ok(parent, `${role.name} has parent ${role.parent}`);
		const flattened = flattenSeedPermissions(role);
		for (const permission of flattenSeedPermissions(parent)) {
			subtest.ok(flattened.has(permission), `${role.name} inherits ${permission}`);
		}
	}
	subtest.end();
});

t.test("seedRoles are unique with one default and one admin", subtest => {
	const names = seedRoles.map(role => role.name);
	subtest.strictSame(names.length, new Set(names).size, "names are unique");
	subtest.strictSame(seedRoles.filter(role => role.isDefault).length, 1, "one default role");
	subtest.strictSame(seedRoles.filter(role => role.isAdmin).length, 1, "one admin role");
	subtest.end();
});
