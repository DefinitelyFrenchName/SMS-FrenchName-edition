-- react_chibi5lp.lua — Chibi Moon (P2) attempts 5LP (the fastest poke in the game, neutral+LP)
-- as a wake-up reversal vs Uranus's frame-perfect N=6 meaty.
-- Measured: DOES NOT ESCAPE. On wake-up the 5LP's startup begins the frame AFTER the wake
-- frame (frame 120 is a forced neutral-return frame; 5LP state 0x40 first appears at 121),
-- so the meaty (active on 120) hits Chibi while she's still neutral. Fastest poke, still loses.
-- Run on the v0.7 ROM in a live match (loads the Uranus-vs-Chibi state itself).
REACTION="chibi5lp"
dofile("/Users/koneko/Developer/SailorMoonS/tools/react_test.lua")
