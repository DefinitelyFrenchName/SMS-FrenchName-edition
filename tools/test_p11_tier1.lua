-- test_p11_tier1.lua (patch 11): Tier-1 feature suite on the PATCHED ROM (tier1 stage).
-- 10 phases, each from a fresh traces/training_p11.mss load; settings poked at $7F:F02x
-- (menu phase drives the real L+R menu). Output: traces/p11_tier1.txt; exit 0 = all pass.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_tier1.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local PL = ENV.dofile("probelib.lua")   -- shared emulator-access helpers (#34)
local WRAM = PL.WRAM
local ram, wr = PL.ram, PL.wr
local function st(off) return ram(0x1F000 + off) end
local function stw(off, v) wr(0x1F000 + off, v) end
local function vword(w) return emu.read(w * 2, emu.memType.snesVideoRam) + 256 * emu.read(w * 2 + 1, emu.memType.snesVideoRam) end
local fails, checks = 0, 0
local EXPECTED_CHECKS = 62  -- issue #7: a check that never runs must fail the suite
local function check(name, ok, detail)
  checks = checks + 1
  log((ok and "PASS " or "FAIL ") .. name .. (detail and (" " .. detail) or ""))
  if not ok then fails = fails + 1 end
end

-- font order: patch 10's DERIVED 14 letters (issue #42: shared CHR prefix, no drift),
-- then p11's extras M,Y + BDFJKOW + > + #
local ORDER = { }
for i, c in ipairs({ "G","C","R","E","V","S","A","L","P","U","N","I","H","T","M","Y",
                     "B","D","F","J","K","O","W",">","#" }) do ORDER[c] = 0xC7 + i - 1 end
local function tw(c) return 0x2C00 + ORDER[c] end
local function rowaddr(i) return 0x1000 + (4 + i) * 32 + 3 end

local function p2close(gap)
  local p1x = ram(0x1021) + 256 * ram(0x1022)
  local x = p1x + (gap or 16)
  wr(0x10A1, x % 256); wr(0x10A2, math.floor(x / 256))
end
local function mode5()
  wr(0x8D, 5); stw(0x04, 0xA5)
end

local pulse = {}
local saw = {}

local PHASES = {
  { name = "guard-all", dur = 90,
    tick = function(pt)
      if pt == 5 then stw(0x21, 1) end
      if pt == 10 then p2close() end
      if pt >= 30 and pt <= 31 then pulse[0] = { down = true, y = true } elseif pt == 32 then pulse[0] = nil end
      if ram(0x1081) == 0x0D then saw.preblock = true end
      if ram(0x1081) == 0x0F then saw.blockstun = true end
    end,
    fin = function()
      check("guard-preblock", saw.preblock)
      check("guard-blockstun", saw.blockstun)
      check("guard-nohp", ram(0x10C9) == 0x60, string.format("hp=%02X", ram(0x10C9)))
    end },
  { name = "guard-afterhit", dur = 160,
    tick = function(pt)
      if pt == 5 then stw(0x21, 2) end
      if pt == 10 then p2close() end
      if pt >= 24 and pt <= 25 then pulse[0] = { down = true, y = true } elseif pt == 26 then pulse[0] = nil end
      if pt >= 90 and pt <= 91 then pulse[0] = { down = true, y = true } elseif pt == 92 then pulse[0] = nil end
      if pt == 85 then p2close() end
      local a = ram(0x1081)
      if pt < 60 and a >= 0x10 and a <= 0x16 then saw.firsthit = true end
      if pt > 90 and a == 0x0F then saw.thenblock = true end
      if pt > 90 and a >= 0x10 and a <= 0x16 then saw.secondhit = true end
    end,
    fin = function()
      check("afterhit-first-connects", saw.firsthit)
      check("afterhit-then-blocks", saw.thenblock and not saw.secondhit,
        string.format("block=%s hit2=%s", tostring(saw.thenblock), tostring(saw.secondhit)))
    end },
  { name = "pose-crouch", dur = 40,
    tick = function(pt) if pt == 5 then stw(0x20, 1) end end,
    fin = function() check("crouch", ram(0x1081) == 0x03, string.format("act=%02X", ram(0x1081))) end },
  { name = "pose-jump", dur = 90,
    tick = function(pt)
      if pt == 5 then stw(0x20, 2) end
      local a = ram(0x1081)
      if a >= 0x05 and a <= 0x09 then saw.air = true end
    end,
    fin = function() check("jump", saw.air) end },
  { name = "tech-mash", dur = 160,
    tick = function(pt)
      if pt == 5 then stw(0x23, 1) end
      if pt == 10 then p2close(14) end
      if pt >= 24 and pt <= 27 then pulse[0] = { right = true, x = true } elseif pt == 28 then pulse[0] = nil end
      local a = ram(0x1081)
      if a == 0x1B or a == 0x1C then saw.held = true end
      if a == 0x23 then saw.tech = true end
      if a == 0x1D then saw.thrown = true end
      if saw.held and not saw.mash then saw.mash = ram(0x1056) end
      if saw.held then local m = ram(0x1056); if m > (saw.mash or 0) then saw.mash = m end end
    end,
    fin = function()
      check("tech-grabbed", saw.held, "throw never connected?")
      check("tech-mashcount", (saw.mash or 0) >= 2, string.format("mash=%s", tostring(saw.mash)))
      check("tech-teched", saw.tech and not saw.thrown,
        string.format("tech=%s thrown=%s", tostring(saw.tech), tostring(saw.thrown)))
    end },
  { name = "wake-jab", dur = 220,
    tick = function(pt)
      if pt == 5 then stw(0x22, 1) end
      if pt == 10 then p2close() end
      if pt >= 24 and pt <= 25 then pulse[0] = { down = true, a = true } elseif pt == 26 then pulse[0] = nil end
      local a = ram(0x1081)
      if a >= 0x19 and a <= 0x20 then saw.kd = true end
      if saw.kd and not saw.wakeT and (a <= 0x04 or a == 0x0C or a == 0x0D or a == 0x21) then saw.wakeT = pt end
      if saw.wakeT and pt <= saw.wakeT + 10 and a >= 0x2B then saw.attack = a end
    end,
    fin = function()
      check("wakejab-kd", saw.kd)
      check("wakejab-fired", saw.attack ~= nil, string.format("act=%s wakeT=%s", tostring(saw.attack), tostring(saw.wakeT)))
    end },
  { name = "wake-dash", dur = 220,
    tick = function(pt)
      if pt == 5 then stw(0x22, 3) end
      if pt == 10 then p2close() end
      if pt >= 24 and pt <= 25 then pulse[0] = { down = true, a = true } elseif pt == 26 then pulse[0] = nil end
      local a = ram(0x1081)
      if a >= 0x19 and a <= 0x20 then saw.kd = true end
      if saw.kd and a == 0x26 then saw.bd = true end
    end,
    fin = function()
      check("wakedash-kd", saw.kd)
      check("wakedash-fired", saw.bd)
    end },
  { name = "regen", dur = 300,
    tick = function(pt)
      if pt == 5 then stw(0x25, 1); mode5() end
      if pt == 10 then p2close() end
      if pt >= 24 and pt <= 25 then pulse[0] = { down = true, y = true } elseif pt == 26 then pulse[0] = nil end
      if pt >= 60 and pt <= 61 then pulse[0] = { down = true, y = true } elseif pt == 62 then pulse[0] = nil end
      if pt == 100 then saw.hpAfterHits = ram(0x10C9) end
      if pt == 150 then saw.hpMid = ram(0x10C9) end
    end,
    fin = function()
      check("regen-dmg", (saw.hpAfterHits or 0x60) < 0x60, string.format("hp@100=%02X", saw.hpAfterHits or -1))
      check("regen-noearly", saw.hpMid == saw.hpAfterHits, string.format("hp@150=%02X", saw.hpMid or -1))
      check("regen-refilled", ram(0x10C9) == 0x60, string.format("hp@300=%02X", ram(0x10C9)))
    end },
  { name = "refill", dur = 320,
    tick = function(pt)
      if pt == 5 then stw(0x26, 1); mode5() end
      if pt == 10 then p2close(); wr(0x10C9, 0x01) end
      if pt >= 24 and pt <= 25 then pulse[0] = { down = true, y = true } elseif pt == 26 then pulse[0] = nil end
      local a = ram(0x1081)
      if ram(0x10C9) == 0 then saw.died = true end
      if a >= 0x19 and a <= 0x20 then saw.kd = true end
      if a == 0x1F then saw.ko = true end
      if saw.kd and pt > 60 and a == 0x00 then saw.recovered = true end
      if pt == 45 then saw.hp45 = ram(0x10C9) end
    end,
    fin = function()
      check("refill-died", saw.died or saw.kd, "lethal hit landed?")
      check("refill-refilled", saw.hp45 == 0x60, string.format("hp@45=%02X", saw.hp45 or -1))
      check("refill-noKO", not saw.ko)
      check("refill-recovered", saw.recovered)
    end },
  { name = "reset", dur = 40,
    tick = function(pt) if pt == 20 then stw(0x13, 1) end end,
    fin = function()
      local p1x = ram(0x1021) + 256 * ram(0x1022)
      local p2x = ram(0x10A1) + 256 * ram(0x10A2)
      check("reset-p1x", p1x == 0xC8, string.format("%04X", p1x))
      check("reset-p2x", p2x == 0x110, string.format("%04X", p2x))
      check("reset-acts", ram(0x1001) == 0 and ram(0x1081) == 0)
    end },
  { name = "recplay", dur = 320,
    tick = function(pt)
      if pt >= 10 and pt <= 12 then pulse[0] = { l = true, r = true } elseif pt == 13 then pulse[0] = nil end
      if pt == 50 then stw(0x27, 1) end                                     -- SET_REC=ARM
      if pt >= 55 and pt <= 57 then pulse[0] = { l = true, r = true } elseif pt == 58 then pulse[0] = nil end
      if pt == 62 then check("rec-active", st(0x42) == 1, string.format("ra=%02X", st(0x42))) end
      -- puppet script: crouch 20f then crouch-jab
      if pt >= 65 and pt <= 84 then pulse[0] = { down = true } end
      if pt >= 85 and pt <= 86 then pulse[0] = { down = true, y = true } end
      if pt == 87 then pulse[0] = nil end
      if pt == 80 then check("rec-puppet-crouch", ram(0x1081) == 0x03, string.format("p2act=%02X", ram(0x1081))) end
      if pt == 80 then check("rec-puppet-eatsP1", ram(0x1001) == 0, string.format("p1act=%02X", ram(0x1001))) end
      if pt >= 88 and pt <= 95 and ram(0x1081) >= 0x2B then saw.puppetjab = true end
      if pt == 96 then check("rec-puppet-jab", saw.puppetjab) end
      if pt >= 100 and pt <= 102 then pulse[0] = { l = true, r = true } elseif pt == 103 then pulse[0] = nil end
      if pt == 110 then
        local len = st(0x46) + 256 * st(0x47)
        check("rec-stopped", st(0x42) == 0 and len > 40 and len < 200, string.format("len=%d", len))
        stw(0x28, 2)                                                        -- SET_PLAY=LOOP
      end
      if pt >= 115 and pt <= 117 then pulse[0] = { l = true, r = true } elseif pt == 118 then pulse[0] = nil end
      if pt == 122 then check("play-active", st(0x4A) == 1, string.format("pa=%02X", st(0x4A))) end
      if pt >= 122 then
        local a = ram(0x1081)
        if a >= 0x2B and not saw.injab then saw.injab = true; saw.jabs = (saw.jabs or 0) + 1 end
        if a < 0x2B then saw.injab = false end
        if a == 0x03 then saw.playcrouch = true end
      end
    end,
    fin = function()
      check("play-crouch", saw.playcrouch)
      check("play-loops", (saw.jabs or 0) >= 2, string.format("jabs=%d", saw.jabs or 0))
    end },
  { name = "show-direct", dur = 90,
    tick = function(pt)
      if pt == 5 then stw(0x29, 1) end                                      -- SET_SHOW=1, no menu
      if pt == 60 then
        check("show-wiped", st(0x55) == 1, string.format("w=%02X", st(0x55)))
        check("show-tmwant", st(0x57) == 1, string.format("tw=%02X", st(0x57)))
      end
    end,
    fin = function() end },
  { name = "show-display", dur = 280,
    tick = function(pt)
      if pt == 5 then stw(0x29, 1); wr(0x8D, 5); stw(0x04, 0xA5) end
      if pt == 10 then p2close() end
      -- hold down+y and check the input display cells (row 19: base word $1264)
      if pt >= 60 and pt <= 70 then pulse[0] = { down = true, y = true } end
      if pt == 68 then
        check("show-inp-D", vword(0x1264 + 1) == tw("D"), string.format("%04X", vword(0x1264 + 1)))
        check("show-inp-LP", vword(0x1264 + 5) == tw("L") and vword(0x1264 + 6) == tw("P"),
          string.format("%04X %04X", vword(0x1264 + 5), vword(0x1264 + 6)))
        check("show-inp-U-blank", vword(0x1264) == 0x2000, string.format("%04X", vword(0x1264)))
      end
      if pt == 71 then pulse[0] = nil end
      if pt == 90 then
        check("show-inp-clear", vword(0x1264 + 1) == 0x2000, string.format("%04X", vword(0x1264 + 1)))
        local f = io.open(TRACE .. "p11_show.png", "wb"); f:write(emu.takeScreenshot()); f:close()
      end
      -- advantage: land a 2LP on the idle dummy, expect ~+6 settle
      if pt >= 100 and pt <= 101 then pulse[0] = { down = true, y = true } elseif pt == 102 then pulse[0] = nil end
      if pt >= 103 and st(0x5D) ~= 0 and not saw.adv then
        saw.adv = true; saw.sign = st(0x5B); saw.mag = st(0x5C)
      end
      if pt == 150 then
        -- HP readout (SHOW): mode-5 damage happened at ~100; digits must match live hp
        local hp = ram(0x10C9)
        local tens, ones = math.floor(hp / 10), hp % 10
        check("hp-readout-p2", vword(0x1296) == 0x2C50 + tens and vword(0x1297) == 0x2C50 + ones,
          string.format("hp=%d cells=%04X %04X", hp, vword(0x1296), vword(0x1297)))
      end
      if pt == 200 then
        check("adv-settled", saw.adv)
        check("adv-plus", saw.sign == 0, string.format("sign=%s", tostring(saw.sign)))
        check("adv-mag", (saw.mag or 0) >= 4 and (saw.mag or 0) <= 8, string.format("mag=%s", tostring(saw.mag)))
        check("adv-vram-A", vword(0x1276) == tw("A"), string.format("%04X", vword(0x1276)))
        check("adv-vram-digit", vword(0x1276 + 5) == 0x2C50 + (saw.mag or 0), string.format("%04X", vword(0x1276 + 5)))
      end
    end,
    fin = function() end },
  { name = "p1hp-toggle", dur = 400,
    tick = function(pt)
      if pt >= 10 and pt <= 12 then pulse[0] = { l = true, r = true } elseif pt == 13 then pulse[0] = nil end
      -- navigate to row 11 (P1 HP): 10 downs from cursor 1, paced for the 30Hz-safe edges
      local dn = math.floor((pt - 50) / 12)
      if pt >= 50 and pt < 170 and (pt - 50) % 12 < 2 and dn < 10 then pulse[0] = { down = true }
      elseif pt >= 50 and pt < 170 then pulse[0] = nil end
      if pt >= 180 and pt <= 181 then pulse[0] = { right = true } elseif pt == 182 then pulse[0] = nil end
      if pt == 200 then check("p1hp-low", ram(0x1049) == 0x17, string.format("hp=%02X cur=%d", ram(0x1049), st(0x06))) end
      if pt >= 210 and pt <= 211 then pulse[0] = { right = true } elseif pt == 212 then pulse[0] = nil end
      if pt == 230 then check("p1hp-full", ram(0x1049) == 0x60, string.format("hp=%02X", ram(0x1049))) end
      if pt >= 240 and pt <= 242 then pulse[0] = { l = true, r = true } elseif pt == 243 then pulse[0] = nil end
    end,
    fin = function() end },
  { name = "menu", dur = 300,
    tick = function(pt)
      if pt >= 10 and pt <= 12 then pulse[0] = { l = true, r = true } elseif pt == 13 then pulse[0] = nil end
      if pt == 20 then check("menu-open", st(0x05) == 1, string.format("mo=%02X", st(0x05))) end
      if pt == 48 then
        check("menu-uivis", st(0x0D) == 1, string.format("ui=%02X", st(0x0D)))
        check("menu-title", vword(rowaddr(0) + 7) == tw("T"), string.format("%04X", vword(rowaddr(0) + 7)))
        check("menu-posename", vword(rowaddr(1) + 3) == tw("P"), string.format("%04X", vword(rowaddr(1) + 3)))
        check("menu-cursor1", vword(rowaddr(1) + 1) == tw(">"), string.format("%04X", vword(rowaddr(1) + 1)))
        check("menu-standval", vword(rowaddr(1) + 10) == tw("S"), string.format("%04X", vword(rowaddr(1) + 10)))
        local f = io.open(TRACE .. "p11_menu.png", "wb"); f:write(emu.takeScreenshot()); f:close()
      end
      if pt >= 55 and pt <= 56 then pulse[0] = { down = true } elseif pt == 57 then pulse[0] = nil end
      if pt == 70 then
        check("menu-cursmove", st(0x06) == 2, string.format("cur=%02X", st(0x06)))
        check("menu-curs-old-blank", vword(rowaddr(1) + 1) == 0x2000, string.format("%04X", vword(rowaddr(1) + 1)))
        check("menu-curs-new", vword(rowaddr(2) + 1) == tw(">"), string.format("%04X", vword(rowaddr(2) + 1)))
      end
      if pt >= 75 and pt <= 76 then pulse[0] = { right = true } elseif pt == 77 then pulse[0] = nil end
      if pt == 95 then
        check("menu-guardset", st(0x21) == 1, string.format("g=%02X", st(0x21)))
        check("menu-guardval", vword(rowaddr(2) + 10) == tw("A"), string.format("%04X", vword(rowaddr(2) + 10)))
      end
      if pt >= 105 and pt <= 108 then pulse[0] = { y = true } elseif pt == 109 then pulse[0] = nil end
      if pt == 125 then check("menu-eat", ram(0x1001) == 0, string.format("p1act=%02X", ram(0x1001))) end
      if pt >= 135 and pt <= 137 then pulse[0] = { start = true } elseif pt == 138 then pulse[0] = nil end
      if pt == 155 then check("menu-eatstart", ram(0x1FA) == 0x80, string.format("f01FA=%02X", ram(0x1FA))) end
      if pt >= 165 and pt <= 167 then pulse[0] = { l = true, r = true } elseif pt == 168 then pulse[0] = nil end
      if pt == 180 then check("menu-closed", st(0x05) == 0 and st(0x0D) == 0,
        string.format("mo=%02X ui=%02X", st(0x05), st(0x0D))) end
      if pt == 215 then
        check("menu-cleared", vword(rowaddr(0) + 7) == 0x2000, string.format("%04X", vword(rowaddr(0) + 7)))
        -- after close, fighter regains control: press y -> P1 attacks
      end
      if pt >= 225 and pt <= 227 then pulse[0] = { y = true } elseif pt == 228 then pulse[0] = nil end
      if pt >= 228 and ram(0x1001) ~= 0 then saw.p1acted = true end
      if pt == 250 then check("menu-uneat", ram(0x1001) ~= 0 or saw.p1acted == true) end
    end,
    fin = function() end },
}

local phase, pt, needLoad = 1, nil, true
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(TRACE .. "training_p11.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; pt = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not pt then return end
  pt = pt + 1
  local P = PHASES[phase]
  P.tick(pt)
  if pt >= P.dur then
    P.fin()
    log("--- phase done: " .. P.name)
    phase = phase + 1
    saw = {}; pulse = {}
    if phase > #PHASES then
      if checks ~= EXPECTED_CHECKS then
        fails = fails + 1
        log(string.format("FAIL check-count %d != expected %d (a check was skipped)", checks, EXPECTED_CHECKS))
      end
      log(fails == 0 and ("ALL PASS (" .. checks .. ")") or (fails .. " FAILURES"))
      emu.stop(fails == 0 and 0 or 1)
      return
    end
    needLoad = true; pt = nil
  end
end, emu.eventType.endFrame)

print("test_p11_tier1 loaded")
