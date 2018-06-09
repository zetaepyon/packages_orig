require('os')
require('bit')
local pack   = require('pack')
local packet = require('packet')
local shared = require('shared')
local events = require('events')
local packets = require('packets')

status_effects = shared.new('status_effects')
status_effects_events = shared.new('events')

local incoming = {}

status_effects.env = {
    next = next,
}

status_effects.data = {
    player = {},
    party = {},
}

status_effects_events.gain = events.new()
status_effects_events.lost = events.new()

function symetric_difference(l1, l2)
    local gain = {}
    local lost = {}
    local k1 = 1
    local k2 = 1
    while (k1 ~= #l1+1 or k2 ~= #l2+1) do
        if (k2 == #l2+1) then
            break
        end
        if (l1[k1] == nil) then
            gain[#gain+1] = l2[k2]    
            k2 = k2 + 1    
        elseif (l2[k2] == nil) then
            lost[#lost+1] = l1[k1] 
            k1 = k1 + 1         
        elseif (l1[k1].id < l2[k2].id) then
            lost[#lost+1] = l1[k1]
            k1 = k1 + 1        
        else 
            if (l2[k2].id < l1[k1].id) then
                gain[#gain+1] = l2[k2]        
            else 
                k1 = k1 + 1
            end
            k2 = k2 + 1
        end
    end
    return gain, lost
end



incoming[0x063] = function(p)
    local temp = {}
    local packet_type = p.data:unpack('H',0x01)
    if packet_type == 9 then
        for i=1, 32 do
            local buff_id = p.data:unpack('H', 3+2 * i)
            if buff_id == 0 or buff_id == 255 then 
                temp[i] = nil
            else
                temp[i] = {
                    id = buff_id,
                    timestamp = ((p.data:unpack('I', 0x41 + 4 * i) / 60) + 501079520 + 1009810800) - os.time()
                }
            end
        end
        
        local gain, lost = symetric_difference(status_effects.data.player, temp)
        for _, status_effect in pairs(gain) do
            status_effects_events.gain:trigger(status_effect.id, status_effect.timestamp)
        end
        for _, status_effect in pairs(lost) do
            status_effects_events.lost:trigger(status_effect.id)
        end
        status_effects.data.player = temp
    end
end 

packets.incoming.register(0x076, function(p)
        local data = status_effects.data.party
        for i = 0, 4 do
            v = p.party_members[i]
            if v.id ~= 0 then
                data[i + 1] = {}
                for pos = 0, 0x1F do
                    local base_value = v.status_effects[pos]
                    local mask_index = bit.rshift((pos), 2) 
                    local mask_offset = 2 * ((pos) % 4)
                    local mask_value = bit.rshift(v.status_effect_mask[mask_index], mask_offset) % 4
                    local temp = base_value + 0x100 * mask_value
                    if temp ~= 255 then
                        data[i+1][pos] = temp
                    end
                end
            end
        end
    end)

incoming.handler = function(p)
    if p.injected then return end

    if incoming[p.id] then 
        incoming[p.id](p)     
    end
end

packet.incoming:register(incoming.handler)