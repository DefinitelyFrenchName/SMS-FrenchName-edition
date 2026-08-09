-- probe_saturn_winbadge.lua — the round-won badge under her life bar (v0.17.0).
--
-- Saturn is summoned the REAL way (L+R over an allowed shell at the confirm),
-- not poked into $1000: the badge's COLOURS come from her transform's palette
-- copier, so a probe that skips the summon would read the shell's palette and
-- call it a pass. The precondition is asserted before any verdict is trusted
-- (HANDOFF trap 9's corollary).
--
-- What it measures, all read back out of VRAM/CGRAM rather than WRAM staging:
--   * the four HUD tilemap cells of badge 1 hold her word ($38CE on P1, $3CCE
--     on P2 — the same word with palette 6 -> 7);
--   * BG3 CHR tiles $CE/$CF/$DE/$DF are non-blank (her medallion arrived);
--   * CGRAM colours 24-27 (P1) / 28-31 (P2) are HER icon palette, not the
--     shell's;
--   * a SECOND round win draws a second badge and leaves the first intact.
--     That last one is the check that exercises the four REDRAW read sites —
--     a fix that only patched the two first-draw sites passes everything above
--     it and fails here.
--
--   SIDE=p1|p2  SHELL_ID=6|7|8  [OPP=4]  TAG=...  ROM=<build> \
--     tools/run.sh tools/saturn/probe_saturn_winbadge.lua 2600
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local ram, wr = PL.ram, PL.wr
local VRAM, CG = emu.memType.snesVideoRam, emu.memType.snesCgRam

local SIDE = os.getenv("SIDE") or "p1"
local SHELL = tonumber(os.getenv("SHELL_ID") or "") or 6
local OPP = tonumber(os.getenv("OPP") or "") or 4
local TAG = os.getenv("TAG") or (SIDE .. "_" .. SHELL)
local LOG = assert(io.open(ENV.TRACE .. "saturn/winbadge_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

-- Her badge, as the builder installs it: tile $CE, BG3 palette 6, priority 1.
-- P2's four cells are the same word ORed with $0400 (palette 6 -> 7), which the
-- drawing code does after the table read — so one table entry serves both.
local BASE = 0x38CE
local function want_cells(side)
  local w = (side == "p2") and (BASE | 0x0400) or BASE
  return { w, w + 1, w + 0x10, w + 0x11 }
end
-- HUD tilemap is BG3 at VRAM word $1000; badge 1 and badge 2 per side. Rows 6
-- and 7 — row 7 is NOT blank in a match, whatever annotations.md used to say.
local CELLS = {
  p1 = { { 0x10C2, 0x10C3, 0x10E2, 0x10E3 }, { 0x10C4, 0x10C5, 0x10E4, 0x10E5 } },
  p2 = { { 0x10DA, 0x10DB, 0x10FA, 0x10FB }, { 0x10DC, 0x10DD, 0x10FC, 0x10FD } },
}
-- Her icon palette, verbatim from the donor: Super S manifest $E0:AC6A +7 ->
-- $E0:B270. Hardcoded on purpose — the point of the check is that CGRAM holds
-- HERS and not whichever shell she wore.
local ICON = { 0xAD, 0x35, 0xFD, 0x7F, 0x8E, 0x69, 0x74, 0x7A }
local BG3_CHR = 0x5000                    -- word; tile T's CHR at $5000 + T*8
local TILES = { 0xCE, 0xCF, 0xDE, 0xDF }

local function vword(w) return emu.read(w * 2, VRAM) | (emu.read(w * 2 + 1, VRAM) << 8) end
local function cells(side, n)
  local out = {}
  for i, w in ipairs(CELLS[side][n]) do out[i] = vword(w) end
  return out
end
local function same(a, b)
  for i = 1, 4 do if a[i] ~= b[i] then return false end end
  return true
end
local function hex4(t)
  local s = {}
  for i = 1, 4 do s[i] = string.format("%04X", t[i]) end
  return table.concat(s, " ")
end

-- ---------------------------------------------------------------- navigation
-- 2P VS, both characters forced, L+R held on the side under test. Lifted from
-- probe_sms_shellguard.lua, which is the flow the whole gate already trusts.
local frames, step, sf = 0, 1, 0
local pulse, hold = {}, false
local P1CHAR = (SIDE == "p1") and SHELL or OPP
local P2CHAR = (SIDE == "p2") and SHELL or OPP
local function beat(on) return (frames % 7) < 3 and on or {} end
local function poke() wr(0x1B40, P1CHAR); wr(0x1B80, P2CHAR) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    if hold and ((SIDE == "p1" and p == 0) or (SIDE == "p2" and p == 1)) then
      b.l = true; b.r = true
    end
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0] = beat({ down = true }); return ram(0x1B10) == 1 end,
  function() pulse[0] = beat({ start = true }); return sf > 40 end,
  function() return sf > 240 end,
  function() poke(); hold = true; return sf > 20 end,
  function() poke(); pulse[0] = beat({ a = true }); return ram(0x1B42) == 1 or sf > 120 end,
  function() pulse[0] = {}; return sf > 20 end,
  function() poke(); pulse[1] = beat({ a = true }); return ram(0x1B82) == 1 or sf > 120 end,
  function() pulse[0] = {}; pulse[1] = {}; return sf > 30 end,
  function()   -- mash both pads through the config screen until IN MATCH
    poke()
    local m = frames % 14
    local b = (m < 3) and { a = true } or ((m >= 7 and m < 10) and { start = true } or {})
    pulse[0] = b; pulse[1] = b
    if ram(0x70) == 4 and ram(0x1000) ~= 0 then return true end
    if sf > 2000 then
      log(string.format("MATCH-LOAD-FAIL $8D=%02X $70=%02X 1000=%02X 1080=%02X",
        ram(0x8D), ram(0x70), ram(0x1000), ram(0x1080)))
      emu.stop(1)
    end
    return false
  end,
  -- settle: $70==4 is the match STARTING, and the transform that gives her the
  -- palette runs a little after it. Declaring "in match" at the first frame of
  -- the round load reads p2=00 and an untransformed P1.
  function() pulse[0] = {}; pulse[1] = {}; return sf > 400 end,
}

-- ------------------------------------------------------------------- the KO
-- Saturn's side jabs an opponent left on 1 HP — the flow probe_sms_winpose.lua
-- established. Poking HP to 0 is NOT equivalent: the round-end state machine
-- waits on the victim's act (0x1F/0x21) and on the displayed bar having caught
-- up, neither of which a bare HP write produces.
local SATSTRUCT = (SIDE == "p2") and 0x1080 or 0x1000
local VICHP = (SIDE == "p2") and 0x1049 or 0x10C9
local ATTPAD = (SIDE == "p2") and 1 or 0
local function setup_ko()
  wr(0x1021, 0x80); wr(0x1022, 0x00)        -- P1 X
  wr(0x10A1, 0xA8); wr(0x10A2, 0x00)        -- P2 X, one jab apart
  wr(VICHP, 1)
end

local inmatch, t = false, -1
local armed = nil                            -- precondition: is she actually in?
local got = { [1] = nil, [2] = nil }         -- latched badge cells, per round
local gotat = { }
local chr, chrsum = nil, 0
local kept = nil
local cgram = nil

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if not inmatch then
    local fn = STEPS[step]
    if fn and fn() then step = step + 1; sf = 0; pulse = {} end
    if not STEPS[step] then
      inmatch = true; t = 0; pulse = {}
      armed = (ram(SATSTRUCT) == 0x1C)
      log(string.format("f=%d IN MATCH p1=%02X p2=%02X armed=%s",
        frames, ram(0x1000), ram(0x1080), tostring(armed)))
      if not armed then
        -- trap 9's corollary: a probe reporting "no badge" when the summon never
        -- happened is testing the harness, not the build.
        log("PRECONDITION-FAIL: Saturn is not on " .. SIDE ..
            " — the summon did not take, so no badge verdict is possible")
        emu.stop(1)
      end
    end
    if frames > 6000 then log("TIMEOUT step " .. step); emu.stop(1) end
    return
  end

  t = t + 1
  if t == 60 then setup_ko() end
  if t == 120 then pulse[ATTPAD] = { y = true } end
  if t == 124 then pulse[ATTPAD] = {} end
  -- round 2: the same setup once the next round is running
  if t == 900 then setup_ko(); wr((SIDE == "p2") and 0x10C9 or 0x1049, 0x60) end
  if t == 960 then pulse[ATTPAD] = { y = true } end
  if t == 964 then pulse[ATTPAD] = {} end

  -- latch each badge the first frame it is drawn, and keep the latest reading of
  -- badge 1 so "round 2 did not corrupt round 1" is a measurement, not a hope.
  for n = 1, 2 do
    local c = cells(SIDE, n)
    if not got[n] and (c[1] ~= 0 and c[1] ~= 0x2000) then
      got[n] = c; gotat[n] = t
      log(string.format("t=%d badge %d drawn: %s", t, n, hex4(c)))
      -- "round 2 left round 1's badge alone" has to be sampled AT the moment
      -- badge 2 appears: the game wipes the HUD tilemap on the round/match
      -- transition, so a reading taken later says nothing about the redraw.
      if n == 2 then kept = cells(SIDE, 1) end
      if n == 1 then
        chr = {}
        for i, tl in ipairs(TILES) do
          local s, base = 0, (BG3_CHR + tl * 8) * 2
          for k = 0, 15 do s = s + emu.read(base + k, VRAM) end
          chr[i] = s; chrsum = chrsum + s
        end
        local c0 = (SIDE == "p2") and 28 or 24
        cgram = {}
        for k = 0, 7 do cgram[k + 1] = emu.read(c0 * 2 + k, CG) end
      end
    end
  end

  if t > 1700 then
    local w = want_cells(SIDE)
    local ok_b1 = got[1] and same(got[1], w)
    local ok_b2 = got[2] and same(got[2], w)
    local ok_keep = kept and same(kept, w)
    local ok_chr = chr and chr[1] > 0 and chr[2] > 0 and chr[3] > 0 and chr[4] > 0
    local ok_pal = true
    if cgram then
      for k = 1, 8 do if cgram[k] ~= ICON[k] then ok_pal = false end end
    else
      ok_pal = false
    end
    local function yn(b) return b and "ok" or "BAD" end
    log(string.format("cells want %s", hex4(w)))
    log(string.format("badge1 %s (t=%s)", got[1] and hex4(got[1]) or "<never drawn>",
      tostring(gotat[1])))
    log(string.format("badge2 %s (t=%s)", got[2] and hex4(got[2]) or "<never drawn>",
      tostring(gotat[2])))
    log(string.format("badge1 at the moment badge2 appeared: %s",
      kept and hex4(kept) or "<badge2 never drawn>"))
    log(string.format("chr tiles $CE/$CF/$DE/$DF sums: %s",
      chr and table.concat(chr, ",") or "<unread>"))
    log(string.format("cgram %s: %s", (SIDE == "p2") and "28-31" or "24-27",
      cgram and table.concat(cgram, " ") or "<unread>"))
    local all = ok_b1 and ok_b2 and ok_keep and ok_chr and ok_pal
    log(string.format(
      "FINAL %s side=%s shell=%d  badge1=%s badge2=%s kept=%s chr=%s palette=%s chrsum=%d",
      all and "PASS" or "FAIL", SIDE, SHELL,
      yn(ok_b1), yn(ok_b2), yn(ok_keep), yn(ok_chr), yn(ok_pal), chrsum))
    emu.stop(all and 0 or 0)   -- the verdict is the FINAL line, not the exit code
  end
end, emu.eventType.endFrame)

print("probe_saturn_winbadge loaded: " .. SIDE .. " shell " .. SHELL)
