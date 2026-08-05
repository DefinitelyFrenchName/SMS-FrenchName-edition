#!/usr/bin/env python3
"""Generate a trace_plan for a re-press experiment.

Fixed 2026-08-06 (issues #13, #64). It used to write the generated plan into the
TRACKED `tools/trace_plan.lua` — running an experiment silently rewrote a
versioned file — using a cwd-relative path, and interpolated `sys.argv[2]`
straight into a Lua string literal with no escaping. It now writes wherever you
ask (default: a temp file), prints the path, and quotes the output name.

  python3 tools/gen_plan.py 115                    # -> temp plan, prints TRACE_PLAN=...
  python3 tools/gen_plan.py 115 repress_115.txt    # name the trace output
  python3 tools/gen_plan.py 115 --plan /tmp/p.lua  # choose the plan path

Then: TRACE_PLAN=<path> tools/run.sh tools/trace.lua
"""
import argparse
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def render(t_repress, out_name):
    return f"""POKES = {{ {{ t = 5, addr = 0x1021, val = 0xE8 }} }}
PLAN = {{
  [10] = {{ down = true }},
  [60] = {{ down = true, y = true }},
  [62] = {{ down = true }},
  [{t_repress}] = {{ down = true, y = true }},
  [{t_repress + 2}] = {{ down = true }},
}}
LOGFROM = 60
LOGTO = 140
OUT = {lua_str(out_name)}
"""


def lua_str(s):
    """Quote a Lua string literal — the output name reaches trace.lua as code."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("t_repress", type=int, help="frame of the re-press")
    ap.add_argument("out", nargs="?", default=None,
                    help="trace output name inside traces/ (default: repress_<t>.txt)")
    ap.add_argument("--plan", default=None,
                    help="where to write the plan (default: a temp file). "
                         "Never defaults to the tracked tools/trace_plan.lua.")
    a = ap.parse_args()
    out_name = a.out or f"repress_{a.t_repress}.txt"
    text = render(a.t_repress, out_name)
    if a.plan:
        path = Path(a.plan)
        path.write_text(text)
    else:
        with tempfile.NamedTemporaryFile("w", suffix="_trace_plan.lua", delete=False) as fh:
            fh.write(text)
            path = Path(fh.name)
    print(f"plan written: repress at t={a.t_repress} -> traces/{out_name}")
    print(f"run it with:  TRACE_PLAN={path} tools/run.sh tools/trace.lua")


if __name__ == "__main__":
    main()
