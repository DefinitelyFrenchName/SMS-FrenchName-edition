POKES = { { t = 5, addr = 0x1021, val = 0xE8 } }
PLAN = {
  [10] = { down = true },
  -- rep 1
  [60] = { down = true, y = true },
  [62] = { down = true },
  [77] = { down = true, x = true },
  [80] = { down = true },
  [95] = {},
  [97] = { right = true },
  [98] = {},
  [99] = { right = true },
  [101] = {},
  -- rep 2 (frame-perfect: jab press 115, chain 133, 66 taps 153/155, dash 156)
  [115] = { down = true, y = true },
  [117] = { down = true },
  [133] = { down = true, x = true },
  [136] = { down = true },
  [151] = {},
  [153] = { right = true },
  [154] = {},
  [155] = { right = true },
  [157] = {},
  -- rep 3
  [171] = { down = true, y = true },
  [173] = { down = true },
  [189] = { down = true, x = true },
  [192] = { down = true },
  [207] = {},
  [209] = { right = true },
  [210] = {},
  [211] = { right = true },
  [213] = {},
  -- rep 4 jab (proves loop closes again)
  [227] = { down = true, y = true },
  [229] = { down = true },
}
P2PLAN = { [70] = { right = true, down = true } }
LOGFROM = 58
LOGTO = 260
OUT = "infinite3rep.txt"
