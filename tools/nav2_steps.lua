-- full flow: title -> 1Pvs2P -> P1=Uranus (poke), P2=Moon -> config screen -> match -> savestate
STEPS = {
  { type = "wait", frames = 900 },
  { type = "pulse", btn = "down", cond = function(ram) return ram(0x1B10) == 1 end, max = 300 },
  { type = "pulse", btn = "start", max = 30 },
  { type = "wait", frames = 300 },
  { type = "poke", addr = 0x1B40, val = 6 },
  { type = "wait", frames = 30 },
  { type = "pulse", btn = "start", cond = function(ram) return ram(0x1B42) == 1 end, max = 60 },
  { type = "wait", frames = 30 },
  -- P2 confirm (Moon)
  { type = "pulse", btn = "start", max = 40, port = 1 },
  { type = "wait", frames = 300 },
  { type = "shot", name = "vs_config" },
  -- config screen: start to begin match; wait until P1 struct = Uranus
  { type = "pulse", btn = "start", cond = function(ram) return ram(0x1000) == 6 end, max = 900 },
  { type = "shot", name = "vs_loading", dumpFrom = 0x1000, dumpTo = 0x10FF },
  -- wait for round start: both players in a controllable state (action 0 = neutral) and intro done
  { type = "wait", cond = function(ram)
      return ram(0x1000) == 6 and ram(0x1080) ~= 0 and ram(0x1001) == 0 and ram(0x1081) == 0
    end, frames = 1800 },
  { type = "wait", frames = 90 },  -- settle after intro (round announcement)
  { type = "shot", name = "vs_round_live", dumpFrom = 0x1000, dumpTo = 0x10FF },
  { type = "state", name = "uranus_vs_moon.mss" },
  { type = "wait", frames = 5 },
  { type = "stop" },
}
