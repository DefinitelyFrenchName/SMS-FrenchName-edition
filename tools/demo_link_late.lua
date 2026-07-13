-- demo_link_late.lua — the follow-up 2LP pressed 1 frame LATE.
-- Result: it STILL CONNECTS, but as a same-frame MEATY, not a true combo — P2 has already
-- recovered from hitstun (its first actionable frame), and the engine's hit-beats-same-
-- frame-block rule lets the 2LP chip through. So it is NOT guaranteed: an invincible
-- reversal or a fast jump-out would escape it. (Press 2 frames late = cleanly blocked; set
-- LINK_OFFSET = 2 to see that.) The guaranteed true combo is only the on-time frame.
-- Run on the v0.6 true-combo ROM in a live match.
LINK_OFFSET = 1
dofile("/Users/koneko/Developer/SailorMoonS/tools/demo_link.lua")
