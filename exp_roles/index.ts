import * as lib from "@clusterio/lib";
import * as messages from "./messages";

declare module "@clusterio/lib" {
	export interface InstanceConfigFields {
		"exp_roles.sync_mode": "disabled" | "enabled" | "bidirectional";
	}
}

lib.definePermission({
	name: "exp_roles.role.list",
	title: "List In Game Roles",
	description: "List the in game properties of all roles.",
	grantByDefault: true,
});
lib.definePermission({
	name: "exp_roles.role.subscribe",
	title: "Subscribe to In Game Role Updates",
	description: "Receive updates when the in game properties of a role change.",
	grantByDefault: true,
});
lib.definePermission({
	name: "exp_roles.role.update",
	title: "Update In Game Roles",
	description: "Modify the in game properties of a role, such as its order and colour.",
});

lib.definePermission({
	name: "exp_roles.assignment.list",
	title: "List Role Assignments",
	description: "List the roles held by each player in game.",
	grantByDefault: true,
});
lib.definePermission({
	name: "exp_roles.assignment.subscribe",
	title: "Subscribe to Role Assignment Updates",
	description: "Receive updates when the roles held by a player change.",
	grantByDefault: true,
});

export const plugin: lib.PluginDeclaration = {
	name: "exp_roles",
	title: "ExpGaming - Roles",
	description: "Clusterio plugin providing syncing of in game roles",

	features: [
		"SavePatching",
		"ScriptCommands",
	],

	messages: [
		messages.RoleUpdatedEvent,
		messages.AssignmentUpdatedEvent,

		messages.RoleListRequest,
		messages.RoleMetaUpdateRequest,

		messages.AssignmentListRequest,
		messages.AssignmentUpdateRequest,
	],

	instanceEntrypoint: "./dist/node/instance",
	instanceConfigFields: {
		"exp_roles.sync_mode": {
			description: "Synchronize in game roles with the controller",
			type: "string",
			enum: ["disabled", "enabled", "bidirectional"],
			initialValue: "bidirectional",
		},
	},

	controllerEntrypoint: "./dist/node/controller",
	controllerConfigFields: {
	},

	webEntrypoint: "./web",
};
