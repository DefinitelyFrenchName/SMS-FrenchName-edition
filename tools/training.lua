-- training.lua — MODERN TRAINING MODE for Bishoujo Senshi Sailor Moon S (Mesen 2 Lua).
--
-- Pure script — the ROM is untouched. Load a VS match (any ROM build), then in the Mesen
-- GUI: Debug -> Script Window -> open this file -> Run. Works alongside any savestate.
--
-- FEATURES
--   * SF6-style frame meter (bottom): per-frame classes for both players — startup green,
--     active red, recovery blue (light blue = cancellable), hitstun yellow, blockstun gold,
--     knockdown rust, throw purple, tech teal; white top strip = invulnerable, dimmed =
--     hitstop; segment counts + advantage badge (+N green / -N red) per exchange. Meter
--     freezes when both players idle so the last exchange stays readable.
--   * Move summary line: "P1 2LP S4 A5 R4 T13 hit +6 (c+12)" — S counts frames before the
--     first active frame (Dustloop convention; press F to toggle SF6-style S+1). c+N =
--     advantage if you cancel the recovery (this game's links live there).
--   * Status panels, input piano roll, event labels (GC/REVERSAL/PUNISH/...), combo
--     counter, hitbox viewer, recordable dummy — see keymap below (features arrive in
--     phases; run headless tests via tools/training_test.lua).
--
-- KEYMAP (host keyboard; editable in tools/training_cfg.lua)
--   M menu | 9 HUD cycle | 8 hitboxes | R record | T playback | Y slot | U trigger
--   Q/E save/load position | G meter freeze | P pad swap | F S-convention | 0 reset pos
-- PAD: hold R shoulder = control dummy; Select = record flow (see recorder.lua header).
--
-- Architecture: tools/training/*.lua modules share a ctx table (see main.lua); add a
-- feature by dropping a module file and appending it to MODULES in main.lua.
-- DEVELOPER GUIDE: docs/project/training_internals.md — the full explanation
-- (architecture, Lua/Mesen primers, per-module walkthrough, worked extension example).
--
-- GUI SMOKE CHECKLIST (visuals can't be screenshot-verified headless — ScriptHud doesn't
-- composite into takeScreenshot):
--   [ ] frame meter visible bottom, freezes when idle, G toggles freeze
--   [ ] meter scale changes via menu (hud scale 1-4) without layout breakage
--   [ ] piano roll right edge scrolls with your inputs; switches to P2 while recording
--   [ ] hitboxes align with sprites while walking both directions (8 toggles)
--   [ ] hold R: you drive the dummy; release: dummy resumes
--   [ ] Select: record slot -> do a sequence -> Select; T plays it back; wakeup trigger
--       plays it as a reversal after a knockdown
--   [ ] Q saves position, E restores it (works repeatedly)
--   [ ] M menu navigates with W/S/A/D, settings persist across restarts
--   [ ] labels pop on GC/punish/reversal/throw situations (MEATY label removed 2026-07-20)
-- Headless self-tests (all must pass): see tools/training_test.lua header.
local ENV = dofile((package.path:match("([^;]+)%?%.lua$") or error("sms_env: tools dir not in package.path")) .. "/sms_env.lua")
local ROOT = ENV.TOOLS
local main = dofile(ROOT .. "training/main.lua")
TM = main.run(ROOT, {})
print("training mode loaded — M for menu, 9 to cycle HUD")
