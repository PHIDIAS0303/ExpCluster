--- Config file for the tasks gui
-- @config Tasks

return {
    -- Adding tasks
    allow_add_task = "all", --- @setting allow_add_task dictates who is allowed to add new tasks; values: all, admin, exp_roles, none
    exp_roles_allow_add_task = "exp_scenario.gui.task_list.add", --- @setting exp_roles_allow_add_task if exp_roles is used then this is the required permission

    -- Editing tasks
    allow_edit_task = "exp_roles", --- @setting allow_edit_task dictates who is allowed to edit existing tasks; values: all, admin, exp_roles, none
    exp_roles_allow_edit_task = "exp_scenario.gui.task_list.edit", --- @setting exp_roles_allow_edit_task if exp_roles is used then this is the required permission
    user_can_edit_own_tasks = true, --- @settings if true then the user who made the task can edit it regardless of the allow_edit_task setting
}
