--[[-- Gui - Auto Outpost
Automated Outpost planner, currently only fluid setup
]]

local Gui = require("modules/exp_gui")
local Roles = require("modules/exp_roles")

--- @class ExpGui_ProductionStats.elements
local Elements = {}

--- The font colours used for number labels
local font_color = {
    positive = { r = 0.3, g = 1, b = 0.3 },
    negative = { r = 1, g = 0.3, b = 0.3 },
}

--- Format a number to include commas and a suffix
local function format_number(amount)
    if math.abs(amount) < 0.009 then
        return "0.00"
    end

    local scaler = 1
    local suffix = ""
    local suffix_list = {
        [" G"] = 1e9,
        [" M"] = 1e6,
        [" k"] = 1e3
    }

    -- Select which suffix and scaler to use
    for _suffix, _scaler in pairs(suffix_list) do
        if math.abs(amount) >= _scaler then
            scaler = _scaler
            suffix = _suffix
            break
        end
    end

    local formatted = string.format("%.2f%s", amount / scaler, suffix)
    -- Split into integer and fractional parts
    local integer_part, fractional_part = formatted:match("^(%-?%d+)%.(%d+)(.*)$")
    -- Add commas to integer part
    return string.format("%s.%s%s", (integer_part or formatted):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""):gsub("-,", "-"), fractional_part or "00", suffix)
end

--- Used to select the item to be displayed on a row
--- @class ExpGui_ProductionStats.elements.item_selector: ExpElement
--- @field data table<LuaGuiElement, { on_last_row: boolean, auto_table: LuaGuiElement }>
--- @overload fun(parent: LuaGuiElement, auto_table: LuaGuiElement): LuaGuiElement
Elements.item_selector = Gui.define("auto_outpost/item_selector")
    :draw{
        type = "choose-elem-button",
        elem_type = "item",
        style = "slot_button",
    }
    :style{
        size = 32,
    }
    :element_data{
        on_last_row = true,
        auto_table = Gui.from_argument(1),
    }
    :on_elem_changed(function(def, player, element, event)
        --- @cast def ExpGui_ProductionStats.elements.item_selector
        local element_data = def.data[element]
        if not element.elem_value then
            if element_data.on_last_row then
                Elements.auto_table.reset_row(element_data.auto_table, element)
            else
                Elements.auto_table.remove_row(element_data.auto_table, element)
            end
        elseif element_data.on_last_row then
            element_data.on_last_row = false
            Elements.auto_table.add_row(element_data.auto_table)
        end
    end) --[[@as any]]
    
--- Label used for every element in the production table
Elements.table_label = Gui.define("auto_outpost/table_label")
    :draw{
        type = "label",
        caption = Gui.from_argument(1, "0.00"),
        tooltip = Gui.from_argument(2),
        style = Gui.from_argument(3),
    }
    :style{
        horizontal_align = "right",
        minimal_width = 60,
    }

--- @class ExpGui_ProductionStats.elements.auto_table.row_elements
--- @field item_selector LuaGuiElement
--- @field production LuaGuiElement
--- @field consumption LuaGuiElement
--- @field net LuaGuiElement

--- @class ExpGui_ProductionStats.elements.auto_table.row_data
--- @field production LocalisedString
--- @field consumption LocalisedString
--- @field net LocalisedString
--- @field font_color Color

--- A table that allows selecting items 
--- @class ExpGui_ProductionStats.elements.auto_table: ExpElement
--- @field data table<LuaGuiElement, { rows: ExpGui_ProductionStats.elements.auto_table.row_elements[] }>
--- @overload fun(parent: LuaGuiElement): LuaGuiElement
Elements.auto_table = Gui.define("auto_outpost/auto_table")
    :track_all_elements()
    :draw(function(def, parent)
        local scroll_table = Gui.elements.scroll_table(parent, 304, 4)

        def.data[scroll_table] = {
            rows = {},
        }

        Elements.table_label(scroll_table, { "gui-production.production" }, { "exp-gui_auto_outpost.tooltip-per-second" }, "heading_2_label")
        Elements.table_label(scroll_table, { "gui-production.consumption" }, { "exp-gui_auto_outpost.tooltip-per-second" }, "heading_2_label")
        Elements.table_label(scroll_table, { "exp-gui_auto_outpost.caption-net" }, { "exp-gui_auto_outpost.tooltip-per-second" }, "heading_2_label")

        return scroll_table
    end) --[[@as any]]

