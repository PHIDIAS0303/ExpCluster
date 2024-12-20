--[[-- Commands - Research
Adds a command to enable automatic research queueing
]]

local Storage = require("modules/exp_util/storage")
local Commands = require("modules/exp_commands")
local format_player_name = Commands.format_player_name_locale

local config = require("modules.exp_legacy.config.research") --- @dep config.research

local r = {}

local research = {
    res_queue_enable = false
}

Storage.register(research, function(tbl)
    research = tbl
end)

--- @param force LuaForce
--- @param silent boolean True when no message should be printed
function r.res_queue(force, silent)
    local res_q = force.research_queue
    local res

    if script.active_mods["space-age"] then
        res = force.technologies["mining-productivity-3"]

    else
        res = force.technologies["mining-productivity-4"]
    end

    if #res_q < config.queue_amount then
        for i = 1, config.queue_amount - #res_q do
            force.add_research(res)

            if not silent then
                game.print{ "exp-commands_research.queue", res.name, res.level + i }
            end
        end
    end
end

--- Sets the auto research state
Commands.new("set-auto-research", { "exp-commands_research.description" })
    :optional("state", { "exp-commands_research.arg-state" }, Commands.types.boolean)
    :add_aliases{ "auto-research" }
    :register(function(player, state)
        --- @cast state boolean?
        if state == nil then
            research.res_queue_enable = not research.res_queue_enable
        else
            research.res_queue_enable = state
        end

        if research.res_queue_enable then
            res_queue(player.force --[[@as LuaForce]], true)
        end

        local player_name = format_player_name(player)
        game.print{ "exp-commands_research.auto-research", player_name, research.res_queue_enable }
    end)

--- @param event EventData.on_research_finished
local function on_research_finished(event)
    if not research.res_queue_enable then return end

    local force = event.research.force
    if force.rockets_launched > 0 and force.technologies["mining-productivity-4"].level > 4 then
        res_queue(force, event.by_script)
    end
end

local e = defines.events
return {
    events = {
        [e.on_research_finished] = on_research_finished,
    },
    c = r
}
