-- react_bjump.lua — Mars P2 attempts bjump as a wake-up reversal to escape Uranus's
-- frame-perfect N=6 meaty. Measured result: DOES NOT ESCAPE — back jump (up-back). Up+back reads as a block on the wake frame; the meaty beats same-frame block.
-- Run on the v0.7 canonical ROM in a live match (loads the Uranus-vs-Mars state itself).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
REACTION="bjump"
dofile(ENV.TOOLS .. "react_test.lua")
