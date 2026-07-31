import React, { useContext, useEffect, useState } from "react";
import { Button, ColorPicker, Form, Input, InputNumber, Space, Switch, Tooltip } from "antd";

import * as lib from "@clusterio/lib";
import { ControlContext, SectionHeader, useAccount, notifyErrorHandler } from "@clusterio/web_ui";

import { RoleColor, RoleMetaRecord, RoleMetaUpdateRequest } from "../../messages";
import type { WebPlugin } from "..";

const MS_PER_HOUR = 3600000;

type RoleFormValues = {
	order: number;
	priority: number;
	shortHand: string;
	tag: string;
	color: string | { toRgb(): { r: number, g: number, b: number } } | null;
	autoAssignHours: number | null;
	blockAutoAssign: boolean;
};

/**
 * In game properties of a role, shown at the end of the core role page.
 *
 * The name, description and permissions of a role are owned by clusterio, this
 * only covers the properties which only mean something in game.
 */
export default function RoleProperties(props: { plugin: WebPlugin, role?: lib.Role }) {
	const control = useContext(ControlContext);
	const account = useAccount();
	const [form] = Form.useForm<RoleFormValues>();
	const [applying, setApplying] = useState(false);

	const [roles] = props.plugin.useRoles();
	const record = props.role ? roles.get(props.role.id) : undefined;
	const meta = record?.meta;
	const canUpdate = account.hasPermission("exp_roles.role.update");

	useEffect(() => {
		if (!meta) {
			return;
		}
		form.setFieldsValue({
			order: meta.order,
			priority: meta.priority,
			shortHand: meta.shortHand,
			tag: meta.tag,
			color: meta.color ? `rgb(${meta.color.r}, ${meta.color.g}, ${meta.color.b})` : null,
			autoAssignHours: meta.autoAssignOnlineTimeMs === null
				? null
				: meta.autoAssignOnlineTimeMs / MS_PER_HOUR,
			blockAutoAssign: meta.blockAutoAssign,
		});
	}, [meta, form]);

	if (!props.role || !meta) {
		return null;
	}

	async function apply() {
		const values = form.getFieldsValue();

		let color: RoleColor | null = null;
		if (values.color && typeof values.color !== "string") {
			const rgb = values.color.toRgb();
			color = new RoleColor(Math.round(rgb.r), Math.round(rgb.g), Math.round(rgb.b));
		} else if (typeof values.color === "string") {
			const match = values.color.match(/(\d+)\D+(\d+)\D+(\d+)/);
			if (match) {
				color = new RoleColor(Number(match[1]), Number(match[2]), Number(match[3]));
			}
		}

		await control.send(new RoleMetaUpdateRequest(new RoleMetaRecord(
			props.role!.id,
			values.order,
			values.priority,
			values.shortHand ?? "",
			values.tag ?? "",
			color,
			values.autoAssignHours === null || values.autoAssignHours === undefined
				? null
				: values.autoAssignHours * MS_PER_HOUR,
			values.blockAutoAssign ?? false,
		)));
	}

	return <>
		<SectionHeader title="In Game Properties" />
		<Form form={form} labelCol={{ span: 8 }} wrapperCol={{ span: 16 }} disabled={!canUpdate}>
			<Form.Item
				name="order"
				label={<Tooltip title="A lower value is a more privileged role">Order</Tooltip>}
			>
				<InputNumber />
			</Form.Item>
			<Form.Item
				name="priority"
				label={
					<Tooltip title="Only the highest priority roles a player holds apply, used by Jail">
						Priority
					</Tooltip>
				}
			>
				<InputNumber />
			</Form.Item>
			<Form.Item name="shortHand" label="Short hand">
				<Input />
			</Form.Item>
			<Form.Item name="tag" label="Tag">
				<Input />
			</Form.Item>
			<Form.Item name="color" label="Colour">
				<ColorPicker allowClear format="rgb" disabledAlpha />
			</Form.Item>
			<Form.Item
				name="autoAssignHours"
				label={
					<Tooltip title="Granted once a player reaches this much online time across the cluster">
						Auto assign after (hours)
					</Tooltip>
				}
			>
				<InputNumber min={0} placeholder="Never" />
			</Form.Item>
			<Form.Item name="blockAutoAssign" label="Block auto assign" valuePropName="checked">
				<Switch />
			</Form.Item>
			{canUpdate && <Form.Item wrapperCol={{ offset: 8 }}>
				<Space>
					<Button
						type="primary"
						loading={applying}
						onClick={() => {
							setApplying(true);
							apply()
								.catch(notifyErrorHandler("Error updating role properties"))
								.finally(() => setApplying(false));
						}}
					>Apply</Button>
				</Space>
			</Form.Item>}
		</Form>
	</>;
}
