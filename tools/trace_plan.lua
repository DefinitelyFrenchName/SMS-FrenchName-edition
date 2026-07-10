POKES = { { t = 5, addr = 0x1021, val = 0xE8 } }
PLAN = {
  [10] = { down = true },
  [60] = { down = true, y = true },
  [62] = { down = true },
  [77] = { down = true, x = true },
  [80] = { down = true },
  [95]={}, [97]={right=true}, [98]={}, [99]={right=true}, [101]={},
  [115]={down=true,y=true}, [117]={down=true},
}
P2PLAN = { [116]={right=true}, [117]={}, [119]={right=true}, [121]={} }
LOGFROM = 115
LOGTO = 165
OUT = "zoom_bdash.txt"
