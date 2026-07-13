-- demo_link_early.lua — the follow-up 2LP pressed 1 frame EARLY.
-- Expected: the 2LP is DROPPED (input lands during dash recovery, no rising edge when
-- Uranus becomes actionable) -> the link never connects. Proves you cannot press early.
-- Run in a live Uranus-P1 match; recommended ROM the v0.6 true-combo build.
LINK_OFFSET = -1
dofile("/Users/koneko/Developer/SailorMoonS/tools/demo_link.lua")
