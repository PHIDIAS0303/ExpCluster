--- This file is used to setup the map starting settings and the items players will start with
-- @config Advanced-Start

--- These are called factories because they return another function
-- use these as a simple methods of adding new items
-- they will do most of the work for you
-- ["item-name"] = factory(params)
-- luacheck:ignore 212/amount_made 212/items_made 212/player

-- Use these to adjust for ticks ie game.tick < 5*minutes
-- luacheck:ignore 211/seconds 211/minutes 211/hours
local seconds, minutes, hours = 60, 3600, 216000

--- Use to make a split point for the number of items given based on time
-- ["stone-furnace"]=cutoff_time(5*minutes, 4,0) -- before 5 minutes give four items after 5 minutes give none
local function cutoff_time(time, before, after)
    return function(amount_made, items_made, player)
        if game.tick < time then
            return before
        else
            return after
        end
    end
end

--- Use to make a split point for the number of items given based on amount made
-- ["firearm-magazine"]=cutoff_amount_made(100, 10, 0) -- give 10 items until 100 items have been made
--[[
local function cutoff_amount_made(amount, before, after)
    return function(amount_made, items_made, player)
        if amount_made < amount then
            return before
        else
            return after
        end
    end
end
]]

--- Same as above but will not give any items if x amount has been made of another item, useful for tiers
-- ["light-armor"]=cutoff_amount_made_unless(5, 0,1,"heavy-armor",5) -- give light armor once 5 have been made unless 5 heavy armor has been made
--[[
local function cutoff_amount_made_unless(amount, before, after, second_item, second_amount)
    return function(amount_made, items_made, player)
        if items_made(second_item) < second_amount then
            if amount_made < amount then
                return before
            else
                return after
            end
        else
            return 0
        end
    end
end
]]

-- Use for mass production items where you want the amount to change based on the amount already made
-- ["iron-plate"]=scale_amount_made(5*minutes, 10, 10) -- for first 5 minutes give 10 items then after apply a factor of 10
--[[
local function scale_amount_made(amount, before, scalar)
    return function(amount_made, items_made, player)
        if amount_made < amount then
            return before
        else
            return (amount_made * scalar) / ((game.tick / minutes) ^ 2)
        end
    end
end
]]

--[[
    Common values
    game.tick is the amount of time the game has been on for
    amount_made is the amount of that item which has been made
    items_made("item-name") will return the amount of any item made
    player is the player who just spawned
    hours, minutes, seconds are the number of ticks in each unit of time
]]

return {
    skip_intro = true, --- @setting skip_intro skips the intro given in the default factorio free play scenario
    skip_victory = true, --- @setting skip_victory will skip the victory screen when a rocket is launched
    friendly_fire = false, --- @setting friendly_fire weather players will be able to attack each other on the same force
    enemy_expansion = false, --- @setting enemy_expansion a catch all for in case the map settings file fails to load
    chart_radius = 16 * 32, --- @setting chart_radius the number of tiles that will be charted when the map starts
    items = { --- @setting items items and there condition for being given
        ["iron-ore"] = cutoff_time(20 * minutes, 80, 0),
        ["stone"] = cutoff_time(20 * minutes, 20, 0),
        ["coal"] = cutoff_time(20 * minutes, 20, 0),
        -- ["burner-mining-drill"]=cutoff_time(20 * minutes, 8, 0),
        -- ["stone-furnace"]=cutoff_time(20 * minutes, 8, 0),
        ["submachine-gun"] = 1,
        ["piercing-rounds-magazine"] = 20,
        ["construction-robot"] = 10,
        ["modular-armor"] = 1,
        ["solar-panel-equipment"] = 16,
        ["belt-immunity-equipment"] = 1,
        ["battery-equipment"] = 2,
        ["personal-roboport-equipment"] = 1
        --[[
        ["construction-robot"] = 50,
        ["spidertron"] = 1,
        ["spidertron-remote"] = 1,
        ["modular-armor"] = 1,
        ["solar-panel-equipment"] = 60,
        ["belt-immunity-equipment"] = 1,
        ["battery-equipment"] = 6,
        ["personal-roboport-equipment"] = 5
        ]]
    }
}
