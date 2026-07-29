-- probe_title_ppu.lua — dump PPU state (bg mode, tilemap/CHR bases) at the title screen.
-- ROM=<rom> OUT=<tag> tools/run.sh tools/probe_title_ppu.lua 60
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local TRACE = ENV.TRACE
local TAG = os.getenv("OUT") or "clean"
local t = 0
local FALSE = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }

emu.addEventCallback(function()
  local b = {}
  for k, v in pairs(FALSE) do b[k] = v end
  if (t % 260) >= 160 and (t % 260) <= 161 then b.start = true end
  emu.setInput(b, 0, 0)
end, emu.eventType.inputPolled)

local function dumpTable(f, tbl, prefix)
  for k, v in pairs(tbl) do
    local key = prefix .. tostring(k)
    if type(v) == "table" then
      dumpTable(f, v, key .. ".")
    else
      f:write(key .. " = " .. tostring(v) .. "\n")
    end
  end
end

emu.addEventCallback(function()
  t = t + 1
  if t == 700 then
    local f = io.open(TRACE .. "titleppu_" .. TAG .. ".txt", "w")
    local st = emu.getState()
    dumpTable(f, st, "")
    f:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
print("probe_title_ppu loaded, tag=" .. TAG)
