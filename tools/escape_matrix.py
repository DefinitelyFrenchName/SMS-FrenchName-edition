#!/usr/bin/env python3
"""Escape matrix: P1 rep timing (sloppy/perfect) x P2 escape (guard/mash/bdash)
on clean and stacked ROMs. Verdict per cell."""
import re
import subprocess

P1_STYLES = {
    # pre-patch optimal habits: early buffered 66, early jab press
    'sloppy':  ("[81]={}, [83]={right=true}, [85]={}, [87]={right=true}, [89]={},",
                "[111]={down=true,y=true}, [113]={down=true},"),
    # frame-perfect for the patched build: late 66, press 115
    'perfect': ("[95]={}, [97]={right=true}, [98]={}, [99]={right=true}, [101]={},",
                "[115]={down=true,y=true}, [117]={down=true},"),
}
P2_ESCAPES = {
    'guard': "[70]={right=true, down=true}",
    'mash':  ", ".join(f"[{t}]={{y=true}}, [{t+2}]={{}}" for t in range(90, 140, 4)),
    'bdash': "[116]={right=true}, [117]={}, [119]={right=true}, [121]={}",
}
ROMS = {'CLEAN': '', 'STACKED': 'build/sms_stacked.sfc'}

def run(rom, p1, p2):
    dash, jab = P1_STYLES[p1]
    esc = P2_ESCAPES[p2]
    plan = f"""POKES = {{ {{ t = 5, addr = 0x1021, val = 0xE8 }} }}
PLAN = {{
  [10] = {{ down = true }},
  [60] = {{ down = true, y = true }},
  [62] = {{ down = true }},
  [77] = {{ down = true, x = true }},
  [80] = {{ down = true }},
  {dash}
  {jab}
}}
P2PLAN = {{ {esc} }}
LOGFROM = 55
LOGTO = 260
OUT = "mx.txt"
"""
    open("tools/trace_plan.lua", "w").write(plan)
    env = {"ROM": rom} if rom else {}
    import os
    e = dict(os.environ); e.update(env)
    subprocess.run(["tools/run.sh", "tools/trace.lua", "60"], env=e,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    hits, dashf, p2free = [], None, None
    prev_hp = None
    for line in open('traces/mx.txt'):
        m = re.match(r't=(\d+) p1\[act=(\w+)', line)
        if not m: continue
        t, act = int(m.group(1)), m.group(2)
        hp = int(re.search(r'hp=(\w+)', line).group(1), 16)
        p2a = re.search(r'p2\[act=(\w+)', line).group(1)
        if act == '60' and dashf is None: dashf = t
        if prev_hp is not None and hp < prev_hp and t > 90: hits.append(t)
        if t > 100 and p2a in ('41', '53', '26', '0D', '0F', '55', '57') and p2free is None:
            p2free = f"{t}:{p2a}"
        prev_hp = hp
    verdict = 'LOOP HOLDS' if hits and not p2free else ('P2 ESCAPED' if p2free else 'loop dropped')
    return dashf, hits, p2free, verdict

for p2 in P2_ESCAPES:
    for romtag, style in [('CLEAN', 'sloppy'), ('STACKED', 'sloppy'), ('STACKED', 'perfect')]:
        dashf, hits, p2free, verdict = run(ROMS[romtag], style, p2)
        print(f"{romtag:8s} P1={style:7s} P2={p2:6s} | dash@{dashf} 3rd-hit@{hits} P2-action={p2free} => {verdict}")
