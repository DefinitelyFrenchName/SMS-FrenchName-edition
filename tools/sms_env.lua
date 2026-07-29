-- sms_env.lua — repo-relative path discovery for all Mesen Lua tooling.
--
-- Mesen's process cwd is NOT the shell cwd (relative io.open fails even when launched
-- via tools/run.sh from the repo root), which is why paths were historically hardcoded
-- absolute. This helper derives the repo root at runtime instead, so the tooling works
-- from any checkout location (macOS assumed, '/' separators).
--
-- Usage (one bootstrap line at the top of every tool script):
--   local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
-- The match works because Mesen appends "<script dir>?.lua" to package.path when it
-- loads a script from file (GUI Script Window and --testrunner alike).
--
-- Exposed (all directory paths end with "/", matching the old hardcoded literals):
--   ENV.ROOT   repo root            (e.g. ".../SailorMoonS/")
--   ENV.TOOLS  tools dir            (e.g. ".../SailorMoonS/tools/")
--   ENV.TRACE  traces dir           (e.g. ".../SailorMoonS/traces/")
--   ENV.dofile(name)   dofile a sibling script in tools/ (returns its result)
--   ENV.cfg(name)      optional cfg: pcall-dofile tools/<name>, ok even if absent
--
-- Discovery order: script dir from package.path -> $SMS_ROOT -> $PWD -> ROM path
-- walk-up. A candidate root is accepted only if <root>/HANDOFF.md exists.

local function is_root(dir)
  if not dir or dir == "" then return false end
  local f = io.open(dir .. "/HANDOFF.md", "r")
  if f then f:close(); return true end
  return false
end

local function find_root()
  -- 1. the directory Mesen registered for the running script (…/tools)
  local sdir = package.path:match("([^;]+)%?%.lua$")
  if sdir then
    local parent = sdir:gsub("/+$", ""):match("^(.*)/[^/]+$")
    if is_root(parent) then return parent end
  end
  -- 2./3. environment
  for _, var in ipairs({ "SMS_ROOT", "PWD" }) do
    local v = os.getenv and os.getenv(var)
    if v then
      v = v:gsub("/+$", "")
      if is_root(v) then return v end
    end
  end
  -- 4. walk up from the loaded ROM (covers GUI sessions on repo ROMs)
  local ok, ri = pcall(emu.getRomInfo)
  local p = ok and ri and ri.path
  while p and p:find("/") do
    p = p:match("^(.*)/[^/]+$")
    if is_root(p) then return p end
  end
  error("sms_env.lua: cannot locate the SailorMoonS repo root " ..
        "(tried script dir, $SMS_ROOT, $PWD, ROM path). " ..
        "Set SMS_ROOT=/path/to/repo or load a ROM from inside the repo.")
end

local ROOT = find_root() .. "/"
local ENV = {
  ROOT = ROOT,
  TOOLS = ROOT .. "tools/",
  TRACE = ROOT .. "traces/",
}
function ENV.dofile(name) return dofile(ENV.TOOLS .. name) end
function ENV.cfg(name) local ok, r = pcall(dofile, ENV.TOOLS .. name); return ok and r or nil end
return ENV
