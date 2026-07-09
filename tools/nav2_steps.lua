-- steps: get to 1P-vs-2P char select, then scout its RAM
STEPS = {
  { type = "wait", frames = 900 },
  -- cursor to 1P vs 2P ($1B10: 0 -> 1)
  { type = "pulse", btn = "down", cond = function(ram) return ram(0x1B10) == 1 end, max = 600 },
  { type = "shot", name = "n2_cursor1" },
  { type = "wait", frames = 20 },
  -- confirm 1P vs 2P; screen change detection unknown -> pulse briefly, then scout
  { type = "pulse", btn = "start", max = 40 },
  { type = "wait", frames = 300 },
  { type = "shot", name = "n2_after_confirm", dumpFrom = 0x1B00, dumpTo = 0x1B3F },
  { type = "stop" },
}
