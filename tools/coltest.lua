-- coltest.lua: reach a live VS match with P1=CHARA confirmed via a color button combo,
-- dump CGRAM. On the palette-patched ROM, charselect confirm = face button (A/B/Y/X),
-- with L/R/Start as color-range modifiers. Config via coltest_cfg.lua:
--   CHARA (id), CONFIRM (table like {a=true} or {l=true,a=true}), TAG.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
dofile(ENV.TOOLS .. "coltest_cfg.lua")
local frames, step, sf = 0, 1, 0
local pulse = {}
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k,v in pairs(b) do base[k]=v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function beat(on) return (frames % 7) < 3 and on or {} end
-- confirm on the beat, holding modifiers continuously so edge lands with them held
local function confirm(tbl)
  local h = {}
  for k,v in pairs(tbl) do if k=="l" or k=="r" or k=="start" then h[k]=v end end  -- hold mods
  if (frames % 7) < 3 then for k,v in pairs(tbl) do h[k]=v end end                 -- pulse the face btn
  return h
end

local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,           -- title menu confirm (start ok here)
  function() return sf>240 end,
  function() emu.write(0x1B40, CHARA, emu.memType.snesWorkRam); if CHAR2 then emu.write(0x1B80, CHAR2, emu.memType.snesWorkRam) end; return sf>20 end,
  function() pulse[0]=confirm(CONFIRM); return ram(0x1B42)==1 or sf>90 end,   -- P1 color-confirm
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=confirm({a=true}); return sf>60 end,            -- P2 confirm (color 0)
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true}); return ram(0x1000)==CHARA or sf>600 end,
  function() return ram(0x1000)==CHARA and ram(0x1080)~=0 and ram(0x1001)==0 end,
  function() return sf>120 end,
}

local dump = false
emu.addMemoryCallback(function()
  if dump then
    local cf = io.open(TRACE .. "cg_" .. TAG .. ".bin", "wb")
    if not cf then print("coltest.lua: cannot open " .. (TRACE .. "cg_" .. TAG .. ".bin")) emu.stop(1) return end
    local t = {}
    for a = 0, 0x1FF do t[#t+1] = string.char(emu.read(a, emu.memType.snesCgRam)) end
    cf:write(table.concat(t)); cf:close()
    -- also screenshot for eyeball
    local sfp = io.open(TRACE .. "cg_" .. TAG .. ".png", "wb")
    if not sfp then print("coltest.lua: cannot open " .. (TRACE .. "cg_" .. TAG .. ".png")) emu.stop(1) return end
    sfp:write(emu.takeScreenshot()); sfp:close()
    if SAVE then
      local ss = emu.createSavestate()
      local so = io.open(TRACE .. SAVE, "wb")
      if not so then print("coltest.lua: cannot open " .. (TRACE .. SAVE)) emu.stop(1) return end
      so:write(ss); so:close()
      print("savestate: " .. SAVE .. " len=" .. #ss)
    end
    print("CGRAM dumped: " .. TAG)
    emu.stop(0)
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then dump = true end
  if frames > 4000 then print("TIMEOUT tag="..TAG.." step="..step.." p1char="..string.format("%02X",ram(0x1000))); emu.stop(1) end
end, emu.eventType.endFrame)

print("coltest loaded")
