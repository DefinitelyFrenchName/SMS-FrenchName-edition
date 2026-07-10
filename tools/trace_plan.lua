POKES = { { t = 5, addr = 0x1021, val = 0xE8 } }
PLAN = {
  [10] = { down = true },
  [60] = { down = true, y = true },
  [62] = { down = true },
  [77] = { down = true, x = true },
  [80] = { down = true },
  [95] = {},
  [97] = { right = true },
  [98] = {},
  [99] = { right = true },
  [101] = {},
  [116] = { down = true, y = true },
  [118] = { down = true },
}
P2PLAN = { [95] = { right = true, down = true } }
LOGFROM = 95
LOGTO = 250
OUT = "stk_116.txt"
