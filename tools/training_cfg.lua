-- training_cfg.lua — optional user config for tools/training.lua (dofile'd if present).
-- Set fields on the TM_CFG table; anything omitted keeps its default (see training/main.lua).
TM_CFG = {
  -- hudScale = 2,          -- ScriptHud overlay scale 1-4 (2 = crisp on a 4x window)
  -- meterCells = 80,       -- frame-meter width in cells
  -- rollRows = 40,         -- piano-roll visible rows
  -- reversal_lead = 1,     -- frames of early playback for reversal-timed recordings
  -- padControls = true,    -- pad: hold R = control dummy, Select = record toggle
  -- keys = { menu = "M", hud = "9", boxes = "8", record = "R", play = "T", slot = "Y",
  --          trigger = "U", posSave = "Q", posLoad = "E", meterFreeze = "G",
  --          padSwap = "P", sConv = "F", reset = "0" },
}
