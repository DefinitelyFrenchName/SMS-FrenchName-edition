-- demo_link_headless.lua — run the demo_link.lua auto-calibrating sweep headless and
-- write the connect window to traces/demo_link_out.txt, then exit (no GUI report phase).
-- ROM=<build> tools/run.sh tools/demo_link_headless.lua 280
-- Expect (v0.7 family, gate 0x04): exactly one MEATY frame, no COMBO frames.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
DEMO_LOG = ENV.TRACE .. "demo_link_out.txt"
dofile(ENV.TOOLS .. "demo_link.lua")
