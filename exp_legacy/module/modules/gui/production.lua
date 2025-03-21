---- Production Data
-- @gui Production

local Gui = require("modules/exp_gui")
local Event = require("modules/exp_legacy/utils/event") --- @dep utils.event
local Roles = require("modules.exp_legacy.expcore.roles") --- @dep expcore.roles

local production_container

local precision = {
    [1] = defines.flow_precision_index.five_seconds,
    [2] = defines.flow_precision_index.one_minute,
    [3] = defines.flow_precision_index.ten_minutes,
    [4] = defines.flow_precision_index.one_hour,
    [5] = defines.flow_precision_index.ten_hours,
}

local font_color = {
    ["positive"] = { r = 0.3, g = 1, b = 0.3 },
    ["negative"] = { r = 1, g = 0.3, b = 0.3 },
}

local function format_n(amount)
    if math.abs(amount) < 0.009 then
        return "0.00"
    end
    local suffix = ""
    local suffix_list = {
        [" G"] = 1e9,
        [" M"] = 1e6,
        [" k"] = 1e3
    }
    local scale = 1
    for letter, limit in pairs(suffix_list) do
        if math.abs(amount) >= limit then
            scale = limit
            suffix = letter
            break
        end
    end
    local formatted = string.format("%.2f%s", amount / scale, suffix)
    -- Split into integer and fractional parts
    local integer_part, fractional_part = formatted:match("^(%-?%d+)%.(%d+)(.*)$")
    -- Add commas to integer part
    return string.format("%s.%s%s", (integer_part or formatted):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""):gsub("-,", "-"), fractional_part or "00", suffix)
end

--- Display group
-- @element production_data_group
local production_data_group = Gui.element("production_data_group")
    :draw(function(_def, parent, i)
        local item

        if i == 0 then
            item = parent.add{
                type = "drop-down",
                name = "production_0_e",
                items = { "5s", "1m", "10m", "1h", "10h" },
                selected_index = 3,
            }
            item.style.width = 80
        else
            item = parent.add{
                type = "choose-elem-button",
                name = "production_" .. i .. "_e",
                elem_type = "item",
                style = "slot_button",
            }
            item.style.height = 32
            item.style.width = 32
        end

        for j = 1, 3 do
            local data = parent.add{
                type = "label",
                name = "production_" .. i .. "_" .. j,
                caption = "0.00",
                style = "heading_2_label",
            }
            data.style.font_color = font_color["positive"]
        end

        return item
    end)

--- A vertical flow containing all the production data
-- @element production_data_set
local production_data_set = Gui.element("production_data_set")
    :draw(function(_, parent, name)
        local production_set = parent.add{ type = "flow", direction = "vertical", name = name }
        local disp = Gui.elements.scroll_table(production_set, 320, 4, "disp")
        for i = 2, 4 do
            disp.style.column_alignments[i] = "right"
        end
        production_data_group(disp, 0)
        disp["production_0_1"].caption = { "production.label-prod" }
        disp["production_0_1"].tooltip = { "production.tooltip-per-second" }
        disp["production_0_2"].caption = { "production.label-con" }
        disp["production_0_2"].tooltip = { "production.tooltip-per-second" }
        disp["production_0_3"].caption = { "production.label-bal" }
        disp["production_0_3"].tooltip = { "production.tooltip-per-second" }
        for i = 1, 8 do
            production_data_group(disp, i)
        end
        return production_set
    end)

production_container = Gui.element("production_container")
    :draw(function(def, parent)
        local container = Gui.elements.container(parent, 320)
        production_data_set(container, "production_st")
        return container.parent
    end)

--- Add the element to the left flow with a toolbar button
Gui.add_left_element(production_container, false)
Gui.toolbar.create_button{
    name = "production_toggle",
    left_element = production_container,
    sprite = "entity/assembling-machine-3",
    tooltip = { "production.main-tooltip" },
    visible = function(player, element)
        return Roles.player_allowed(player, "gui/production")
    end
}

Event.on_nth_tick(60, function()
    for _, player in pairs(game.connected_players) do
        local container = Gui.get_left_element(production_container, player)
        local stat = player.force.get_item_production_statistics(player.surface) -- Allow remote view
        local precision_value = precision[container.frame["production_st"].disp.table["production_0_e"].selected_index]
        local table = container.frame["production_st"].disp.table
        for i = 1, 8 do
            local production_prefix = "production_" .. i
            local item = table[production_prefix .. "_e"].elem_value --[[ @as string ]]
            if item then
                local add = math.floor(stat.get_flow_count{ name = item, category = "input", precision_index = precision_value, count = false } / 6) / 10
                local minus = math.floor(stat.get_flow_count{ name = item, category = "output", precision_index = precision_value, count = false } / 6) / 10
                local sum = add - minus
                table[production_prefix .. "_1"].caption = format_n(add)
                table[production_prefix .. "_2"].caption = format_n(minus)
                table[production_prefix .. "_3"].caption = format_n(sum)
                table[production_prefix .. "_3"].style.font_color = (sum < 0 and font_color["negative"]) or font_color["positive"]
            else
                table[production_prefix .. "_1"].caption = "0.00"
                table[production_prefix .. "_2"].caption = "0.00"
                table[production_prefix .. "_3"].caption = "0.00"
                table[production_prefix .. "_3"].style.font_color = font_color["positive"]
            end
        end
    end
end)
