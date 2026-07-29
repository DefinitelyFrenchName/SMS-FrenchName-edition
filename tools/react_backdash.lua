-- react_backdash.lua — Mars P2 attempts backdash as a wake-up reversal to escape Uranus's
-- frame-perfect N=6 meaty. Measured result: DOES NOT ESCAPE — reversal back-dash (back-back). Comes out (act 0x26) on the wake frame but has NO frame-1 invincibility, so the meaty hits it.
-- Run on the v0.7 canonical ROM in a live match (loads the Uranus-vs-Mars state itself).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
REACTION="backdash"
dofile(ENV.TOOLS .. "react_test.lua")
