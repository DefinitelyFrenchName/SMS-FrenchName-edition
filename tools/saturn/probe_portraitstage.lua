
-- probe_portraitstage.lua — at MATCH LOAD, is the VRAM $0000 transfer the
-- report-card portrait, staged in $7F like the effect tiles? Dump the staging
-- content at that DMA so it can be compared with the card's VRAM $0000 region.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local TAG = os.getenv("TAG") or "x"
local CHAR = tonumber(os.getenv("CHAR") or "6")
local LOG = assert(io.open(ENV.TRACE .. "saturn/pstage_" .. TAG .. ".txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local frames, step, sf = 0, 1, 0
local pulse = {}
local function beat(on) return (frames % 10) < 2 and on or {} end
emu.addEventCallback(function()
  for p = 0, 1 do
    local b = pulse[p] and PL.pad(pulse[p]) or PL.pad()
    emu.setInput(b, 0, p)
  end
end, emu.eventType.inputPolled)
local vaddr, grabbed = 0, {}
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
    if (value or 0) == 0 then return end
    for ch = 0, 7 do
      if ((value >> ch) & 1) == 1 then
        local c = 0x4300 + ch * 0x10
        if (reg(c+1) == 0x18 or reg(c+1) == 0x19) and (vaddr == 0x0000 or vaddr == 0x0800) then
          local src = reg(c+2) + 256*reg(c+3) + 65536*reg(c+4)
          local len = reg(c+5) + 256*reg(c+6)
          local key = string.format("%04X", vaddr)
          if not grabbed[key] then
            grabbed[key] = true
            log(string.format("f=%d DMA VRAM %04X <- %06X len %04X", frames, vaddr, src, len))
            local f = assert(io.open(ENV.TRACE .. "saturn/pstage_" .. TAG .. "_" .. key .. ".bin", "wb"))
            local t2 = {}
            for i = 0, 0x8FF do t2[#t2+1] = string.char(emu.read(0x7F0000 + i, REG)) end
            f:write(table.concat(t2)); f:close()
          end
        end
      end
    end
  end, emu.callbackType.write, b, b, emu.cpuType.snes, emu.memType.snesMemory)
end
local STEPS = {
  function() return frames >= 900 end,
  function() pulse[0]=beat({down=true}); return ram(0x1B10)==1 end,
  function() pulse[0]=beat({start=true}); return sf>40 end,
  function() return sf>300 end,
  function() wr(0x1B40, CHAR); wr(0x1B80, 4); return sf>20 end,
  function() pulse[0]=beat({a=true}); return ram(0x1B42)==1 or sf>150 end,
  function() pulse[1]=beat({a=true}); return ram(0x1B82)==1 or sf>150 end,
  function()
    pulse[0] = (sf % 20 < 3) and {start=true} or {}
    if ram(0x70)==4 and ram(0x1000)~=0 then return true end
    if sf > 900 then log("NO-MATCH"); emu.stop(1) end
    return false
  end,
  function() return sf > 60 end,
}
emu.addEventCallback(function()
  frames = frames + 1; sf = sf + 1
  local fn = STEPS[step]
  if fn and fn() then step = step + 1; sf = 0; pulse = {} end
  if not STEPS[step] then log("done"); emu.stop(0) end
  if frames > 4000 then log("TIMEOUT"); emu.stop(1) end
end, emu.eventType.endFrame)
print("portraitstage loaded")
