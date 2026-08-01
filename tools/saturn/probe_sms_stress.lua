
-- probe_sms_stress.lua — CRASH HUNT: Saturn vs an opponent, thousands of
-- frames of pseudo-random inputs (both players), watching for a wedge:
-- act/pose frozen while the engine "runs", PC parked, or the object update
-- ceasing. On detection, dump the last N frames of state + a screenshot.
-- SEED env picks the input stream; MOVES biases toward specials.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local SEED = tonumber(os.getenv("SEED") or "1")
local MIRROR = os.getenv("MIRROR") == "1"
local VERBOSE = os.getenv("VERBOSE") == "1"
local VLO = tonumber(os.getenv("VLO") or "0")
local VHI = tonumber(os.getenv("VHI") or "99999")
local LOG = assert(io.open(ENV.TRACE .. "saturn/stress_" .. SEED .. (MIRROR and "m" or "") .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
-- xorshift so runs are reproducible per seed
local rng = SEED * 2654435761 % 4294967296
local function rnd(n)
  rng = rng ~ ((rng << 13) & 0xFFFFFFFF); rng = rng ~ (rng >> 17)
  rng = rng ~ ((rng << 5) & 0xFFFFFFFF); rng = rng % 4294967296
  return rng % n
end
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

-- motion scripts: qcf+P, qcb+P, 632+K (air), 412364+HP, throws, normals
local SEQ = {
  {{down=true},{down=true,right=true},{right=true},{right=true,y=true}},          -- qcf LP
  {{down=true},{down=true,right=true},{right=true},{right=true,x=true}},          -- qcf HP
  {{down=true},{down=true,left=true},{left=true},{left=true,y=true}},             -- qcb LP
  {{down=true},{down=true,left=true},{left=true},{left=true,x=true}},             -- qcb HP
  {{up=true},{right=true},{down=true,right=true},{down=true},{down=true,b=true}}, -- j.632K
  {{up=true},{right=true},{down=true,right=true},{down=true},{down=true,a=true}}, -- j.632HK
  {{left=true},{down=true,left=true},{down=true},{down=true,right=true},{right=true},{left=true},{left=true,x=true}}, -- desperation
  {{right=true,x=true}},                                                          -- 6HP throw
  {{y=true}}, {{x=true}}, {{b=true}}, {{a=true}},                                 -- normals
  {{down=true,y=true}}, {{down=true,a=true}},                                     -- crouch
  {{up=true},{up=true,a=true}},                                                   -- jump attack
}
local p1seq, p1i, p1hold = nil, 1, 0
local p2seq, p2i, p2hold = nil, 1, 0
local buttons1, buttons2 = {}, {}
emu.addEventCallback(function()
  emu.setInput(PL.pad(buttons1), 0, 0); emu.setInput(PL.pad(buttons2), 0, 1)
end, emu.eventType.inputPolled)

local lastact, stuck, lastposechange = -1, 0, 0
local hist = {}
local vaddr, dmaflag = 0, 0
-- VRAM integrity watchdog: regions the game does NOT rewrite mid-match
-- (BG/HUD tiles + tilemaps). Cel windows $6000-$73FF and the HUD counters are
-- excluded. A change here == the screen-wide corruption the maintainer sees.
local VRSNAP, vrbad = nil, 0
local function vrsample()
  local V = emu.memType.snesVideoRam
  local t2 = {}
  for a = 0x0000, 0x5FFF, 0x40 do t2[#t2+1] = emu.read(a, V) end
  for a = 0x7400, 0xFFFF, 0x40 do t2[#t2+1] = emu.read(a, V) end
  return t2
end
for _, b in ipairs({0x002116, 0x802116}) do
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0xFF00) | (v or 0) end,
    emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v) vaddr = (vaddr & 0x00FF) | ((v or 0) << 8) end,
    emu.callbackType.write, b + 1, b + 1, emu.cpuType.snes, emu.memType.snesMemory)
end
local REG = emu.memType.snesMemory
local function reg(a) return emu.read(0x800000 + a, REG) end
for _, b in ipairs({0x00420B, 0x80420B}) do
  emu.addMemoryCallback(function(addr, value)
    if (value or 0) == 0 or t < 90 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        if reg(c + 1) == 0x18 or reg(c + 1) == 0x19 then
          local bank, len = reg(c + 4), reg(c+5) + 256*reg(c+6)
          local ok = (vaddr >= 0x6000 and vaddr < 0x7400) or (vaddr >= 0x1100 and vaddr < 0x1200) or vaddr == 0
          local bok = (bank >= 0x7E) or (bank >= 0xC0)
          if (not ok) or (not bok) or len > 0x4000 then
            dmaflag = dmaflag + 1
            if dmaflag <= 8 then
              log(string.format("t=%d SUSPECT DMA VRAM %04X <- %02X:%04X len %04X p1act=%02X p2act=%02X",
                t, vaddr, bank, reg(c+2) + 256*reg(c+3), len, ram(0x1001), ram(0x1081)))
            end
          end
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 and os.getenv("VANILLA") == "1" then
    -- calibration mode: no transform, same input stream
  elseif t == 60 then
    wr(0x1000, 0x1C)                                  -- P1 Saturn
    for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1000 + o, 0) end
    if MIRROR then
      wr(0x1080, 0x1C)                                -- P2 Saturn too (mirror)
      for _, o in ipairs({0x01,0x02,0x04,0x05,0x06,0x07}) do wr(0x1080 + o, 0) end
    end
  end
  -- corner/proximity churn: shove players around so specials fire at walls,
  -- point blank, and max range
  if t % 300 == 0 then
    local mode = rnd(4)
    if mode == 0 then wr(0x1021, 0x10); wr(0x1022, 0x00); wr(0x10A1, 0x20); wr(0x10A2, 0x00)
    elseif mode == 1 then wr(0x1021, 0xE0); wr(0x1022, 0x01); wr(0x10A1, 0xF0); wr(0x10A2, 0x01)
    elseif mode == 2 then wr(0x1021, 0x80); wr(0x1022, 0x00); wr(0x10A1, 0x88); wr(0x10A2, 0x00)
    end
  end
  if t < 90 then return end
  -- refill HP so rounds don't end; low HP window enables desperation
  -- refill ONLY when both players are in neutral-ish acts and no projectile is
  -- live: poking HP during a KO/round-end deadlocks the engine (harness
  -- artifact, not a game bug — cost me a false positive once)
  if t % 240 == 0 and ram(0x1001) < 0x10 and ram(0x1081) < 0x10
     and ram(0x1100) == 0 and ram(0x1180) == 0 then
    wr(0x1049, (rnd(2) == 0) and 0x60 or 0x14); wr(0x10C9, 0x60)
  end
  -- P1 input stream
  if p1hold > 0 then p1hold = p1hold - 1
  else
    if p1seq and p1i <= #p1seq then
      buttons1 = p1seq[p1i]; p1i = p1i + 1; p1hold = 2
    else
      p1seq = SEQ[rnd(#SEQ) + 1]; p1i = 1; buttons1 = {}; p1hold = rnd(10)
    end
  end
  if p2hold > 0 then p2hold = p2hold - 1
  else
    if MIRROR then
      if p2seq and p2i <= #p2seq then
        buttons2 = p2seq[p2i]; p2i = p2i + 1; p2hold = 2
      else
        p2seq = SEQ[rnd(#SEQ) + 1]; p2i = 1; buttons2 = {}; p2hold = rnd(12)
      end
    else
      p2hold = rnd(20)
      local r = rnd(6)
      buttons2 = (r == 0) and {left=true} or (r == 1) and {right=true}
        or (r == 2) and {down=true} or (r == 3) and {y=true} or {}
    end
  end
  -- wedge detection
  local a, p = ram(0x1001), ram(0x1005)
  hist[#hist + 1] = string.format(
    "t=%d P1 act=%02X st=%02X pose=%02X f16=%02X f76=%02X | P2 act=%02X st=%02X pose=%02X"
    .. " | projA id=%02X act=%02X | projB id=%02X act=%02X | hp=%d/%d",
    t, a, ram(0x1002), p, ram(0x1016), ram(0x1076),
    ram(0x1081), ram(0x1082), ram(0x1085),
    ram(0x1100), ram(0x1101), ram(0x1180), ram(0x1181),
    ram(0x1049), ram(0x10C9))
  if #hist > 60 then table.remove(hist, 1) end
  if VERBOSE and t >= VLO and t <= VHI then log(hist[#hist]) end
  -- round-end states are legitimately static (win pose 0x24, downed 0x1F/0x21,
  -- and any KO where a player is at 0 HP): don't count them as a wedge
  local roundend = (a == 0x24 or a == 0x1F or a == 0x21 or a == 0x1A or a == 0x1E)
    or (ram(0x1081) == 0x24 or ram(0x1081) == 0x1F or ram(0x1081) == 0x21)
    or ram(0x1049) == 0 or ram(0x10C9) == 0
  if p ~= lastact or roundend then lastact = p; lastposechange = t end
  if t == 150 then VRSNAP = vrsample() end
  if VRSNAP and t > 150 and t % 30 == 0 and vrbad == 0 then
    local cur = vrsample()
    local diffs = 0
    for i = 1, #VRSNAP do if cur[i] ~= VRSNAP[i] then diffs = diffs + 1 end end
    if diffs > 8 then
      vrbad = diffs
      log(string.format("VRAM CORRUPTION at t=%d: %d/%d sampled bytes changed", t, diffs, #VRSNAP))
      for _, l in ipairs(hist) do log("  " .. l) end
      local png = emu.takeScreenshot()
      local f = assert(io.open(ENV.TRACE .. "saturn/corrupt_" .. SEED .. (MIRROR and "m" or "") .. ".png", "wb"))
      f:write(png); f:close()
      emu.stop(1)
    end
  end
  if ram(0x1000) == 0 and ram(0x1080) == 0 then
    log(string.format("MATCH ENDED CLEANLY at t=%d — no wedge; suspect DMAs: %d", t, dmaflag))
    emu.stop(0)
  end
  if os.getenv("VANILLA") ~= "1" and ram(0x1000) ~= 0x1C and ram(0x1000) ~= 0 then
    log(string.format("P1 ID CHANGED at t=%d (id=%02X)", t, ram(0x1000)))
    for _, l in ipairs(hist) do log("  " .. l) end
    emu.stop(1)
  end
  if t - lastposechange > 240 then
    log("WEDGE SUSPECTED at t=" .. t)
    for _, l in ipairs(hist) do log("  " .. l) end
    local ok, st = pcall(emu.getState)
    log(string.format("PC=%02X:%04X", st and st["cpu.k"] or -1, st and st["cpu.pc"] or -1))
    local png = emu.takeScreenshot()
    local f = assert(io.open(ENV.TRACE .. "saturn/stress_" .. SEED .. (MIRROR and "m" or "") .. ".png", "wb"))
    f:write(png); f:close()
    emu.stop(1)
  end
  if t > 7000 then log("SURVIVED " .. t .. " frames; suspect DMAs: " .. dmaflag); emu.stop(0) end
end, emu.eventType.endFrame)
print("stress loaded seed=" .. SEED)
