-- demo_link_blocked.lua — the follow-up 2LP pressed 2 frames late.
-- Result: cleanly BLOCKED — P2 is fully in crouch-block before the 2LP becomes active, so
-- it takes zero damage (goes to blockstun, not hitstun). This is the unambiguous "fails"
-- visual: 2 frames late and the loop simply stops. (1 frame late still meaty-connects; see
-- demo_link_late.lua.) Run on the v0.6 true-combo ROM in a live match.
LINK_OFFSET = 2
dofile("/Users/koneko/Developer/SailorMoonS/tools/demo_link.lua")
