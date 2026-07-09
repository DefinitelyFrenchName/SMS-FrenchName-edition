-- pass 11 (deterministic RAM): downs on port 0 (1000-2000), then port 1 (2100-3100)
SCHEDULE = {}
for f = 1000, 2000, 100 do
  SCHEDULE[#SCHEDULE+1] = { f, { down = true }, hold = 6, port = 0 }
end
for f = 2100, 3100, 100 do
  SCHEDULE[#SCHEDULE+1] = { f, { down = true }, hold = 6, port = 1 }
end
SHOT_FROM = 900
SHOT_TO = 3200
SHOT_EVERY = 100
STOP_AT = 3200