--- Calculate the row data for a production table
--- @param force LuaForce
--- @param surface LuaSurface
--- @param item_name string
--- @param precision_index defines.flow_precision_index
--- @return ExpGui_ProductionStats.elements.auto_table.row_data
function Elements.auto_table.calculate_row_data(force, surface, item_name, precision_index)
    local get_flow_count = force.get_item_production_statistics(surface).get_flow_count
    local production = math.floor(get_flow_count{ name = item_name, category = "input", precision_index = precision_index, count = false } / 6) / 10
    local consumption = math.floor(get_flow_count{ name = item_name, category = "output", precision_index = precision_index, count = false } / 6) / 10
    local net = production - consumption
    return {
        production = format_number(production),
        consumption = format_number(consumption),
        net = format_number(net),
        font_color = net < 0 and font_color.negative or font_color.positive,
    }
end

--- A single row of a production table, the parent must be a production table
--- @param auto_table LuaGuiElement
function Elements.auto_table.add_row(auto_table)
    local rows = Elements.auto_table.data[auto_table].rows
    local item_selector = Elements.item_selector(auto_table, auto_table)
    rows[item_selector.index] = {
        item_selector = item_selector,
        production = Elements.table_label(auto_table, "0.00"),
        consumption = Elements.table_label(auto_table, "0.00"),
        net = Elements.table_label(auto_table, "0.00"),
    }
end

--- Remove a row from a production table
--- @param auto_table LuaGuiElement
--- @param item_selector LuaGuiElement
function Elements.auto_table.remove_row(auto_table, item_selector)
    local rows = Elements.auto_table.data[auto_table].rows
    local row = assert(rows[item_selector.index])
    rows[item_selector.index] = nil
    Gui.destroy_if_valid(item_selector)
    for _, element in pairs(row) do
        Gui.destroy_if_valid(element)
    end
end

--- Reset a row in a production table
--- @param auto_table LuaGuiElement
--- @param item_selector LuaGuiElement
function Elements.auto_table.reset_row(auto_table, item_selector)
    local rows = Elements.auto_table.data[auto_table].rows
    local row = assert(rows[item_selector.index])
    row.production.caption = "0.00"
    row.consumption.caption = "0.00"
    row.net.caption = "0.00"
    row.net.style.font_color = font_color.positive
end

--- Refresh the data on a row
--- @param auto_table LuaGuiElement
--- @param item_selector LuaGuiElement
--- @param row_data ExpGui_ProductionStats.elements.auto_table.row_data
function Elements.auto_table.refresh_row(auto_table, item_selector, row_data)
    local rows = Elements.auto_table.data[auto_table].rows
    local row = assert(rows[item_selector.index])
    row.production.caption = row_data.production
    row.consumption.caption = row_data.consumption
    row.net.caption = row_data.net
    row.net.style.font_color = row_data.font_color
end

--- Refresh all online tables
function Elements.auto_table.refresh_online()
    for player, auto_table in Elements.auto_table:online_elements() do
        local element_data = Elements.auto_table.data[auto_table]
        local precision_index = precision_indexes[element_data.precision_dropdown.selected_index]
        for _, row in pairs(element_data.rows) do
            local item_selector = row.item_selector
            local item_name = item_selector.elem_value --[[@as string?]]
            if item_name then
                local row_data = Elements.auto_table.calculate_row_data(player.force --[[@as LuaForce]], player.surface, item_name, precision_index)
                Elements.auto_table.refresh_row(auto_table, item_selector, row_data)
            end
        end
    end
end

--- Container added to the left gui flow
Elements.container = Gui.define("auto_outpost/container")
    :draw(function(def, parent)
        local container = Gui.elements.container(parent)
        local auto_table = Elements.auto_table(container)
        Elements.auto_table.add_row(auto_table)
        return Gui.elements.container.get_root_element(container)
    end)

--- Add the element to the left flow with a toolbar button
Gui.add_left_element(Elements.container, false)
Gui.toolbar.create_button{
    name = "toggle_auto_outpost",
    left_element = Elements.container,
    sprite = "entity/assembling-machine-3",
    tooltip = { "exp-gui_auto_outpost.tooltip-main" },
    visible = function(player, element)
        return Roles.player_has_permission(player, "exp_scenario.gui.auto_outpost")
    end
}

return {
    elements = Elements,
    on_nth_tick = {
        [60] = Elements.auto_table.refresh_online,
    }
}
