-- probe_sms_saturn_p2.lua — verify SATURN AS P2: poke $1080=0x1C, drive P2 pad
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("no tools")) .. "/../sms_env.lua")
local PL = ENV.dofile("probelib.lua")
local LOG = assert(io.open(ENV.TRACE .. "saturn/saturn_p2.txt", "w"))
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local ram, wr = PL.ram, PL.wr
local t, needLoad = -1, true
local acts = {}
emu.addMemoryCallback(function()
  if needLoad then
    local f = assert(io.open(ENV.TRACE .. "uranus_vs_jupiter_f5.mss", "rb"))
    emu.loadSavestate(f:read("*a")); f:close(); needLoad = false; t = 0
  end
end, emu.callbackType.exec, 0x808353, 0x808353, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  local p2 = PL.pad()
  if t >= 120 and t <= 121 then p2 = PL.pad({ y = true })       -- 5LP
  elseif t >= 170 and t <= 171 then p2 = PL.pad({ a = true })   -- 5HK
  -- qcb (P2 faces LEFT so qcf-for-her = down, down-right? her FORWARD = left!)
  elseif t >= 220 and t <= 221 then p2 = PL.pad({ down = true })
  elseif t >= 222 and t <= 223 then p2 = PL.pad({ down = true, left = true })
  elseif t >= 224 and t <= 225 then p2 = PL.pad({ left = true })
  elseif t >= 226 and t <= 227 then p2 = PL.pad({ left = true, y = true }) end
  emu.setInput(PL.pad(), 0, 0); emu.setInput(p2, 0, 1)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if t < 0 then return end
  t = t + 1
  if t == 60 then
    wr(0x1080, 0x1C)
    for _, o in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x07 }) do wr(0x1080 + o, 0) end
  end
  if t > 60 and t <= 320 then acts[ram(0x1081)] = true end
  if t >= 232 and t <= 260 and t % 6 == 0 then
    log(string.format("t=%03d s1180 id=%02X act=%02X pose=%02X tile0A=%02X%02X x=%d",
      t, ram(0x1180), ram(0x1181), ram(0x1185), ram(0x118B), ram(0x118A),
      ram(0x11A1) + 256 * ram(0x11A2)))
    if ram(0x1180) ~= 0 then
      for si = 0, 60 do
        local o = 0x0200 + 4 * si
        if ram(o + 1) < 0xE0 and ram(o + 2) >= 0xA0 then
          log(string.format("  eff-oam%02d: x=%02X y=%02X tile=%02X attr=%02X",
            si, ram(o), ram(o + 1), ram(o + 2), ram(o + 3)))
        end
      end
    end
  end
  if t == 320 then
    local l = {}
    for a in pairs(acts) do l[#l + 1] = string.format("%02X", a) end
    table.sort(l)
    log(string.format("P2-Saturn acts: [%s] end=%02X proj1180 id=%02X",
      table.concat(l, " "), ram(0x1081), ram(0x1180)))
    log("DONE"); emu.stop(0)
  end
end, emu.eventType.endFrame)
print("p2 probe loaded")
