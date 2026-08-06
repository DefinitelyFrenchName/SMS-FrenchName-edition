-- probe_p11_7fc.lua (patch 11, P10b): bank $7F usage census across boot -> title ->
-- practice nav -> char select -> training match. Watches reads+writes to
-- $7F0000-$7FFFFF (WRAM offs 0x10000-0x1FFFF), reporting touched 256-byte pages per
-- phase — full page lists (probe_p11_7f caps at 40) plus per-10-frame access-count
-- deltas once in-match. Output: traces/p11_7fc.txt
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local LOG = assert(io.open(TRACE .. "p11_7fc.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local function ram(a) return emu.read(a, emu.memType.snesWorkRam) end

local frames, step, sf = 0, 1, 0
local pulse = {}
local pagesR, pagesW = {}, {}
local hits = 0
emu.addMemoryCallback(function(addr) pagesR[math.floor((addr - 0x10000) / 256)] = true; hits = hits + 1 end,
  emu.callbackType.read, 0x10000, 0x1FFFF, emu.cpuType.snes, emu.memType.snesWorkRam)
emu.addMemoryCallback(function(addr) pagesW[math.floor((addr - 0x10000) / 256)] = true; hits = hits + 1 end,
  emu.callbackType.write, 0x10000, 0x1FFFF, emu.cpuType.snes, emu.memType.snesWorkRam)

local function report(tag)
  local function fmt(t)
    local l = {}
    for p in pairs(t) do l[#l + 1] = p end
    table.sort(l)
    local s, n = "", #l
    for i = 1, n do s = s .. string.format(" %04X", l[i]) end
    return n, s
  end
  local nr, sr = fmt(pagesR)
  local nw, sw = fmt(pagesW)
  log(string.format("%s f=%d: readPages=%d [%s ] writePages=%d [%s ]", tag, frames, nr, sr, nw, sw))
  pagesR, pagesW = {}, {}
end

emu.addEventCallback(function()
  for p = 0, 1 do
    local base = { a=false,b=false,x=false,y=false,l=false,r=false,up=false,down=false,left=false,right=false,start=false,select=false }
    local b = pulse[p]; if b then for k, v in pairs(b) do base[k] = v end end
    emu.setInput(base, 0, p)
  end
end, emu.eventType.inputPolled)

local function slowbeat(on) return (frames % 16) < 4 and on or {} end
local function beat(on) return (frames % 7) < 3 and on or {} end

local STEPS = {
  function() if frames == 890 then report("boot+attractwait") end; return frames >= 900 end,
  function() pulse[0]=slowbeat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=slowbeat({right=true}); return ram(0x1B10)==4 end,
  function() pulse[0]={}; if sf==1 then report("titlemenu") end; return sf>10 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() pulse[0]={}; return sf>240 end,
  function() if sf==1 then report("practice-confirm+charselload") end
             emu.write(0x1B40, 6, emu.memType.snesWorkRam)
             emu.write(0x1B80, 4, emu.memType.snesWorkRam); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>90 end,
  function() pulse[0]={}; return sf>30 end,
  function() pulse[1]=beat({a=true}); return sf>60 end,
  function() return sf>240 end,
  function() pulse[0]=beat({start=true}); pulse[1]=beat({start=true})
             return (ram(0x1000)==6 and ram(0x1001)==0 and ram(0x1080)~=0) or sf>600 end,
  function() if sf==1 then report("charsel+matchload") end; return sf>240 end,
  function() report("in-match-240f"); return true end,
}

local lastH = 0
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  if step >= 12 and frames % 10 == 0 then
    if hits ~= lastH then log(string.format("hits f=%d step=%d d=%d", frames, step, hits - lastH)); lastH = hits end
  end
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 4500 then log("TIMEOUT step=" .. step); emu.stop(1) end
end, emu.eventType.endFrame)

print("probe_p11_7f loaded")
