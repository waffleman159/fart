-- One function per row of sheets/beamng_hooks.json (tools/gen.py checks the two match).
-- Every BeamNG call the mod makes goes through here, so each can be verified in one place.
local A = {}

function A.udp_open(port)
  local socket = require('socket')
  local udp = socket.udp()
  assert(udp:setsockname('127.0.0.1', port))
  udp:settimeout(0)
  return udp
end

function A.json_decode(text)
  local ok, v = pcall(jsonDecode, text)
  if ok then return v end
  return nil
end

function A.start_level(levelPath)
  freeroam_freeroam.startFreeroam(levelPath)
end

function A.level_loaded()
  local f = getMissionFilename and getMissionFilename() or ''
  return f ~= nil and f ~= ''
end

function A.spawn_vehicle(model, config, pos, dir, enter)
  local opts = {
    pos = pos,
    rot = quatFromDir(dir, vec3(0, 0, 1)),
    autoEnterVehicle = enter and true or false,
  }
  if config ~= 'default' then opts.config = config end
  return core_vehicles.spawnNewVehicle(model, opts)
end

function A.player_vehicle()
  return be:getPlayerVehicle(0)
end

function A.vehicle_pose(veh)
  local dir = veh:getDirectionVector()
  return veh:getPosition(), vec3(dir.x, dir.y, 0):normalized()
end

function A.delete_vehicle(veh)
  if veh then veh:delete() end
end

function A.ai_traffic(veh)
  veh:queueLuaCommand("ai.setMode('traffic'); ai.driveInLane('on')")
end

function A.ai_speed(veh, mps)
  veh:queueLuaCommand(string.format("ai.setSpeedMode('set'); ai.setSpeed(%.2f)", mps))
end

function A.couple_trailer(veh)
  veh:queueLuaCommand("beamstate.activateAutoCoupling()")
end

-- Spreads extraKg evenly over the trailer's nodes, on top of their original weight.
function A.add_cargo_mass(veh, extraKg)
  veh:queueLuaCommand(string.format([[
    local extra = %.1f
    if not shadowRigBaseMass then
      shadowRigBaseMass = {}
      for _, n in pairs(v.data.nodes) do shadowRigBaseMass[n.cid] = obj:getNodeMass(n.cid) end
    end
    local count = 0
    for _ in pairs(shadowRigBaseMass) do count = count + 1 end
    for cid, base in pairs(shadowRigBaseMass) do obj:setNodeMass(cid, base + extra / math.max(count, 1)) end
  ]], extraKg))
end

function A.log(level, text)
  log(level, 'shadowRig', text)
end

function A.message(text, ttl)
  ui_message(text, ttl or 5, 'shadowRig')
end

return A
