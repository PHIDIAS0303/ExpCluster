--- Config file for the compliatrons including where they spawn and what messages they show
-- @config Compilatron

return {
    message_cycle = 60 * 15, --- @setting message_cycle 15 seconds default, how often (in ticks) the messages will cycle
    locations = { --- @setting locations defines the spawn locations for all compilatrons
        ["Spawn"] = { x = 0, y = 0 },
    },
    messages = { --- @setting messages the messages that each one will say, must be same name as its location
        ["Spawn"] = {
            { "info.website" },
            { "info.cloud" },
            { "info.github" },
            { "info.graph" },
            { "info.read-readme" },
            { "info.softmod" },
            { "info.custom-commands" },
            { "info.lhd" },
        },
    },
}
