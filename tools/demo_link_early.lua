-- demo_link_early.lua — after auto-calibrating, loop a single attempt ONE FRAME EARLIER than
-- the valid frame. On any gate this shows the 2LP getting DROPPED (the press edge lands in
-- dash recovery, no buffer) — you cannot press early. Run on any patched ROM in a live match
-- (loads the v0.7 state by default; pass LINK_STATE for another build). See demo_link.lua.
LINK_OFFSET = -1
dofile("/Users/koneko/Developer/SailorMoonS/tools/demo_link.lua")
