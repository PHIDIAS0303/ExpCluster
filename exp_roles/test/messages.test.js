"use strict";
const t = require("tap");
const messages = require("../dist/node/messages");
const { testMatrix, testRoundTripJsonSerialisable } = require("../../test/common");

const fullMeta = new messages.RoleMetaRecord(
	7, 3, 1, "Mod", "[Mod]", new messages.RoleColor(1, 2, 3), 3600000, true, 12345, false,
);

t.test("RoleColor", subtest => {
	testRoundTripJsonSerialisable(messages.RoleColor, testMatrix(
		[0, 255], // r
		[0, 128], // g
		[0, 1], // b
	));
	subtest.pass("round trips");
	subtest.end();
});

t.test("RoleMetaRecord", subtest => {
	testRoundTripJsonSerialisable(messages.RoleMetaRecord, testMatrix(
		[7], // id
		[3], // order
		[0, 1], // priority
		["", "Mod"], // shortHand
		["", "[Mod]"], // tag
		[null, new messages.RoleColor(1, 2, 3)], // color
		[null, 3600000], // autoAssignOnlineTimeMs
		[false, true], // blockAutoAssign
		[0, 12345], // updatedAtMs
		[false, true], // isDeleted
	));
	subtest.pass("round trips");
	subtest.end();
});

t.test("RoleRecord", subtest => {
	testRoundTripJsonSerialisable(messages.RoleRecord, testMatrix(
		[7], // id
		["Moderator"], // name
		[[], ["a.b", "c.d"]], // permissions
		[new messages.RoleMetaRecord(7, 3), fullMeta], // meta
		[false, true], // isDefault
		[0, 12345], // updatedAtMs
		[false, true], // isDeleted
	));
	subtest.pass("round trips");
	subtest.end();
});

t.test("AssignmentRecord", subtest => {
	testRoundTripJsonSerialisable(messages.AssignmentRecord, testMatrix(
		["alice"], // name
		[new Set(), new Set([5, 6])], // roleIds
		[0, 12345], // updatedAtMs
		[false, true], // isDeleted
	));
	subtest.pass("round trips");
	subtest.end();
});

t.test("update events and requests", subtest => {
	const record = new messages.RoleRecord(7, "Moderator", ["a.b"], fullMeta, true, 12345);
	const assignment = new messages.AssignmentRecord("alice", new Set([5]), 12345);

	testRoundTripJsonSerialisable(messages.RoleUpdatedEvent, testMatrix(
		[[], [record]], // updates
	));
	testRoundTripJsonSerialisable(messages.AssignmentUpdatedEvent, testMatrix(
		[[], [assignment]], // updates
	));
	testRoundTripJsonSerialisable(messages.RoleMetaUpdateRequest, testMatrix(
		[new messages.RoleMetaRecord(7, 3), fullMeta], // meta
	));
	testRoundTripJsonSerialisable(messages.AssignmentUpdateRequest, testMatrix(
		["alice"], // name
		[[], [5]], // assign
		[[], [6]], // unassign
	));
	subtest.pass("round trips");
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
