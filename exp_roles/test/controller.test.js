"use strict";
const t = require("tap");
const lib = require("@clusterio/lib");
const { ControllerPlugin } = require("../dist/node/controller");
const messages = require("../dist/node/messages");
const { seedRoles } = require("../dist/node/seed");

// Importing this defines the exp_scenario permissions the seed grants
require("@expcluster/scenario/dist/node/permissions");

const logger = { child: () => logger, info: () => {}, warn: () => {}, error: () => {}, verbose: () => {} };

class FakeUser {
	constructor(name, roleIds = []) {
		this.name = name;
		this.roleIds = new Set(roleIds);
		this.playerStats = { onlineTimeMs: 0 };
		this.updatedAtMs = 0;
		this.isDeleted = false;
	}

	set(field, value) {
		this[field] = value;
		this.updatedAtMs += 1;
	}
}

/** Build a plugin around fake controller internals, started on first use by each test. */
async function startPlugin(t2, { roles = [], users = [], config = {} } = {}) {
	const state = { broadcasts: [], permissionUpdates: [] };
	const configValues = {
		"controller.database_directory": t2.testdir(),
		"controller.default_role_id": lib.Role.DefaultPlayerRoleId,
		...config,
	};

	const roleStore = new lib.SubscribableDatastore(
		...await new lib.MemoryDatastoreProvider(new Map(roles.map(role => [role.id, role]))).bootstrap()
	);
	const userStore = new Map(users.map(user => [user.name, user]));

	const controller = {
		config: { get: key => configValues[key] },
		roles: roleStore,
		users: {
			records: { on: () => {}, values: () => userStore.values() },
			getByNameMutable: name => userStore.get(name),
			valuesMutable: () => userStore.values(),
			getOrCreateUser: name => {
				if (!userStore.has(name)) {
					userStore.set(name, new FakeUser(name));
				}
				return userStore.get(name);
			},
		},
		subscriptions: { handle: () => {}, broadcast: event => state.broadcasts.push(event) },
		handle: () => {},
		userPermissionsUpdated: user => state.permissionUpdates.push(user.name),
	};

	const plugin = new ControllerPlugin({ name: "exp_roles" }, controller, undefined, logger);
	await plugin.init();
	return { plugin, controller, state, users: userStore };
}

const role = (id, name, permissions = []) => new lib.Role(id, name, "", new Set(permissions));

t.test("init creates properties for existing roles and sweeps orphans", async t2 => {
	const { plugin } = await startPlugin(t2, { roles: [role(0, "Cluster Admin"), role(5, "Moderator")] });

	t2.strictSame(plugin.roleMeta.get(0).order, 1, "the first role is ordered first");
	t2.strictSame(plugin.roleMeta.get(5).order, 2, "the next role is ordered after it");

	plugin.roleMeta.set(new messages.RoleMetaRecord(99, 3));
	plugin.sweepRoleMeta();
	t2.notOk(plugin.roleMeta.get(99), "properties without a role are removed");
	t2.ok(plugin.roleMeta.get(5), "properties with a role are kept");
});

t.test("role records combine the role with its properties", async t2 => {
	const { plugin } = await startPlugin(t2, {
		roles: [role(1, "Player"), role(5, "Moderator", ["exp_scenario.command.kill"])],
	});
	plugin.roleMeta.set(new messages.RoleMetaRecord(5, 2, 1, "Mod"));

	const record = plugin.buildRoleRecord(plugin.controller.roles.get(5));
	t2.strictSame(record.name, "Moderator", "the name comes from the role");
	t2.strictSame(record.permissions, ["exp_scenario.command.kill"], "the permissions come from the role");
	t2.strictSame(record.meta.shortHand, "Mod", "the properties come from the datastore");
	t2.notOk(record.isDefault, "not the default role");
	t2.ok(plugin.buildRoleRecord(plugin.controller.roles.get(1)).isDefault, "the default role is marked");
});

t.test("role changes broadcast to subscribers", async t2 => {
	const { plugin, controller, state } = await startPlugin(t2, { roles: [role(1, "Player")] });

	state.broadcasts.length = 0;
	controller.roles.set(role(5, "Moderator"));
	const updated = state.broadcasts.flatMap(event => event.updates.map(update => update.name));
	t2.ok(updated.includes("Moderator"), "a new role is broadcast");

	state.broadcasts.length = 0;
	plugin.roleMeta.set(new messages.RoleMetaRecord(5, 2, 0, "Mod"));
	t2.ok(state.broadcasts.some(
		event => event instanceof messages.RoleUpdatedEvent && event.updates[0].meta.shortHand === "Mod"
	), "a property change is broadcast as its role");

	state.broadcasts.length = 0;
	await plugin.onControllerConfigFieldChanged("controller.default_role_id");
	t2.ok(state.broadcasts.some(event => event instanceof messages.RoleUpdatedEvent), "a default role change rebroadcasts");
});

