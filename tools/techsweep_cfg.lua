-- techsweep_cfg.lua — config for techsweep.lua (see its header for all knobs).
-- Default: measure the Venus 6HP mash-start window (P1 Venus throws P2 Jupiter).
-- Expected TECH window: clean ROM [55..72] (rel connect -5..+12), patch-8 ROM [55..79] (+19);
-- standard reference: STATE="jupiter_vs_venus_clean.mss" gives [55..81] (+21) on either ROM.
STATE = "venus_vs_jupiter_clean.mss"
THROWER = 0
TECH = { a=true }
MASH = 20
MASHGAP = 2
F_LO = 55
F_HI = 100
OUT = "techsweep_out.txt"
