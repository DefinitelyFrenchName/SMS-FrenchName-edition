-- demo_link_late.lua — after auto-calibrating, loop a single attempt ONE FRAME LATER than the
-- valid frame. Outcome depends on the gate: on N=5 (v0.6, true combo) this is a MEATY that
-- still connects; on N=6 (v0.7, 1-frame meaty) the valid frame IS the meaty, so one later is
-- cleanly BLOCKED. Either way it is not the intended link. Run in a live match; see the full
-- picture with demo_link.lua. Pass LINK_STATE for a non-v0.7 build.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
LINK_OFFSET = 1
dofile(ENV.TOOLS .. "demo_link.lua")
