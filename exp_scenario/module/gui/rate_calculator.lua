--[[-- Gui - Rate Calculator
Adds a Gui which calculate the rate of selected machines
]]

local Gui = require("modules/exp_gui")
local AABB = require("modules/exp_util/aabb")
local Roles = require("modules/exp_roles")

local format_string = string.format
local format_number = require("util").format_number

local Selection = require("modules/exp_util/selection")
local SelectArea = Selection.connect("RateArea")

local Feature = require("modules/exp_scenario/features")
local feature, config = Feature.register("rate_calculator", {
})

--- @class ExpGui_RateCalculator.elements
local Elements = {}

--- Button used to create a selection planner from a module table
--- @class ExpGui_RateCalculator.elements.create_selection_planner: ExpElement
--- @field data table<LuaGuiElement, LuaGuiElement>
--- @overload fun(parent: LuaGuiElement, rate_table: LuaGuiElement): LuaGuiElement
Elements.create_selection_planner = Gui.define("rate_calculator/create_selection_planner")
    :draw{
        type = "sprite-button",
        sprite = "item/blueprint-planner",
        tooltip = { "exp-gui_rate-calculator.tooltip-apply" },
        style = "shortcut_bar_button",
    }
    :style{
        size = 28,
        padding = 0,
    }
    :element_data(
        Gui.from_argument(1)
    )
    :on_click(function(def, player, element)
        --- @cast def ExpGui_RateCalculator.elements.create_selection_planner
        SelectArea:start(player, def.data[element])
    end) --[[@as any]]

--- A table that allows selecting modules 
--- @class ExpGui_RateCalculator.elements.rate_table: ExpElement
--- @field data table<LuaGuiElement, LuaGuiElement[]>
--- @overload fun(parent: LuaGuiElement): LuaGuiElement
Elements.rate_table = Gui.define("rate_calculator/rate_table")
    :draw(function(def, parent)
        --- @cast def ExpGui_RateCalculator.elements.rate_table
        return Gui.elements.scroll_table(parent, 500)
    end)
    :element_data{} --[[@as any]]

--- Label
--- @class ExpGui_RateCalculator.elements.label: ExpElement
--- @overload fun(parent: LuaGuiElement, caption: LocalisedString): LuaGuiElement
Elements.label = Gui.define("rate_calculator/label")
    :draw{
        type = "label",
        caption = Gui.from_argument(1),
        style = "heading_2_label",
    }
    :style{
        width = 100,
    } --[[@as any]]

local rate_table_1 = {
    1 = "item",
    2 = "machine"
}

--- Add a row to a module table
--- @param rate_table LuaGuiElement
--- @param data table
function Elements.rate_table.rows_adjust(rate_table, data)
    local rows = Elements.rate_table.data[rate_table]

    for _, v in ipairs(rows) do
        for _, vv in ipairs(v) do
            Gui.destroy_if_valid(vv)
        end
    end

    for i, v in ipairs(data) do
        rows[i] = {}
        for ki, kv in ipairs(rate_table_1) do
            rows[i][ki] = Elements.label(
                rate_table,
                (i > 1 and data[i - 1][kv] == v[kv])
                and ""
                or (v[kv] or "")
            )
        end
        rows[i][3] = Elements.label(
            rate_table,
            v["count"] and format_number(v["count"]) or ""
        )
        rows[i][4] = Elements.label(
            rate_table,
            v["productivity"] or ""
        )
        rows[i][5] = Elements.label(
            rate_table,
            v["rate"]
            and format_string(
                "%.1f",
                v["rate"]
            ) or ""
        )
        rows[i][6] = Elements.label(
            rate_table,
            v["usage"]
            and format_string(
                "%.1f %%",
                v["usage"]
            ) or ""
        )
    end
end

--- Container added to the left gui flow
Elements.container = Gui.define("rate_calculator/container")
    :draw(function(def, parent)
        local container = Gui.elements.container(parent)
        local header = Gui.elements.header(container, { caption = { "exp-gui_rate_calculator.caption-main" } })
        local rate_table = Elements.rate_table(container)
        Elements.rate_table.rows_adjust(rate_table, {})
        Elements.create_selection_planner(header, rate_table)
        return Gui.elements.container.get_root_element(container)
    end)

--- Add the element to the left flow with a toolbar button
Gui.add_left_element(Elements.container, false)
Gui.toolbar.create_button{
    name = "toggle_rate_calculator",
    left_element = Elements.container,
    sprite = "virtual-signal/signal-speed",
    tooltip = { "exp-gui_rate_calculator.tooltip-main" },
    visible = function(player, element)
        return feature:is_enabled() and Roles.player_has_permission(player, "exp_scenario.gui.rate_calculator")
    end
}

--- When an area is selected to have rate calculated
--- @param event EventData.on_player_selected_area
--- @param rate_table LuaGuiElement
SelectArea:on_selection(function(event, rate_table)
    local player = Gui.get_player(event)
    local area = AABB.expand(event.area)
    local surface = event.surface
    local order = {}
    local rates = {}

    local machines = surface.find_entities_filtered{
        area = area,
        force = player.force,
        type = {
            "assembling-machine",
            "furnace"
        }
    }

    -- ERR
    if #machines > 2000 then return end

    for _, machine in pairs(machines) do
        local recipe = machine.get_recipe()
        if recipe then
            local name = recipe.name
            if not rates[name] then rates[name] = {} end
            -- recipe.ingredients
            -- recipe.products
            local machine = machine.name
            if not rates[name][machine] then rates[name][machine] = {} end
            local crafting_speed = machine.crafting_speed
            if not rates[name][machine][crafting_speed] then rates[name][machine][crafting_speed] = {} end
            rates[name][machine][crafting_speed].productivity_bonus = machine.productivity_bonus
        end
    end

    --[[
        Elements.rate_table.rows_adjust(rate_table, data)

        Input?
        Output?

        1       2       3   4   5               6
        I       M       C   P   R               U
                ASM2    3   0   15 - 15 = 0     (100.0%)
    ]]
end)

local e = defines.events

return feature:guard{
    elements = Elements,
    events = {}
}
