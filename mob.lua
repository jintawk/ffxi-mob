--[[
Copyright (c) 2014, Matt McGinty
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
    * Neither the name of <addon name> nor the
    names of its contributors may be used to endorse or promote products
    derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name = 'mob'
_addon.version = '0.00'
_addon.author = 'Jinvoco/Jintawk (Carbuncle)'
_addon.command = 'sc'

require('actions')
require('tables')
require('sets')
res = require('resources')
require "const"
require "gui"
require "List"

BLUE = 207
debug = false
engaged = false

currentMob = nil

function log(msg)
    windower.add_to_chat(BLUE, 'mob -> ' .. msg)
end

function log_d(msg)
    if debug then
        log("[dbg] " .. msg)
    end
end

--[[
    Event: Addon loaded
]]
windower.register_event('load', function()
    log('Addon loaded')
end)

--[[
    Fires when an action event is received from the game.
    Checks if the action is a valid weaponskill performed by
    another player targeting the same mob as the user. If 
    checks are passed closing weaponskills are then searched for.
    Parameters:
    action:   Action received
]]
windower.register_event('action', function(act)
    if type(act) ~= 'table' then return end

    if act == nil then 
        log_d('act is nil! ')
        return 
    end

    if currentMob == nil or act.actor_id ~= currentMob.id then return end

    local actionId = act.targets[1].actions[1].param
    local skill = nil

    -- Finish WS
    if act.category == 3 then
        skill = res.weapon_skills[act.param]
    -- Start WS
    elseif act.category == 7 then
        skill = res.monster_abilities[actionId]
    -- Finish spell
    elseif act.category == 4 then
        skill = res.spells[act.param]
    -- Start spell
    elseif act.category == 8 then
        skill = res.spells[actionId]
    -- Finished TP move
    elseif act.category == 11 then
        skill = res.monster_abilities[act.param]
    end

    if skill ~= nil then
        log_d("skill = " .. skill.en)
    else
        log_d("nil skill")
    end

    if skill == nil then return end

    log_d('action cat = ' .. act.category)    

    -- 7 = start WS/TP move casting(24931), or failure(28787)
    -- 8  = start casting(24931), or interrupted(28787)
    if act.category == 7 or act.category == 8 then                 

        if currentMob.move_history == nil then
            currentMob.move_history = List.new()
        end


        if act.param == CAST_PARAM.INITIALISING then
            local move = { id = skill.id, name = skill.en, casting = true, interrupted = false, start = os.time() }
            currentMob.move_history:push_back(move)              
        elseif act.param == CAST_PARAM.FAILURE then
            if currentMob.move_history == nil then return end

            local idx = currentMob.move_history:find_by_id(skill.id)

            if idx == -1 then
                log("mob error, can't find move in cast intterupt logic")
                return
            end

            currentMob.move_history.items[idx].casting = false
            currentMob.move_history.items[idx].interrupted = true
        else
            log("unknown param: " .. act.param)
        end
    elseif act.category == 3 or act.category == 4 or act.category == 11 then
        if currentMob.move_history == nil then return end

        local idx = currentMob.move_history:find_by_id(skill.id)

        if idx == -1 then
            log("mob error, can't find move in cast finish logic")
            return
        end

        currentMob.move_history.items[idx].casting = false
        currentMob.move_history.items[idx].interrupted = false
    end

    draw_gui(currentMob)
end)

function table.val_to_str ( v )
    if "string" == type( v ) then
      v = string.gsub( v, "\n", "\\n" )
      if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
        return "'" .. v .. "'"
      end
      return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
    else
      return "table" == type( v ) and table.tostring( v ) or
        tostring( v )
    end
  end
  
  function table.key_to_str ( k )
    if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
      return k
    else
      return "[" .. table.val_to_str( k ) .. "]"
    end
  end
  
  function table.tostring( tbl )
    local result, done = {}, {}
    for k, v in ipairs( tbl ) do
      table.insert( result, table.val_to_str( v ) )
      done[ k ] = true
    end
    for k, v in pairs( tbl ) do
      if not done[ k ] then
        table.insert( result,
          table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
      end
    end
    return "{" .. table.concat( result, "," ) .. "}"
  end

--[[
	Event: Status has changed Engaged/Not Enaged
]]
windower.register_event('status change', function(new, old)
    if new == STATUS.ENGAGED then
    	log_d('New status: Engaged')
        engaged = true
    elseif new == STATUS.NOT_ENGAGED then
    	log_d('New status: Not Engaged')
        engaged = false
    end
end)

--[[
	Event: Status has changed Engaged/Not Enaged
]]
windower.register_event('target change', function(new, old)
    currentMob = nil
    clear_gui()

    local newCurrentMob = windower.ffxi.get_mob_by_target('t') or nil

    -- If no current mob then do nothing as we're not interested in others
    -- Otherwise record the ID of the mob we're fighting
    if newCurrentMob == nil or newCurrentMob.is_npc == false or newCurrentMob.valid_target == false then 
        log_d('Target no valid')        
        return
    end

    currentMob = newCurrentMob
    draw_gui(currentMob)       
    -- log_d('Target mob id[' .. currentMob.id .. ' npc [' ..  string.format("%s", tostring(currentMob.is_npc))  ..'] valid[' .. string.format("%s", tostring(currentMob.valid_target)) .. ']')
    
end)

windower.register_event('time change', function(new, old)
    if currentMob == nil or currentMob.hpp <= 0 then 
        clear_gui()
        return 
    end

    local updatedCurrentMob = windower.ffxi.get_mob_by_id(currentMob.id)

    currentMob.hpp = updatedCurrentMob.hpp

    draw_gui(currentMob)
end)

