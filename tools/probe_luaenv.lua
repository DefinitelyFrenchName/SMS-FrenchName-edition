-- probe_luaenv.lua — one-shot probe of Mesen's Lua sandbox for path-discovery options.
-- ROM=<any> tools/run.sh tools/probe_luaenv.lua 20
local function say(k, v) print(string.format("%-28s %s", k, tostring(v))) end
say("debug lib", type(debug))
if type(debug) == "table" then
  local ok, info = pcall(debug.getinfo, 1, "S")
  say("debug.getinfo source", ok and info and info.source or ("ERR " .. tostring(info)))
end
say("os lib", type(os))
if type(os) == "table" then
  say("os.getenv", type(os.getenv))
  if os.getenv then say("os.getenv PWD", os.getenv("PWD")); say("os.getenv SMS_ROOT", os.getenv("SMS_ROOT")) end
end
say("io lib", type(io))
if type(io) == "table" and io.popen then
  local ok, p = pcall(io.popen, "pwd")
  if ok and p then say("io.popen pwd", p:read("*l")); p:close() else say("io.popen pwd", "ERR") end
else
  say("io.popen", io and type(io.popen) or "nil")
end
-- cwd check via relative open
local f = io.open("HANDOFF.md", "r")
say("relative open HANDOFF.md", f and "OK (cwd=repo root)" or "nil")
if f then f:close() end
say("package", type(package))
if type(package) == "table" then say("package.path", package.path) end
say("emu.getRomInfo", type(emu.getRomInfo))
if emu.getRomInfo then
  local ok, ri = pcall(emu.getRomInfo)
  if ok and ri then for k, v in pairs(ri) do say("romInfo." .. tostring(k), v) end end
end
say("emu.getScriptDataFolder", type(emu.getScriptDataFolder))
if emu.getScriptDataFolder then
  local ok, d = pcall(emu.getScriptDataFolder)
  say("scriptDataFolder", ok and d or "ERR")
end
emu.stop(0)
