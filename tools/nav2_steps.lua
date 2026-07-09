-- Moon P1 vs Moon P2 savestate for cross-char verification
STEPS = {
  { type = "wait", frames = 900 },
  { type = "pulse", btn = "down", cond = function(ram) return ram(0x1B10) == 1 end, max = 300 },
  { type = "pulse", btn = "start", max = 30 },
  { type = "wait", frames = 300 },
  { type = "poke", addr = 0x1B40, val = 1 },
  { type = "wait", frames = 30 },
  { type = "pulse", btn = "start", cond = function(ram) return ram(0x1B42) == 1 end, max = 60 },
  { type = "wait", frames = 30 },
  { type = "pulse", btn = "start", max = 40, port = 1 },
  { type = "wait", frames = 300 },
  { type = "pulse", btn = "start", cond = function(ram) return ram(0x1000) == 1 end, max = 900 },
  { type = "wait", cond = function(ram)
      return ram(0x1000) == 1 and ram(0x1080) ~= 0 and ram(0x1001) == 0 and ram(0x1081) == 0
    end, frames = 1800 },
  { type = "wait", frames = 90 },
  { type = "state", name = "moon_vs_moon.mss" },
  { type = "wait", frames = 5 },
  { type = "stop" },
}
