#!/usr/bin/env python3
"""Generate tools/trace_plan.lua for a re-press experiment."""
import sys

t_repress = int(sys.argv[1])
out = sys.argv[2] if len(sys.argv) > 2 else f"repress_{t_repress}.txt"
plan = f"""POKES = {{ {{ t = 5, addr = 0x1021, val = 0xE8 }} }}
PLAN = {{
  [10] = {{ down = true }},
  [60] = {{ down = true, y = true }},
  [62] = {{ down = true }},
  [{t_repress}] = {{ down = true, y = true }},
  [{t_repress + 2}] = {{ down = true }},
}}
LOGFROM = 60
LOGTO = 140
OUT = "{out}"
"""
open("tools/trace_plan.lua", "w").write(plan)
print(f"plan written: repress at t={t_repress} -> {out}")