t.test("subscriptions replay only newer records", async t2 => {
	const { plugin, controller } = await startPlugin(t2, { roles: [role(1, "Player")] });
	controller.roles.set(role(5, "Moderator"));
	const updatedAtMs = plugin.buildRoleRecord(controller.roles.get(5)).updatedAtMs;

	const all = await plugin.handleRoleSubscription({ lastRequestTimeMs: 0 });
	t2.strictSame(all.updates.length, 2, "everything is replayed from the start");
	const none = await plugin.handleRoleSubscription({ lastRequestTimeMs: updatedAtMs });
	t2.strictSame(none, null, "nothing is replayed when up to date");
});

t.test("assignments mirror users without the default role", async t2 => {
	const alice = new FakeUser("alice", [lib.Role.DefaultPlayerRoleId, 5]);
	alice.updatedAtMs = 10;
	const bob = new FakeUser("bob", [lib.Role.DefaultPlayerRoleId]);
	const { plugin } = await startPlugin(t2, { roles: [role(1, "Player"), role(5, "Moderator")], users: [alice, bob] });

	const records = plugin.listAssignmentRecords();
	t2.strictSame(records.length, 1, "users with only the default role are left out");
	t2.strictSame(records[0].name, "alice");
	t2.strictSame([...records[0].roleIds], [5], "the default role is not listed");
});

t.test("assignment updates validate the user and roles", async t2 => {
	const alice = new FakeUser("alice", [5]);
	const { plugin, state } = await startPlugin(t2, {
		roles: [role(1, "Player"), role(5, "Moderator"), role(6, "Regular")], users: [alice],
	});

	await t2.rejects(
		plugin.handleAssignmentUpdateRequest(new messages.AssignmentUpdateRequest("nobody", [], [])),
		{ message: /does not exist/ }, "an unknown user is refused",
	);
	await t2.rejects(
		plugin.handleAssignmentUpdateRequest(new messages.AssignmentUpdateRequest("alice", [99], [])),
		{ message: /does not exist/ }, "an unknown role is refused",
	);

	await plugin.handleAssignmentUpdateRequest(new messages.AssignmentUpdateRequest("alice", [6], [5]));
	t2.strictSame([...alice.roleIds], [6], "roles are added and removed");
	t2.ok(state.permissionUpdates.includes("alice"), "permission changes are pushed to the user");
});

t.test("roles are granted from online time", async t2 => {
	const newcomer = new FakeUser("newcomer");
	newcomer.playerStats.onlineTimeMs = 3600000;
	const veteran = new FakeUser("veteran");
	veteran.playerStats.onlineTimeMs = 7200000;
	const jailed = new FakeUser("jailed", [7]);
	jailed.playerStats.onlineTimeMs = 7200000;

	const { plugin } = await startPlugin(t2, {
		roles: [role(1, "Player"), role(6, "Regular"), role(7, "Jail")],
		users: [newcomer, veteran, jailed],
	});
	// The blocking role is marked first, since setting properties applies auto assignment
	plugin.roleMeta.set(new messages.RoleMetaRecord(7, 3, 1, "", "", null, null, true));
	plugin.roleMeta.set(new messages.RoleMetaRecord(6, 2, 0, "", "", null, 7200000));
	t2.ok(veteran.roleIds.has(6), "enough online time grants the role");
	t2.notOk(newcomer.roleIds.has(6), "not enough online time does not");
	t2.notOk(jailed.roleIds.has(6), "a blocking role prevents the grant");

	veteran.roleIds.delete(6);
	await plugin.onPlayerEvent(undefined, { type: "leave", name: "veteran" });
	t2.ok(veteran.roleIds.has(6), "granted again when the player leaves");
});

t.test("seeding creates the roles and reuses them by name", async t2 => {
	const { plugin, controller } = await startPlugin(t2, {
		roles: [role(0, "Cluster Admin", ["core.admin"]), role(1, "Player")],
	});

	await plugin.handleSeedRolesRequest();
	t2.strictSame(controller.roles.size, seedRoles.length, "every seed role exists");

	const moderator = [...controller.roles.values()].find(other => other.name === "Moderator");
	t2.ok(moderator.permissions.has("exp_scenario.command.jail"), "parent permissions are flattened in");
	t2.ok(plugin.roleMeta.get(moderator.id), "the role properties are created");
	t2.strictSame(plugin.roleMeta.get(moderator.id).shortHand, "Mod", "the properties match the seed");

	await plugin.handleSeedRolesRequest();
	t2.strictSame(controller.roles.size, seedRoles.length, "seeding again reuses the roles");
});
