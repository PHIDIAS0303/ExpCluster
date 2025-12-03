--- Used to config the spawn generation settings yes there is alot here i know just ignore the long tables at the end (they were generated with a command)
-- @config Spawn-Area

return {
    spawn_area = { --- @setting spawn_area Settings relating to the whole spawn area
        -- Enable predefined patches: 128, else: 32
        deconstruction_radius = 12, -- @setting deconstruction_radius All entities within this radius will be removed
        deconstruction_tile = "refined-concrete", --- @setting deconstruction_tile Tile to be placed in the deconstruction radius, use nil for map gen
        tile_radius = 14,
        landfill_radius = 16, --- @setting pattern_radius All water within this radius will be land filled
    },
    turrets = { --- @setting turrets Settings relating to adding turrets to spawn
        enabled = true, --- @setting enabled Whether turrets will be added to spawn
        ammo_type = "uranium-rounds-magazine", --- @setting ammo_type The ammo type that will be used during refills
        refill_time = 60 * 60 * 5, --- @setting refill_time The time in ticks between each refill of the turrets, only change if having lag issues
        offset = { x = 0, y = 0 }, --- @setting offset The position offset to apply to turrets
        locations = { --- @setting locations The locations of all turrets, this list can change during runtime
            { -2, -2 },
            { 2, -2 },
            { -2, 2 },
            { 2, 2 },
        },
    },
    afk_belts = { --- @setting afk_belts Settings relating to adding afk belts to spawn
        enabled = true, --- @setting enabled Whether afk belts will be added to spawn
        belt_type = "transport-belt", --- @setting belt_type The belt to be used as afk belts
        protected = true, --- @setting protected Whether belts will be protected from player interaction
        offset = { x = 0, y = 0 }, --- @setting offset The position offset to apply to afk belts
        locations = { --- @setting locations The locations to spawn afk belts at, given as the top left position
            { 4, 4 },
            { 4, -4 },
            { -4, 4 },
            { -4, -4 }
        }
    },
    water = { --- @setting water Settings relating to adding water to spawn
        enabled = true, --- @setting enabled Whether water tiles will be added to spawn
        water_tile = "water-mud", --- @setting water_tile The tile to be used as the water tile
        offset = { x = 0, y = 0 }, --- @setting offset The position offset to apply to water tiles
        locations = { --- @setting locations The location of the water tiles {x,y}
            -- Each is a 3x3 with the closest tile to 0,0 removed
            { 5, 6 }, { 5, 7 }, { 6, 5 }, { 6, 6 }, { 6, 7 }, { 7, 5 }, { 7, 6 }, { 7, 7 },
            { 5, -7 }, { 5, -8 }, { 6, -6 }, { 6, -7 }, { 6, -8 }, { 7, -6 }, { 7, -7 }, { 7, -8 },
            { -6, 6 }, { -6, 7 }, { -7, 5 }, { -7, 6 }, { -7, 7 }, { -8, 5 }, { -8, 6 }, { -8, 7 },
            { -6, -7 }, { -6, -8 }, { -7, -6 }, { -7, -7 }, { -7, -8 }, { -8, -6 }, { -8, -7 }, { -8, -8 },
        }
    },
    entities = { --- @setting entities Settings relating to adding entities to spawn
        enabled = true, --- @setting enabled Whether entities will be added to spawn
        protected = true, --- @setting protected Whether entities will be protected from player interaction
        operable = true, --- @setting operable Whether entities can be opened by players, must be true if chests are used
        offset = { x = 0, y = 0 }, --- @setting offset The position offset to apply to entities
        locations = { --- @setting locations The location and names of entities {name,x,y}
            { "steel-chest", 1, 3 }, { "steel-chest", 1, 4 }, { "steel-chest", 1, 5 },
            { "steel-chest", 3, 1 }, { "steel-chest", 4, 1 }, { "steel-chest", 5, 1 },
            { "steel-chest", 1, -4 }, { "steel-chest", 1, -5 }, { "steel-chest", 1, -6 },
            { "steel-chest", 3, -2 }, { "steel-chest", 4, -2 }, { "steel-chest", 5, -2 },
            { "steel-chest", -2, 3 }, { "steel-chest", -2, 4 }, { "steel-chest", -2, 5 },
            { "steel-chest", -4, 1 }, { "steel-chest", -5, 1 }, { "steel-chest", -6, 1 },
            { "steel-chest", -2, -4 }, { "steel-chest", -2, -5 }, { "steel-chest", -2, -6 },
            { "steel-chest", -4, -2 }, { "steel-chest", -5, -2 }, { "steel-chest", -6, -2 },
            { "medium-electric-pole", 2, 3 }, { "medium-electric-pole", 2, -4 }, { "medium-electric-pole", -3, 3 }, { "medium-electric-pole", -3, -4 },
            { "small-lamp", 2, 4 }, { "small-lamp", 2, -5 }, { "small-lamp", -3, 4 }, { "small-lamp", -3, -5 },
            { "small-lamp", 4, 2 }, { "small-lamp", 4, -3 }, { "small-lamp", -5, 2 }, { "small-lamp", -5, -3 },
            { "stone-wall", 1, 7 }, { "stone-wall", 2, 7 }, { "stone-wall", 3, 7 }, { "stone-wall", 4, 7 },
            { "stone-wall", 7, 1 }, { "stone-wall", 7, 2 }, { "stone-wall", 7, 3 }, { "stone-wall", 7, 4 },
            { "stone-wall", 1, -8 }, { "stone-wall", 2, -8 }, { "stone-wall", 3, -8 }, { "stone-wall", 4, -8 },
            { "stone-wall", 7, -2 }, { "stone-wall", 7, -3 }, { "stone-wall", 7, -4 }, { "stone-wall", 7, -5 },
            { "stone-wall", -2, 7 }, { "stone-wall", -3, 7 }, { "stone-wall", -4, 7 }, { "stone-wall", -5, 7 },
            { "stone-wall", -8, 1 }, { "stone-wall", -8, 2 }, { "stone-wall", -8, 3 }, { "stone-wall", -8, 4 },
            { "stone-wall", -2, -8 }, { "stone-wall", -3, -8 }, { "stone-wall", -4, -8 }, { "stone-wall", -5, -8 },
            { "stone-wall", -8, -2 }, { "stone-wall", -8, -3 }, { "stone-wall", -8, -4 }, { "stone-wall", -8, -5 },
        }
    },
    pattern = {
        enabled = false, --- @setting enabled Whether pattern tiles will be added to spawn
        pattern_tile = "refined-concrete", --- @setting pattern_tile The tile to be used for the pattern
        offset = { x = 0, y = 0 }, --- @setting offset The position offset to apply to pattern tiles
        locations = { --- @setting locations The location of the pattern tiles {x,y}
        }
    },
    resource_tiles = {
        enabled = false,
        resources = {
            {
                enabled = false,
                name = "iron-ore",
                amount = 4000,
                size = { 26, 27 },
                -- offset = {-64,-32}
                offset = { -64, -64 },
            },
            {
                enabled = false,
                name = "copper-ore",
                amount = 4000,
                size = { 26, 27 },
                -- offset = {-64, 0}
                offset = { 64, -64 },
            },
            {
                enabled = false,
                name = "stone",
                amount = 4000,
                size = { 22, 20 },
                -- offset = {-64, 32}
                offset = { -64, 64 },
            },
            {
                enabled = false,
                name = "coal",
                amount = 4000,
                size = { 22, 20 },
                -- offset = {-64, -64}
                offset = { 64, 64 },
            },
            {
                enabled = false,
                name = "uranium-ore",
                amount = 4000,
                size = { 22, 20 },
                -- offset = {-64, -96}
                offset = { 0, 64 },
            },
        },
    },
    resource_patches = {
        enabled = false,
        resources = {
            {
                enabled = false,
                name = "crude-oil",
                num_patches = 4,
                amount = 4000000,
                -- offset = {-80, -12},
                offset = { -12, 64 },
                -- offset_next = {0, 6}
                offset_next = { 6, 0 },
            },
        },
    },
    resource_refill_nearby = {
        enabled = false,
        range = 128,
        refill_time = 36000,
        resources_name = {
            "iron-ore",
            "copper-ore",
            "stone",
            "coal",
            "uranium-ore",
        },
        amount = { 2500, 4000 },
    },
}
