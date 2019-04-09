local Roles = require 'expcore.roles'

-- Use these to adjust for ticks ie game.tick < 5*minutes
local seconds, minutes, hours = 60, 3600, 216000

local function playtime(time_required)
    return function(player)
        if player.online_time > time_required then
            return true
        end
    end
end

Roles.define_flag_trigger('is_admin',function(player,state)
    player.admin = state
end)
Roles.define_flag_trigger('is_spectator',function(player,state)
    player.spectator = state
end)
Roles.define_flag_trigger('is_jail',function(player,state)
    if player.character then
        player.character.active = not state
    end
end)

Roles.new_role('System','SYS')
:set_allow_all(true)
:set_flag('is_admin',true)
:set_flag('is_spectator',true)
:set_permission_group('Admin')

Roles.new_role('Senior Administrator','SAdmin')
:set_flag('is_admin',true)
:set_flag('is_spectator',true)
:set_permission_group('Admin')
:set_parent('Administrator')
:allow{
    'command/interface',
    'command/toggle-cheat-mode'
}

Roles.new_role('Administrator','Admin')
:set_flag('is_admin',true)
:set_flag('is_spectator',true)
:set_custom_color{r=233,g=63,b=233}
:set_permission_group('Admin')
:set_parent('Moderator')
:allow{
}

Roles.new_role('Moderator','Mod')
:set_flag('is_admin',true)
:set_flag('is_spectator',true)
:set_custom_color{r=0,g=170,b=0}
:set_permission_group('Admin')
:set_parent('Trainee')
:allow{
}

Roles.new_role('Trainee','TrMod')
:set_flag('is_admin',true)
:set_flag('is_spectator',true)
:set_custom_color{r=0,g=170,b=0}
:set_permission_group('Admin')
:set_parent('Donator')
:allow{
    'command/admin-chat',
    'command/teleport',
    'command/bring',
    'command/goto',
    'command/kill/always',
    'command/tag-clear/always',
}

Roles.new_role('Sponsor','Spon')
:set_flag('is_spectator',true)
:set_custom_color{r=247,g=246,b=54}
:set_permission_group('Trusted')
:set_parent('Pay to Win')
:allow{
}

Roles.new_role('Pay to Win','P2W')
:set_flag('is_spectator',true)
:set_custom_color{r=238,g=172,b=44}
:set_permission_group('Trusted')
:set_parent('Donator')
:allow{
}

Roles.new_role('Donator','Don')
:set_flag('is_spectator',true)
:set_custom_color{r=230,g=99,b=34}
:set_permission_group('Trusted')
:set_parent('Veteran')
:allow{
}

Roles.new_role('Partner','Part')
:set_flag('is_spectator',true)
:set_custom_color{r=140,g=120,b=200}
:set_permission_group('Trusted')
:set_parent('Veteran')
:allow{
}

Roles.new_role('Veteran','Vet')
:set_custom_color{r=140,g=120,b=200}
:set_permission_group('Trusted')
:set_parent('Member')
:allow{
}
:set_auto_promote_condition(playtime(10*hours))

Roles.new_role('Member','Mem')
:set_custom_color{r=24,g=172,b=188}
:set_permission_group('Standard')
:set_parent('Regular')
:allow{
}

Roles.new_role('Regular','Reg')
:set_custom_color{r=79,g=155,b=163}
:set_permission_group('Standard')
:set_parent('Guest')
:allow{
    'command/kill'
}
:set_auto_promote_condition(playtime(3*hours))

Roles.new_role('Guest','')
:set_custom_color{r=185,g=187,b=160}
:set_permission_group('Guest')
:allow{
    'command/me',
    'command/tag',
    'command/tag-clear',
    'command/chelp'
}

Roles.new_role('Jail')
:set_custom_color{r=50,g=50,b=50}
:set_permission_group('Restricted')
:set_block_auto_promote(true)
:allow{
}

Roles.set_root('System')
Roles.set_default('Guest')

Roles.define_role_order{
    'System',
    'Senior Administrator',
    'Administrator',
    'Moderator',
    'Trainee',
    'Sponsor',
    'Pay to Win',
    'Donator',
    'Partner',
    'Veteran',
    'Member',
    'Regular',
    'Guest',
    'Jail'
}

Roles.override_player_roles{
    Cooldude2606={'Senior Administrator','Administrator','Moderator','Member'},
    arty714={'Senior Administrator','Administrator','Moderator','Member'},
    mark9064={'Administrator','Moderator','Member'},
    Drahc_pro={'Administrator','Moderator','Member'},
    aldldl={'Sponsor','Administrator','Moderator','Member'},
}