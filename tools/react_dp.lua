-- react_dp.lua — Sailor Neptune (P2) attempts her invincible reversal DP (623+HP) to escape
-- Uranus's frame-perfect N=6 meaty.
--
-- Measured: Neptune's DP is invincible from FRAME 2, not frame 1. So:
--   * frame-perfect meaty (default, MFV=115): the 2LP hits the DP's vulnerable frame-1
--     startup (state 0x69 at 120) -> DP LOSES, Neptune is hit.
--   * one frame late (set REACT_MFV = 116): the 2LP lands on DP frame 2 (invincible) and
--     WHIFFS -> the DP counter-hits Uranus into a knockdown (DP WON).
-- So an invincible-reversal character punishes a non-frame-perfect meaty; only frame-perfect
-- execution beats the DP. Run on the v0.7 ROM in a live match (loads the Uranus-vs-Neptune
-- state itself). To see the late-punish case: add a line `REACT_MFV = 116` before the dofile.
REACTION="dp"
dofile("/Users/koneko/Developer/SailorMoonS/tools/react_test.lua")
