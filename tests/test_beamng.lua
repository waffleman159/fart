-- Offline test of the BeamNG side with stand-ins for BeamNG's Lua API (no game).
-- Run from the repo root: lua5.1 tests/test_beamng.lua
package.path = 'beamng_mod/lua/?.lua;' .. package.path

local failures = 0
local function check(cond, what)
  if not cond then failures = failures + 1; print('FAIL ' .. what) end
end

-- vec3 stand-in
local V = {}
V.__index = V
function vec3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, k) return vec3(a.x * k, a.y * k, a.z * k) end
function V:normalized() local l = math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2); return vec3(self.x / l, self.y / l, self.z / l) end
function quatFromDir(d) return {dir = d} end

-- tiny JSON decoder for the flat messages the plugin sends
function jsonDecode(s)
  local t = {}
  for k, v in s:gmatch('"([%w_]+)":("?[^,}"]*"?)') do
    if v:sub(1, 1) == '"' then t[k] = v:sub(2, -2)
    elseif v == 'true' then t[k] = true elseif v == 'false' then t[k] = false
    else t[k] = tonumber(v) end
  end
  return t
end

-- BeamNG stand-ins that record what the mod does
local calls, vehicles, inbox, playerVeh = {}, {}, {}, nil
local mission = ''
local function rec(...) table.insert(calls, table.concat({...}, ' ')) end
local function newVeh(model, pos, dir)
  local v = {model = model, pos = pos, dir = dir, lua = {}, deleted = false}
  function v:getPosition() return self.pos end
  function v:getDirectionVector() return self.dir end
  function v:queueLuaCommand(c) table.insert(self.lua, c) end
  function v:delete() self.deleted = true; if playerVeh == self then playerVeh = nil end end
  table.insert(vehicles, v)
  return v
end
package.loaded['socket'] = {udp = function()
  return {setsockname = function() return 1 end, settimeout = function() end, close = function() end,
          receive = function() return table.remove(inbox, 1) end}
end}
freeroam_freeroam = {startFreeroam = function(p) rec('startFreeroam', p) end}
function getMissionFilename() return mission end
core_vehicles = {spawnNewVehicle = function(model, o)
  local v = newVeh(model, o.pos, o.rot.dir)
  if o.autoEnterVehicle then playerVeh = v end
  rec('spawn', model)
  return v
end}
be = {getPlayerVehicle = function() return playerVeh end}
function ui_message(t) rec('msg', t) end
function log() end

local data = require('ge/extensions/shadowRig/sheetData')
local ext = dofile('beamng_mod/lua/ge/extensions/shadowRig.lua')
local function has(prefix) for _, c in ipairs(calls) do if c:find(prefix, 1, true) == 1 then return true end end return false end
local function live(model) for _, v in ipairs(vehicles) do if v.model == model and not v.deleted then return v end end end
local function step(n, dt) for _ = 1, (n or 1) do ext.onUpdate(dt or 0.05) end end

ext.onExtensionLoaded()
step(5)
check(#calls == 0, 'does nothing before ATS talks')

table.insert(inbox, '{"t":"tick","spd":25.0000,"str":0.0000,"thr":0.5000,"brk":0.0000,"trl":true,"kg":18000.0000,"cargo":"Lumber","brand":"Peterbilt","cdmg":0.0000,"pause":false}')
step()
check(has('startFreeroam ' .. data.world.level_path), 'loads the highway map')

mission = data.world.level_path
playerVeh = newVeh('pickup', vec3(100, 200, 50), vec3(0, 1, 0))
local default = playerVeh
step()
local tractor, trailer = live('us_semi'), live('dryvan')
check(default.deleted, 'replaces the default car')
check(tractor ~= nil and trailer ~= nil, 'spawns tractor and trailer')
check(trailer and trailer.pos.y == 200 - data.rigs.trailer.spawn_offset_m, 'trailer behind the tractor')
local tl = tractor and table.concat(tractor.lua, '\n') or ''
check(tl:find("ai.setMode('traffic')", 1, true), 'AI keeps it in traffic lanes')
check(tl:find('ai.setSpeed(25.00)', 1, true), 'matches ATS speed 25 m/s')
check(tl:find('activateAutoCoupling', 1, true), 'couples the trailer')
check(trailer and table.concat(trailer.lua):find('local extra = 18000.0', 1, true), 'adds 18000 kg of ATS cargo')

table.insert(inbox, '{"t":"crash","kmh":82.0000,"g":3.2000,"dmg":0.0700,"why":"physics"}')
step()
local wall = live('blockwall')
check(wall ~= nil, '82 km/h -> concrete wall')
check(wall and wall.pos.y == 200 + 8, 'wall 8 m ahead')
check(wall and wall.dir.x == -1 and wall.dir.y == 0, 'wall placed across the lane')
table.insert(inbox, '{"t":"crash","kmh":20.0000,"g":1.3000,"dmg":0.0100,"why":"fine"}')
step()
check(live('barrier') ~= nil, '20 km/h -> barrier')
table.insert(inbox, '{"t":"crash","kmh":50.0000,"g":2.0000,"dmg":0.0300,"why":"physics"}')
step()
check(live('etk800') ~= nil, '50 km/h -> parked car')

step(math.ceil(data.world.obstacle_life_s / 0.05) + 2)
check(live('blockwall') == nil and live('barrier') == nil, 'obstacles cleaned up after their lifetime')
local stopped = table.concat(tractor.lua, '\n'):find('ai.setSpeed(0.00)', 1, true)
check(stopped, 'stops the shadow truck when ATS goes quiet')

table.insert(inbox, '{"t":"tick","spd":10.0000,"str":0.0000,"thr":0.5000,"brk":0.0000,"trl":true,"kg":18000.0000,"cargo":"Lumber","brand":"Peterbilt","cdmg":0.0000,"pause":false}')
table.insert(inbox, '{"t":"repair","wear":0.0000}')
step()
check(tractor.deleted and trailer.deleted, 'repair removes the wrecked rig')
step()
local tractor2 = live('us_semi')
check(tractor2 ~= nil and tractor2 ~= tractor, 'repair respawns a fresh rig')
check(tractor2 and tractor2.pos.y == 200, 'respawned where the old rig was')

table.insert(inbox, '{"t":"tick","spd":10.0000,"str":0.0000,"thr":0.5000,"brk":0.0000,"trl":false,"kg":0.0000,"cargo":"","brand":"Peterbilt","cdmg":0.0000,"pause":false}')
step(2)
check(live('dryvan') == nil and live('us_semi') ~= nil, 'trailer dropped in ATS -> bobtail shadow truck')

print(failures == 0 and 'beamng tests passed' or ('beamng tests FAILED: ' .. failures))
os.exit(failures == 0 and 0 or 1)
