-- demo_link_blocked.lua — after auto-calibrating, loop a single attempt TWO FRAMES LATER than
-- the valid frame: the opponent is fully guarding, so the 2LP is cleanly BLOCKED (zero
-- damage) on any gate. The unambiguous "off by too much -> loop dies" visual. Run in a live
-- match; see demo_link.lua for the whole window. Pass LINK_STATE for a non-v0.7 build.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
LINK_OFFSET = 2
dofile(ENV.TOOLS .. "demo_link.lua")
