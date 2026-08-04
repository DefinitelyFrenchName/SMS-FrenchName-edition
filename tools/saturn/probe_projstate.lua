-- probe_projstate.lua — dump the 214P projectile from a SAVESTATE that already
-- has it on screen, so the measurement no longer depends on driving the input.
--
-- Two states supplied by the maintainer: v0.14.1 with a clean projectile and
-- v0.14.6 with the corrupted one. That pair is the control every metric here has
-- to pass — an earlier OAM metric was retracted precisely because a vanilla
-- Neptune reproduced its numbers exactly.
--
-- STATUS: NOT WORKING. The savestates are valid and are the right input; this
-- probe fails to APPLY them.
--   * loading at the first exec of $80:8353 leaves the ROM running its attract
--     sequence — the screenshot comes back as the title screen, and OAM reads as
--     32 degenerate entries all on palette 0;
--   * deferring the load by an exec counter overshot and the run timed out.
--
-- Do not improvise this again. tools/ds_trace.lua loads savestates successfully
-- and is the reference: copy its flow exactly (it reads the file relative to the
-- traces dir and loads from the same exec hook), then change one thing at a time.
--
--   STATE=<path> TAG=<name> ROM=<matching build> tools/run.sh tools/saturn/probe_projstate.lua 200
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram = PL.ram
local STATE = os.getenv("STATE") or error("STATE=<savestate path>")
local TAG = os.getenv("TAG") or "projstate"
local LOG = assert(io.open(ENV.TRACE .. "saturn/projstate_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

local OAM = emu.memType.snesSpriteRam
local VRAM = emu.memType.snesVideoRam
local frames, done, loaded = 0, false, false

-- emu.loadSavestate takes the CONTENTS, not a path, and the probes that work do
-- it from the exec hook at $80:8353 (the input poll) rather than from endFrame.
-- Passing a path silently does nothing: OAM then reads all zeros, every entry
-- looks "visible" at y=0, and the run reports 128 sprites — which is what the
-- first version of this probe did.
-- Load AFTER boot has settled. Loading at the first exec left the ROM running
-- its attract sequence — the screenshot came back as the title screen, not the
-- match — so the state was not being applied that early.
local boot = 0
emu.addMemoryCallback(function()
  boot = boot + 1
  if loaded or boot < 40000 then return end
  local f = io.open(STATE, "rb")
  if not f then log("cannot open " .. STATE); emu.stop(1); return end
  local ss = f:read("*a"); f:close()
  local ok, err = pcall(emu.loadSavestate, ss)
  log(string.format("loadSavestate: ok=%s err=%s bytes=%d", tostring(ok), tostring(err), #ss))
  loaded = true; frames = 0
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1
  -- 6 frames after the load was too soon: the screenshot came out black and
  -- OAM read as 32 degenerate entries. Give the emulator time to resume
  -- rendering before believing anything it reports.
  if not loaded or frames < 90 or done then return end
  done = true

  local shot = io.open(ENV.TRACE .. "saturn/projstate_" .. TAG .. ".png", "wb")
  if shot then shot:write(emu.takeScreenshot()); shot:close() end

  log(string.format("state=%s", STATE))
  for _, slot in ipairs({ 0x1100, 0x1180 }) do
    local id = ram(slot)
    if id ~= 0 then
      local b = {}
      for o = 0, 0x2F do b[#b + 1] = string.format("%02X", ram(slot + o)) end
      log(string.format("proj slot $%04X id=$%02X", slot, id))
      log("   +00: " .. table.concat(b, " "))
    end
  end

  -- every visible sprite, with the ink state of the tile it points at
  local rows = {}
  for i = 0, 127 do
    local o = i * 4
    local y = emu.read(o + 1, OAM) or 0
    if y < 0xE0 then
      local x = emu.read(o, OAM) or 0
      local t = emu.read(o + 2, OAM) or 0
      local a = emu.read(o + 3, OAM) or 0
      local tile = t | ((a & 1) << 8)
      local pal = (a >> 1) & 7
      local base = tile * 32
      local nz = 0
      for k = 0, 31 do if (emu.read(base + k, VRAM) or 0) ~= 0 then nz = nz + 1 end end
      rows[#rows + 1] = string.format("oam%-3d x=%3d y=%3d tile=$%03X pal=%d attr=$%02X nzbytes=%2d",
        i, x, y, tile, pal, a, nz)
    end
  end
  log(string.format("visible sprites: %d", #rows))
  for _, r in ipairs(rows) do log("  " .. r) end
  emu.stop(0)
end, emu.eventType.endFrame)
