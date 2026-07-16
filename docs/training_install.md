# Training mode — installation & configuration

The training mode is **pure Mesen 2 Lua** — it never modifies the ROM. It works with any
ROM build of *Bishoujo Senshi Sailor Moon S: Jougai Rantou!?* (clean JP, canonical v0.7,
or any experimental build): all game knowledge is read from RAM/ROM at runtime.

## Requirements

- **Mesen 2** (the repo ships `tools/Mesen.app` for macOS; any Mesen 2 build with the Lua
  script window works — Windows/Linux included).
- The game ROM (any of the builds above).
- No BizHawk, no Snes9x, no ROM patching.

## Files

```
tools/training.lua          <- the script you run (GUI entry point)
tools/training_cfg.lua      <- optional user config (safe to delete; defaults apply)
tools/training/             <- the module package (all required)
    main.lua  const.lua  gamestate.lua  input.lua  recorder.lua  dummy.lua
    framedata.lua  combo.lua  labels.lua  regen.lua  menu.lua  hud.lua
    hud_panel.lua  hud_bar.lua  hud_pianoroll.lua  hud_boxes.lua  hitbox_h.lua
tools/training_test.lua     <- headless self-test harness (optional, for development)
tools/training_test_cfg.lua <- selects which self-test runs (optional)
traces/                     <- recordings + settings are saved here at runtime
docs/training_install.md    <- this file
docs/training_usage.md      <- commands & usage reference
```

## Recommended paths

**If you work inside the repo** (`/Users/koneko/Developer/SailorMoonS/`): nothing to do —
all paths are already correct.

**If you extracted the distribution zip somewhere else:** the two entry scripts carry one
absolute path each (`ROOT`). Run the included fixer from the extract directory:

```bash
cd <extract dir>
./fixpaths.sh            # rewrites the path prefix in tools/training*.lua to $PWD
```

or edit by hand — it is a single line at the top of `tools/training.lua` (and
`tools/training_test.lua` if you want the self-tests):

```lua
local ROOT = "/path/to/extract/tools/"
```

Everything else derives from `ROOT` at runtime. Keep the `tools/training/` package
directory next to `training.lua`, and keep a writable `traces/` directory as a **sibling
of `tools/`** (recordings and settings are written to `<ROOT>/../traces/`).

## Running it (GUI)

1. Start Mesen, load the ROM, and get into a **VS match** (any characters; you are P1).
   Tip: from the title screen pick 1P vs 2P so the dummy has no CPU interference.
2. Open **Debug → Script Window**.
3. **Enable file access**: in the Script Window options, allow file/OS access
   (`Options → Allow file/OS access` or the equivalent checkbox). Without it the mode
   still runs, but recordings and settings won't persist across sessions.
4. `File → Open` → `tools/training.lua` → **Run**.
5. You should see the status panels and the frame meter. Press `M` for the menu.

The script stays resident; re-run it after loading a different ROM. Savestates made while
it runs are ordinary Mesen savestates and work normally.

## Configuration

Defaults live in `tools/training/main.lua`; override them in **`tools/training_cfg.lua`**
(read at startup, plain Lua):

```lua
TM_CFG = {
  hudScale = 2,          -- ScriptHud overlay scale 1-4 (2 = crisp on a ~4x window; try 3-4
                         --   if text is too small on your monitor)
  meterCells = 80,       -- frame-meter width in cells (one cell = one frame)
  rollRows = 40,         -- piano-roll visible rows
  reversal_lead = 1,     -- frames of early playback for reversal-timed recordings
  padControls = true,    -- pad extras: hold R = control dummy, Select = record toggle
  keys = { ... },        -- rebind any hotkey (see training_usage.md for the map)
}
```

Menu settings (dummy mode, triggers, HUD mode, hitboxes, S-convention…) are saved
automatically to `traces/training_settings.lua` when you close the menu, and restored on
the next launch. Recording slots persist in `traces/training_slots.lua`.

## Self-tests (optional, headless)

The engine ships with a regression suite validated against measured frame data:

```bash
cd <repo or extract dir>
for T in T1 T2 T2H T3 T5; do
  echo "TEST = \"$T\"" > tools/training_test_cfg.lua
  ROM="<clean JP ROM>" tools/run.sh tools/training_test.lua 250
done
# T4 exercises the v0.7 infinite rep — run it on a v0.7-family ROM:
echo 'TEST = "T4"' > tools/training_test_cfg.lua
ROM="<v0.7 build>" tools/run.sh tools/training_test.lua 250
```

Each test writes `traces/training_test_<id>.txt` (PASS/FAIL lines) and exits nonzero on
failure. The zip includes the savestates the tests need (`traces/*.mss`).

## Troubleshooting

- **No HUD, game runs normally** — the Script Window shows an error: usually a wrong
  `ROOT` path. Fix the path (see above).
- **HUD text but no meter/roll** — HUD mode is cycled off; press `9`, or check `hud mode`
  in the menu.
- **"slot save failed (io access off?)"** — enable file/OS access in the Script Window
  (recordings then persist; without it they live until the script stops).
- **Hotkeys don't respond** — click the game window to give it keyboard focus; keys are
  single letters/digits (see the usage doc) and are only read by the GUI.
- **Boxes/meter misaligned after resizing** — layout re-derives every frame; if a custom
  `hudScale` clips at your window size, lower it in the menu (`hud scale`).
