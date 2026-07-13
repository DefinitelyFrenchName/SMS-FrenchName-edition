-- demo_link_late.lua — the follow-up 2LP pressed 1 frame LATE.
-- Expected: the 2LP comes out, but the opponent has already recovered from hitstun into
-- a crouch-block -> the hit is BLOCKED. Proves you cannot press late either.
-- Run in a live Uranus-P1 match; recommended ROM the v0.6 true-combo build.
LINK_OFFSET = 1
dofile("/Users/koneko/Developer/SailorMoonS/tools/demo_link.lua")
