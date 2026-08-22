"use strict";
const t = require("tap");
const lib = require("@clusterio/lib");
const { InstancePlugin } = require("../dist/node/instance");
const messages = require("../dist/node/messages");

const logger = { child: () => logger, info: () => {}, warn: () => {}, error: () => {}, verbose: () => {} };

// Subscribing validates event names against the link registry
lib.Link.register(messages.RoleUpdatedEvent);
lib.Link.register(messages.AssignmentUpdatedEvent);

const sampleRoles = () => [
	new messages.RoleRecord(1, "Player", ["exp_scenario.gui.readme"], new messages.RoleMetaRecord(1, 2), true),
	new messages.RoleRecord(5, "Moderator", ["exp_scenario.gui.readme", "core.admin"], new messages.RoleMetaRecord(5, 1)),
];
const sampleAssignments = () => [new messages.AssignmentRecord("alice", new Set([5]))];

/** Build a plugin around a fake instance, started on first use by each test. */
async function startPlugin(t2, { syncMode = "bidirectional", roles = sampleRoles() } = {}) {
	const state = { sent: [], rcons: [], warnings: [], failNext: null };
	const instance = {
		logger,
		config: { get: field => (field === "exp_roles.sync_mode" ? syncMode : undefined) },
		handle: () => {},
		server: { handle: () => {} },
		sendTo: async (dst, request) => {
			state.sent.push(request);
			if (state.failNext) {
				const error = state.failNext;
				state.failNext = null;
				throw error;
			}
			if (request instanceof messages.RoleListRequest) {
				return roles;
			}
			if (request instanceof messages.AssignmentListRequest) {
				return sampleAssignments();
			}
			return undefined;
		},
		sendRcon: async command => state.rcons.push(command),
	};

	const plugin = new InstancePlugin({ name: "exp_roles" }, instance, {});
	plugin.logger = { ...logger, warn: message => state.warnings.push(message) };
	await plugin.init();
	return { plugin, state };
}

/** The lua receiver and payload of a recorded rcon command. */
function decodeRcon(command) {
	const match = command.match(/^\/sc exp_roles\.(\w+)\(helpers\.json_to_table\[=\[(.*)\]=\]\)$/s);
	return { receiver: match[1], payload: JSON.parse(match[2]) };
}

t.test("start subscribes and initialises the lua module", async t2 => {
	const { plugin, state } = await startPlugin(t2, { syncMode: "enabled" });
	await plugin.onStart();

	const subscribed = state.sent.filter(request => request instanceof lib.SubscriptionRequest);
	t2.strictSame(subscribed.length, 2, "roles and assignments are subscribed to");
	t2.ok(state.sent.some(request => request instanceof messages.RoleListRequest), "the roles are requested");
	t2.ok(state.sent.some(request => request instanceof messages.AssignmentListRequest), "the assignments are requested");

	const initialise = decodeRcon(state.rcons[0]);
	t2.strictSame(initialise.receiver, "initialise", "the lua module is initialised");
	t2.strictSame(initialise.payload.permission_names, ["exp_scenario.gui.readme", "core.admin"],
		"each permission name is sent once");
	t2.strictSame(initialise.payload.roles[1].permissions, [0, 1], "roles reference permissions by index");
	t2.strictSame(initialise.payload.assignments, [{ name: "alice", role_ids: [5] }], "the assignments are sent");

	const emit = decodeRcon(state.rcons[1]);
	t2.strictSame([emit.receiver, emit.payload], ["set_emit_events", false], "enabled does not emit changes back");
	t2.strictSame(state.warnings.length, 0, "no warnings with a default role");
});

t.test("bidirectional emits changes back", async t2 => {
	const { plugin, state } = await startPlugin(t2);
	await plugin.onStart();
	const emit = decodeRcon(state.rcons[state.rcons.length - 1]);
	t2.strictSame([emit.receiver, emit.payload], ["set_emit_events", true]);
});

t.test("disabled does nothing on start", async t2 => {
	const { plugin, state } = await startPlugin(t2, { syncMode: "disabled" });
	await plugin.onStart();
	t2.strictSame(state.sent.length, 0, "nothing is sent");
	t2.strictSame(state.rcons.length, 0, "no commands are run");
});

t.test("a missing default role is warned about", async t2 => {
	const roles = sampleRoles().map(record => { record.isDefault = false; return record; });
	const { plugin, state } = await startPlugin(t2, { roles });
	await plugin.onStart();
	t2.ok(state.warnings.some(message => /default role/.test(message)), "the warning names the default role");
});

t.test("updates from the controller are forwarded to lua", async t2 => {
	const { plugin, state } = await startPlugin(t2);
	await plugin.handleRoleUpdatedEvent(new messages.RoleUpdatedEvent(sampleRoles()));
	const roles = decodeRcon(state.rcons[0]);
	t2.strictSame(roles.receiver, "receive_role_updates", "role updates are forwarded");
	t2.strictSame(roles.payload[0].name, "Player", "the records are sent in plain form");

	await plugin.handleAssignmentUpdatedEvent(new messages.AssignmentUpdatedEvent(sampleAssignments()));
	const assignments = decodeRcon(state.rcons[1]);
	t2.strictSame(assignments.receiver, "receive_assignment_updates", "assignment updates are forwarded");
});

t.test("updates are not forwarded while disabled", async t2 => {
	const { plugin, state } = await startPlugin(t2, { syncMode: "disabled" });
	await plugin.handleRoleUpdatedEvent(new messages.RoleUpdatedEvent(sampleRoles()));
	await plugin.handleAssignmentUpdatedEvent(new messages.AssignmentUpdatedEvent(sampleAssignments()));
	t2.strictSame(state.rcons.length, 0, "no commands are run");
});

t.test("in game changes are sent up and rolled back when refused", async t2 => {
	const { plugin, state } = await startPlugin(t2);
	await plugin.handleAssignmentUpdateIPC({ name: "alice", assign: [5], unassign: undefined });
	const request = state.sent[0];
	t2.ok(request instanceof messages.AssignmentUpdateRequest, "the change is sent as a request");
	t2.strictSame([request.name, request.assign, request.unassign], ["alice", [5], []], "the request names the change");

	state.failNext = new Error("User 'alice' does not exist");
	await plugin.handleAssignmentUpdateIPC({ name: "alice", assign: [5], unassign: undefined });
	const rollback = decodeRcon(state.rcons[0]);
	t2.strictSame(rollback.receiver, "reject_assignment", "the refusal is rolled back in lua");
	t2.strictSame(rollback.payload, { name: "alice", role_ids: [5] }, "the rollback names the refused roles");
});

t.test("in game changes are dropped unless bidirectional", async t2 => {
	const { plugin, state } = await startPlugin(t2, { syncMode: "enabled" });
	await plugin.handleAssignmentUpdateIPC({ name: "alice", assign: [5], unassign: undefined });
	t2.strictSame(state.sent.length, 0, "nothing is sent");
});

t.test("changing the sync mode toggles emit", async t2 => {
	const { plugin, state } = await startPlugin(t2);
	await plugin.onInstanceConfigFieldChanged("exp_roles.sync_mode", "enabled", "bidirectional");
	const emit = decodeRcon(state.rcons[0]);
	t2.strictSame([emit.receiver, emit.payload], ["set_emit_events", false], "leaving bidirectional stops emitting");
});
