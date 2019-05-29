local Gui = require 'expcore.gui'
local Store = require 'expcore.store'
local Global = require 'utils.global'
local Roles = require 'expcore.roles'
local Token = require 'utils.token'
local config = require 'config.tasks'
local format_time,table_keys = ext_require('expcore.common','format_time','table_keys')

local task_store = 'gui.left.task-list.tasks'

local task_details = {}
local force_tasks = {}
Global.register({
    task_details=task_details,
    force_tasks=force_tasks
},function(tbl)
    task_details = tbl.task_details
    force_tasks = tbl.force_tasks
end)

--- Adds a new task for this force with this players name attached
local function add_task(player,task_number)
    local task_id = tostring(Token.uid())

    if not force_tasks[player.force.name] then
        force_tasks[player.force.name] = {}
    end
    if task_number then
        table.insert(force_tasks[player.force.name],task_number,task_id)
    else
        table.insert(force_tasks[player.force.name],task_id)
    end

    task_details[task_id] = {
        task_id=task_id,
        force=player.force.name,
        last_edit_player=player.name,
        last_edit_time=game.tick,
        editing={[player.name]=true}
    }

    Store.set_child(task_store,task_id,'test')
end

--- Removes all refrences to a task
local function remove_task(task_id)
    local force_name = task_details[task_id].force
    Store.set_child(task_store,task_id)
    task_details[task_id] = nil
    table.remove_element(force_tasks[force_name],task_id)
end

--- If a player is allowed to use the edit buttons
local function player_allowed_edit(player)
    if config.only_admins_can_edit and not player.admin then
        return false
    end

    if config.edit_tasks_role_permision and not Roles.player_allowed(player,config.edit_tasks_role_permision) then
        return false
    end

    return true
end

--- Button in the header to add a new task
local update_all
local add_new_task =
Gui.new_button()
:set_sprites('utility/add')
:set_tooltip{'task-list.add-tooltip'}
:set_style('tool_button',function(style)
    Gui.set_padding_style(style,-2,-2,-2,-2)
    style.height = 20
    style.width = 20
end)
:on_click(function(player,element)
    add_task(player)
end)

--- Used to save changes to a task
local confirm_edit =
Gui.new_button()
:set_sprites('utility/downloaded')
:set_tooltip{'task-list.confirm-tooltip'}
:set_style('tool_button',function(style)
    Gui.set_padding_style(style,-2,-2,-2,-2)
    style.height = 20
    style.width = 20
end)
:on_click(function(player,element)
    local task_id = element.parent.name
    local task = element.parent.task.text
    local details = task_details[task_id]
    details.editing[player.name] = nil
    Store.set_child(task_store,task_id,task)
end)

--- Used to cancel any changes you made to a task
local generate_task
local cancel_edit =
Gui.new_button()
:set_sprites('utility/close_black')
:set_tooltip{'task-list.cancel-tooltip'}
:set_style('tool_button',function(style)
    Gui.set_padding_style(style,-2,-2,-2,-2)
    style.height = 20
    style.width = 20
end)
:on_click(function(player,element)
    local task_id = element.parent.name
    local details = task_details[task_id]
    details.editing[player.name] = nil
    generate_task(player,element.parent.parent,task_id)
end)

--- Removes the task from the list
local discard_task =
Gui.new_button()
:set_sprites('utility/trash')
:set_tooltip{'task-list.discord-tooltip'}
:set_style('tool_button',function(style)
    Gui.set_padding_style(style,-2,-2,-2,-2)
    style.height = 20
    style.width = 20
end)
:on_click(function(player,element)
    local task_id = element.parent.caption
    remove_task(task_id)
    update_all()
end)

--- Opens edit mode for the task
local edit_task =
Gui.new_button()
:set_sprites('utility/rename_icon_normal')
:set_tooltip{'task-list.edit-tooltip-none'}
:set_style('tool_button',function(style)
    Gui.set_padding_style(style,-2,-2,-2,-2)
    style.height = 20
    style.width = 20
end)
:on_click(function(player,element)
    local task_id = element.parent.caption
    local details = task_details[task_id]
    details.editing[player.name] = true
    generate_task(player,element.parent.parent,task_id)
end)

