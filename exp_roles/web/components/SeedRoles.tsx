import React, { useContext, useState } from "react";
import { Button, Popconfirm } from "antd";

import { ControlContext, SectionHeader, useAccount, notifyErrorHandler } from "@clusterio/web_ui";

import { SeedRolesRequest } from "../../messages";

/** Button on the roles page which creates the roles the scenario shipped with. */
export default function SeedRoles() {
	const control = useContext(ControlContext);
	const account = useAccount();
	const [seeding, setSeeding] = useState(false);

	if (!account.hasPermission("core.role.create")) {
		return null;
	}

	return <SectionHeader
		title="ExpGaming Roles"
		extra={<Popconfirm
			title="Create the ExpGaming roles?"
			description="Roles which already exist by name are kept and only gain permissions."
			onConfirm={() => {
				setSeeding(true);
				control.send(new SeedRolesRequest())
					.catch(notifyErrorHandler("Error seeding roles"))
					.finally(() => setSeeding(false));
			}}
		>
			<Button loading={seeding}>Seed roles</Button>
		</Popconfirm>}
	/>;
}
