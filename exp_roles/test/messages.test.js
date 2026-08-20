"use strict";
const t = require("tap");
const { Value } = require("@sinclair/typebox/value");
const messages = require("../dist/node/messages");

function roundTrip(subtest, Record, record) {
	const json = record.toJSON();
	subtest.ok(Value.Check(Record.jsonSchema, json), "json matches the schema");
	subtest.strictSame(Record.fromJSON(json), record, "the record round trips");
}

t.test("RoleMetaRecord", subtest => {
	roundTrip(subtest, messages.RoleMetaRecord, new messages.RoleMetaRecord(7, 3));
	roundTrip(subtest, messages.RoleMetaRecord, new messages.RoleMetaRecord(
		7, 3, 1, "Mod", "[Mod]", new messages.RoleColor(1, 2, 3), 3600000, true, 12345, false,
	));
	subtest.end();
});

t.test("RoleRecord", subtest => {
	roundTrip(subtest, messages.RoleRecord, new messages.RoleRecord(
		7, "Moderator", ["exp_scenario.command.kill"], new messages.RoleMetaRecord(7, 3), true, 12345,
	));
	subtest.end();
});

t.test("AssignmentRecord", subtest => {
	roundTrip(subtest, messages.AssignmentRecord, new messages.AssignmentRecord("alice", new Set([5, 6]), 12345));
	subtest.end();
});

t.test("encodeRolesForLua sends each permission name once", subtest => {
	const meta = id => new messages.RoleMetaRecord(id, id);
	const encoded = messages.encodeRolesForLua([
		new messages.RoleRecord(1, "A", ["p.one", "p.two"], meta(1)),
		new messages.RoleRecord(2, "B", ["p.two", "p.three"], meta(2)),
	]);

	subtest.strictSame(encoded.permission_names, ["p.one", "p.two", "p.three"], "names are deduplicated");
	subtest.strictSame(encoded.roles[0].permissions, [0, 1], "indexes are zero based");
	subtest.strictSame(encoded.roles[1].permissions, [1, 2], "shared names reuse their index");
	subtest.end();
});
