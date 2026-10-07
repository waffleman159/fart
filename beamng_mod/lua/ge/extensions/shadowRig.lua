-- Shadow Rig - BeamNG.drive side.
-- Listens for the ATS plugin on localhost UDP, keeps a shadow T-Series + trailer driving at the
-- player's ATS speed with the ATS cargo weight, and when ATS reports a crash, puts an obstacle
-- sized from the impact in front of it. All numbers come from sheets/ via sheetData.lua.
local M = {}

local data = require('ge/extensions/shadowRig/sheetData')
local api = require('ge/extensions/shadowRig/api')

local udp
local clock = 0
local lastTickAt = -1
local tick              -- latest 'tick' message from ATS
local levelRequested = false
local rig = {tractor = nil, trailer = nil, hasTrailer = false, cargoKg = -1, sentMps = -1, sentAt = -1}
local obstacles = {}    -- {veh = ..., expires = ...}

local function obstacleFor(kmh)
  for _, o in ipairs(data.obstacles) do
    if kmh >= o.min_kmh and kmh < o.max_kmh then return o end
  end
  return data.obstacles[#data.obstacles]
end

local function clearObstacles()
  for _, o in ipairs(obstacles) do api.delete_vehicle(o.veh) end
  obstacles = {}
end

local function despawnRig()
  if rig.tractor then rig.lastPos, rig.lastDir = api.vehicle_pose(rig.tractor) end
  api.delete_vehicle(rig.trailer)
  api.delete_vehicle(rig.tractor)
  rig.tractor, rig.trailer, rig.cargoKg, rig.sentMps = nil, nil, -1, -1
end

local function spawnRig()
  local pos, dir
  local current = api.player_vehicle()
  if current then
    pos, dir = api.vehicle_pose(current)
    api.delete_vehicle(current)    -- the shadow tractor takes the player's place (camera follows it)
  elseif rig.lastPos then
    pos, dir = rig.lastPos, rig.lastDir   -- respawn where the last rig was (after a repair)
  else
    return false                   -- level still settling; try again next frame
  end
  local t = data.rigs.tractor
  rig.tractor = api.spawn_vehicle(t.beamng_model, t.beamng_config, pos - dir * t.spawn_offset_m, dir, true)
  rig.hasTrailer = tick and tick.trl or false
  if rig.hasTrailer then
    local tr = data.rigs.trailer
    rig.trailer = api.spawn_vehicle(tr.beamng_model, tr.beamng_config, pos - dir * tr.spawn_offset_m, dir, false)
    api.couple_trailer(rig.tractor)
  end
  api.ai_traffic(rig.tractor)
  api.message(string.format('Shadow Rig: following your %s', (tick and tick.brand ~= '' and tick.brand) or 'truck'), 5)
  return true
end

local function onCrash(msg)
  if not rig.tractor then return end
  local o = obstacleFor(msg.kmh or 0)
  local pos, dir = api.vehicle_pose(rig.tractor)
  local across = vec3(-dir.y, dir.x, 0)     -- obstacles are placed across the lane
  local veh = api.spawn_vehicle(o.beamng_model, o.beamng_config, pos + dir * o.ahead_m, across, false)
  if veh then table.insert(obstacles, {veh = veh, expires = clock + data.world.obstacle_life_s}) end
  api.message(string.format('ATS crash at %d km/h, %.1f g -> %s', math.floor(msg.kmh or 0), msg.g or 0, o.label), 6)
end

local function onRepair()
  clearObstacles()
  despawnRig()
  api.message('Truck repaired in ATS - shadow rig respawning', 4)
end

local function handle(msg)
  if type(msg) ~= 'table' then return end
  if msg.t == 'tick' then
    tick, lastTickAt = msg, clock
  elseif msg.t == 'crash' then
    onCrash(msg)
  elseif msg.t == 'repair' then
    onRepair()
  end
end

local function drive()
  local live = tick and not tick.pause and (clock - lastTickAt) < data.world.stale_tick_s
  local mps = live and math.max(0, tick.spd or 0) or 0
  -- re-send when the target changes noticeably, and at least once a second
  if math.abs(mps - rig.sentMps) > 0.3 or clock - rig.sentAt > 1 then
    api.ai_speed(rig.tractor, mps)
    rig.sentMps, rig.sentAt = mps, clock
  end
  if tick and rig.trailer and tick.kg ~= rig.cargoKg then
    api.add_cargo_mass(rig.trailer, tick.kg or 0)
    rig.cargoKg = tick.kg
    if (tick.kg or 0) > 0 then
      api.message(string.format('Shadow load: %s, %d lb', tick.cargo ~= '' and tick.cargo or 'cargo', math.floor(tick.kg * 2.20462)), 4)
    end
  end
end

local function onUpdate(dtReal)
  clock = clock + dtReal
  if udp then
    for _ = 1, 64 do
      local text = udp:receive()
      if not text then break end
      handle(api.json_decode(text))
    end
  end
  if not tick then return end      -- ATS not talking yet

  if not api.level_loaded() then
    if not levelRequested then
      levelRequested = true
      api.start_level(data.world.level_path)
    end
    return
  end

  if tick.trl ~= nil and rig.tractor and tick.trl ~= rig.hasTrailer then despawnRig() end
  if not rig.tractor then
    if not spawnRig() then return end
  end
  drive()

  for i = #obstacles, 1, -1 do
    if clock > obstacles[i].expires then
      api.delete_vehicle(obstacles[i].veh)
      table.remove(obstacles, i)
    end
  end
end

local function onExtensionLoaded()
  local ok, sockOrErr = pcall(api.udp_open, data.rules.udp_port)
  if ok then
    udp = sockOrErr
    api.log('I', 'listening for ATS on 127.0.0.1:' .. tostring(data.rules.udp_port))
  else
    api.log('E', 'could not open UDP port: ' .. tostring(sockOrErr))
  end
end

local function onExtensionUnloaded()
  if udp then udp:close() end
  udp = nil
end

local function onClientEndMission()
  rig.tractor, rig.trailer, rig.cargoKg, rig.sentMps, rig.lastPos, rig.lastDir = nil, nil, -1, -1, nil, nil
  obstacles = {}
  levelRequested = false
end

M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onClientEndMission = onClientEndMission

return M
