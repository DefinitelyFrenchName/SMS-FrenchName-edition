-- react_njump.lua — Mars P2 attempts njump as a wake-up reversal to escape Uranus's
-- frame-perfect N=6 meaty. Measured result: DOES NOT ESCAPE — neutral jump (up). Can't leave the ground before the meaty lands on the single actionable frame.
-- Run on the v0.7 canonical ROM in a live match (loads the Uranus-vs-Mars state itself).
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
REACTION="njump"
dofile(ENV.TOOLS .. "react_test.lua")
