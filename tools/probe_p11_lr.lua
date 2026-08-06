-- probe_p11_lr.lua: fresh-boot repro for "L+R doesn't open the training menu".
-- Boots -> Practice -> in-match (same autopilot as probe_p11_nav), then tries L+R
-- three ways: (a) both pressed same frame, held 8f; (b) L leads R by 2f (pad skew);
-- (c) R leads L by 2f. After each attempt logs $8D, MENUOPEN $7F:F005, P1 act
-- (taunt = 0x65/0x66), and $7F:F000..F00F. Output: traces/p11_lr.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
pcall(dofile, ENV.TOOLS .. "probe_p11_lr_cfg.lua")  -- optional TAG
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_lr.txt", "w"))
local frames, step, sf = 0, 1, 0
local pulse = {}
local WRAM = emu.memType.snesWorkRam
local function ram(a) return emu.read(a, WRAM) end
local function log(s) LOG:write(s .. "\n"); LOG:flush() end

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function beat(on) return (frames % 7) < 3 and on or {} end
local function slowbeat(on) return (frames % 16) < 4 and on or {} end

local function state7f()
  local s = ""
  for i = 0, 15 do s = s .. string.format("%02X ", ram(0x1F000 + i)) end
  return s
end
local function snap(tag)
  log(string.format("%s f=%d sf=%d mode=%02X g70=%02X g1FA=%02X menu=%02X p1act=%02X 7F:F000=%s",
    tag, frames, sf, ram(0x8D), ram(0x70), ram(0x1FA), ram(0x1F005), ram(0x1001), state7f()))
end

local attempts = {
  { name = "simultaneous", l0 = 0, r0 = 0, shot = true },
  { name = "after-movelist", l0 = 0, r0 = 0, pre = "startx2" }, -- Start open+close movelist, then L+R
  { name = "L-leads-10f",  l0 = 0, r0 = 10 },
  { name = "during-movelist", l0 = 0, r0 = 0, pre = "start1" }, -- movelist left OPEN, then L+R (last: leaves it open)
}
local shotName = (TAG or "lr") .. "_menu.png"
local ai = 1

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=slowbeat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=slowbeat({right=true}); return ram(0x1B10)==4 end,
  function() pulse[0]={}; return sf>10 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() pulse[0]={}; return sf>240 end,
  function() emu.write(0x1B40, 6, WRAM); emu.write(0x1B80, 4, WRAM); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  -- Practice: P1 also confirms the dummy's char; then mash A/start through any
  -- stage/config screens until the match actually loads (charIDs in the structs).
  function()
    emu.write(0x1B80, 4, WRAM)
    pulse[0] = (frames % 14 < 3) and {a=true} or ((frames % 14 >= 7 and frames % 14 < 10) and {start=true} or {})
    if ram(0x1000)==6 and ram(0x1080)~=0 then return true end
    if sf > 900 then snap("MATCH-LOAD-FAIL"); emu.stop(1) end
    return false
  end,
  function() pulse[0]={}; return sf>180 and ram(0x1001)==0 end,   -- settle to neutral
  -- L+R attempts: each = 8f press window (with per-button lead), 120f observe, log, next
  function()
    local at = attempts[ai]
    if not at then snap("ALL-ATTEMPTS-DONE"); emu.stop(0); return false end
    if sf == 1 then snap("BEFORE-" .. at.name) end
    -- optional preamble: Start presses (movelist toggle) well before the L+R window
    if at.pre and sf >= 2 and sf <= 5 then pulse[0] = { start = true } end
    if at.pre == "startx2" and sf >= 40 and sf <= 43 then pulse[0] = { start = true } end
    if at.pre and (sf == 6 or sf == 44) then pulse[0] = {} end
    if at.pre and sf == 80 then snap("post-preamble-" .. at.name) end
    if sf >= 90 and sf < 106 and at.pre then
      local p = {}
      if sf - 90 >= at.l0 then p.l = true end
      if sf - 90 >= at.r0 then p.r = true end
      pulse[0] = p
    elseif sf == 106 and at.pre then pulse[0] = {}
    end
    if (not at.pre) and sf >= 10 and sf < 26 then
      local p = {}
      if sf - 10 >= at.l0 then p.l = true end
      if sf - 10 >= at.r0 then p.r = true end
      pulse[0] = p
    elseif sf == 26 then pulse[0] = {}
    end
    if sf > 26 and sf <= 150 and (sf % 8 == 0) then snap("obs-" .. at.name) end
    if at.shot and sf == 100 then
      local sp = assert(io.open(TRACE .. shotName, "wb"), "probe_p11_lr.lua: cannot open " .. (TRACE .. shotName)); sp:write(emu.takeScreenshot()); sp:close()
      log("SCREENSHOT " .. shotName .. " menu=" .. ram(0x1F005))
    end
    if sf == 150 then
      snap("AFTER-" .. at.name)
      -- close the menu if it opened (L+R again) so the next attempt starts closed
      ai = ai + 1; sf = 0
    end
    return false
  end,
}

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if frames % 300 == 0 then snap("tick") end
  local fn = STEPS[step]
  if fn and fn() then snap("STEP->" .. (step+1)); step = step + 1; sf = 0; pulse = {} end
  if frames > 6000 then snap("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_p11_lr loaded")
