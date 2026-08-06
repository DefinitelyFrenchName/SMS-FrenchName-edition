-- demo_truecombo_headless.lua — run demo_truecombo.lua headless from the v07 state and
-- log per-frame P2 state to traces/demo_truecombo_out.txt, then exit.
-- ROM=<v0.6/v0.7-family build> tools/run.sh tools/demo_truecombo_headless.lua 60
-- Oracle (#94): with block held from the first hit onward, `hitsBlk` on the last
-- line must equal (number of hp drops) - 1 — the first hit landed BEFORE block.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
DEMO_STATE = ENV.TRACE .. "uranus_vs_jupiter_v07.mss"
DEMO_LOG = ENV.TRACE .. "demo_truecombo_out.txt"
dofile(ENV.TOOLS .. "demo_truecombo.lua")