--[[ Generates each task, handles both view and edit mode
    element
    > count-"task_id"
    >> label
    > "task_id"
    >> task
    >> cancel_edit (edit mode)
    >> confirm_edit (edit mode)
    > edit-"task_id"
    >> edit_task
    >> discard_task
]]
function generate_task(player,element,task_id)
    local task = Store.get_child(task_store,task_id)
    local details = task_details[task_id]
    local editing = details.editing[player.name]
    local last_edit_player = details.last_edit_player
    local last_edit_time = details.last_edit_time
    local tasks = force_tasks[player.force.name]
    local task_number = table.index_of(tasks, task_id)

    if not task then
        -- task is nil so remove it from the list
        element.parent.no_tasks.visible = #tasks == 01
        Gui.destory_if_valid(element['count-'..task_id])
        Gui.destory_if_valid(element['edit-'..task_id])
        Gui.destory_if_valid(element[task_id])

    else
        element.parent.no_tasks.visible = false
        -- if it is not already present then add it now
        local task_area = element[task_id]
        if not task_area then
            -- label to show the task number
            local top_align = element.add{
                name='count-'..task_id,
                type='flow'
            }
            top_align.style.vertical_align = 'top'
            top_align.style.vertically_stretchable = true
            top_align.add{
                name='label',
                type='label',
                caption=task_number..')'
            }

            -- area which stores the task and buttons
            task_area =
            element.add{
                name=task_id,
                type='flow',
            }
            Gui.set_padding(task_area)
            task_area.style.vertical_align = 'top'

            -- if the player can edit then it adds the edit and delete button
            if player_allowed_edit(player) then
                local flow = Gui.create_right_align(element,'edit-'..task_id)
                flow.caption = task_id
                flow.style.vertical_align = 'top'
                flow.style.vertically_stretchable = true

                edit_task(flow)
                discard_task(flow)
            end

        end

        -- update the number indexes and the current editing players
        element['count-'..task_id].label.caption = task_number..')'
        if element['edit-'..task_id] then
            local players = table_keys(details.editing)
            if #players > 0 then
                element['edit-'..task_id][edit_task.name].tooltip = {'task-list.edit-tooltip',table.concat(players,', ')}
            else
                element['edit-'..task_id][edit_task.name].tooltip = {'task-list.edit-tooltip-none'}
            end
        end

        -- draws/updates the task area
        local element_type = task_area.task and task_area.task.type or nil
        if not editing and element_type == 'label' then
            -- update the label already present
            task_area.task.caption = task
            task_area.task.tooltip = {'task-list.last-edit',last_edit_player,format_time(last_edit_time)}

        elseif not editing then
            -- create the label, view mode
            if element['edit-'..task_id] then
                element['edit-'..task_id][edit_task.name].enabled = true
            end

            task_area.clear()

            local label =
            task_area.add{
                name='task',
                type='label',
                caption=task,
                tooltip={'task-list.last-edit',last_edit_player,format_time(last_edit_time)}
            }
            label.style.single_line = false
            label.style.maximal_width = 150

        elseif editing and element_type ~= 'textfield' then
            -- create the text field, edit mode, update it omited as value is being edited
            if element['edit-'..task_id] then
                element['edit-'..task_id][edit_task.name].enabled = false
            end

            task_area.clear()

            local entry =
            task_area.add{
                name='task',
                type='textfield',
                text=task
            }
            entry.style.maximal_width = 150
            entry.style.height = 20

            cancel_edit(task_area)
            confirm_edit(task_area)

        end

    end

end

--[[ generates the main gui structure
    element
    > container
    >> header
    >>> right aligned add_new_task
    >> scroll
    >>> no_tasks
    >>> table
]]
local function generate_container(player,element)
    Gui.set_padding(element,2,2,2,2)
    element.style.minimal_width = 200

    -- main container which contains the other elements
    local container =
    element.add{
        name='container',
        type='frame',
        direction='vertical',
        style='window_content_frame_packed'
    }
    Gui.set_padding(container)
    container.style.vertically_stretchable = false

    -- main header for the gui
    local header =
    container.add{
        name='header',
        type='frame',
        style='subheader_frame'
    }
    Gui.set_padding(header,2,2,4,4)
    header.style.horizontally_stretchable = true
    header.style.use_header_filler = false

    --- Caption for the header bar
    header.add{
        type='label',
        style='heading_1_label',
        caption={'task-list.main-caption'},
        tooltip={'task-list.sub-tooltip'}
    }

    --- Right aligned button to toggle the section
    local right_align = Gui.create_right_align(header)
    add_new_task(right_align)

    -- main flow for the data
    local flow =
    container.add{
        name='scroll',
        type='scroll-pane',
        direction='vertical',
        horizontal_scroll_policy='never',
        vertical_scroll_policy='auto-and-reserve-space'
    }
    Gui.set_padding(flow,1,1,2,2)
    flow.style.horizontally_stretchable = true
    flow.style.maximal_height = 185

    -- message to say that you have no tasks
    local non_made =
    flow.add{
        name='no_tasks',
        type='label',
        caption={'task-list.no-tasks'}
    }
    non_made.style.width = 200
    non_made.style.single_line = false

    -- table that stores all the data
    local col_count = 2
    if player_allowed_edit(player) then col_count = col_count+1 end
    local flow_table =
    flow.add{
        name='table',
        type='table',
        column_count=col_count,
        draw_horizontal_lines=true
    }
    Gui.set_padding(flow_table)
    flow_table.style.horizontally_stretchable = true
    flow_table.style.top_cell_padding = 3
    flow_table.style.bottom_cell_padding = 3

    return flow_table
end

local task_list =
Gui.new_left_frame('gui/task-list')
:set_sprites('utility/not_enough_repair_packs_icon')
:set_direction('vertical')
:set_tooltip{'task-list.main-tooltip'}
:set_open_by_default()
:on_draw(function(player,element)
    local data_table = generate_container(player,element)
    local force_name = player.force.name

    local tasks = force_tasks[force_name] or {}
    for _,task_id in pairs(tasks) do
        generate_task(player,data_table,task_id)
    end
end)
:on_update(function(player,element)
    local data_table = element.container.scroll.table
    local force_name = player.force.name

    local tasks = force_tasks[force_name] or {}
    for _,task_id in pairs(tasks) do
        generate_task(player,data_table,task_id)
    end
end)

update_all = task_list 'update_all'

Store.register(task_store,function(value,task_id)
    local details = task_details[task_id]
    local force = game.forces[details.force]

    for _,player in pairs(force.players) do
        local frame = task_list:get_frame(player)
        local element = frame.container.scroll.table
        generate_task(player,element,task_id)
    end
end)

return task_list