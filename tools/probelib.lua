-- probelib.lua — shared emulator-access helpers for the standalone suites/probes
-- (issue #34, scoped per the maintainer's dedup rule: common tooling is centralized,
-- one-shot archival probes are left as-is). The training package has its own shared
-- module (tools/training/const.lua); this serves the standalone entry points.
-- Load via the standard bootstrap:  local PL = ENV.dofile("probelib.lua")
local P = {}
P.WRAM = emu.memType.snesWorkRam
P.PRG = emu.memType.snesPrgRom
function P.ram(a) return emu.read(a, P.WRAM) end
function P.wr(a, v) emu.write(a, v, P.WRAM) end
function P.rom(a) return emu.read(a, P.PRG) end
P.FALSE_PAD = { a=false,b=false,x=false,y=false,l=false,r=false,
                up=false,down=false,left=false,right=false,start=false,select=false }
-- fresh full pad table, with optional overrides merged in
function P.pad(overrides)
  local b = {}
  for k, v in pairs(P.FALSE_PAD) do b[k] = v end
  if overrides then for k, v in pairs(overrides) do b[k] = v end end
  return b
end
return P
