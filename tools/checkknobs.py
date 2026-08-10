#!/usr/bin/env python3
"""Verify the knobs table in docs/project/patch_notes.md against the builders.

  python3 tools/checkknobs.py        # verify
  python3 tools/checkknobs.py -v     # ...and print every option found

WHY THIS EXISTS. Trap 18: *a documented knob either works or does not exist, and
"works" is a measurement.* The knobs table is the page the maintainer retunes
balance from — a wrong default there is not a typo, it is a build made on a
false premise. It is also the page furthest from the code: nothing links a row
to the `add_argument` it describes, so a renamed flag or a changed default
leaves the table exactly as convincing as it was.

Three things are checked, in both directions:

  * every flag the table names EXISTS in the builder it names;
  * every builder option is documented somewhere in the knobs section (minus the
    plumbing every builder shares — src, out, --stacked, --force);
  * the documented default MATCHES the one in the source.

Defaults are read STATICALLY, with `ast` — the builders' parsers are built under
`if __name__ == "__main__":`, so there is nothing to import, and running a build
tool to ask it about itself is a worse idea than reading it. Module-level
constants are resolved (`default=NEW_SPEED`), including simple f-strings, since
patch 4's default subtitle is one and that is exactly the row that had rotted.

This needs no ROM and no emulator, so unlike most of this project's checks it
runs anywhere, including CI.
"""
import argparse
import ast
import re
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

NOTES = REPO / "docs" / "project" / "patch_notes.md"
SECTION = "## Tunable parameters (the knobs)"
# Plumbing every builder shares; not knobs, and documented once in HANDOFF §2.
PLUMBING = {"src", "out", "--stacked", "--force", "--help", "-h"}


class Fail(Exception):
    pass


def knobs_section():
    text = NOTES.read_text(encoding="utf-8")
    i = text.index(SECTION)
    j = text.index("\n---", i)
    return text[i:j]


def rows():
    """[(builders, flags, default_cell, row_text)] from the knobs table."""
    out = []
    for line in knobs_section().splitlines():
        if not line.startswith("|") or line.startswith("|---") or "| Knob |" in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4:
            continue
        _, where, default, _ = cells[0], cells[1], cells[2], cells[3]
        builders = re.findall(r"(mkpatch\d*\.py)", where)
        flags = re.findall(r"(--[a-z][a-z0-9-]*)", where)   # --l1, not --l
        out.append((builders, flags, default, line))
    if not out:
        raise Fail("no knob rows found — has the table's shape changed?")
    return out


def _literal(node, consts):
    """Best-effort constant folding for an `add_argument(default=…)` value."""
    try:
        return ast.literal_eval(node)
    except Exception:
        pass
    if isinstance(node, ast.Name):
        return consts.get(node.id, "<computed>")
    if isinstance(node, ast.JoinedStr):                      # f"FrenchName v.{X}"
        parts = []
        for v in node.values:
            if isinstance(v, ast.Constant):
                parts.append(str(v.value))
            elif isinstance(v, ast.FormattedValue) and isinstance(v.value, ast.Name):
                parts.append(str(consts.get(v.value.id, "<computed>")))
            else:
                return "<computed>"
        return "".join(parts)
    return "<computed>"


def options(builder):
    """{flag or positional: default} for one builder, read out of its source."""
    src = (REPO / "tools" / builder).read_text(encoding="utf-8")
    tree = ast.parse(src)
    consts = {}
    import smspaths                                          # for imported constants
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name):
            consts[node.targets[0].id] = _literal(node.value, consts)
        if isinstance(node, ast.ImportFrom) and node.module == "smspaths":
            for a in node.names:
                if hasattr(smspaths, a.name) and not callable(getattr(smspaths, a.name)):
                    consts[a.asname or a.name] = getattr(smspaths, a.name)
    out = {}
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "add_argument"):
            continue
        names = [a.value for a in node.args
                 if isinstance(a, ast.Constant) and isinstance(a.value, str)]
        if not names:
            continue
        kw = {k.arg: k.value for k in node.keywords}
        action = ast.literal_eval(kw["action"]) if "action" in kw else None
        if action == "store_true":
            default = False
        elif action == "store_false":
            default = True
        elif "default" in kw:
            default = _literal(kw["default"], consts)
        else:
            default = None
        out[names[0]] = default
    return out


def renderings(value):
    """How a default could legitimately be written in the table."""
    if isinstance(value, bool) or value is None:
        return []                                   # a flag's presence IS its default
    if isinstance(value, int):
        return [str(value), f"0x{value:X}", f"0x{value:x}", f"0x{value:04X}", f"0x{value:04x}"]
    return [str(value)]


def check(verbose=False):
    fails, section, documented_flags = [], knobs_section(), set()
    seen_builders = set()

    for builders, flags, default_cell, line in rows():
        documented_flags |= set(flags)
        for b in builders:
            if not (REPO / "tools" / b).exists():
                fails.append(f"the table names {b}, which does not exist")
                continue
            seen_builders.add(b)
            opts = options(b)
            if verbose:
                print(f"  {b:14} " + "  ".join(f"{k}={v!r}" for k, v in opts.items()))
            for flag in flags:
                if flag not in opts and len(builders) == 1:
                    fails.append(f"{b} has no {flag} — the table documents it "
                                 f"(row: {line[:60]}…)")
                    continue
                cands = renderings(opts.get(flag))
                if cands and not any(c in default_cell for c in cands):
                    fails.append(f"{b} {flag} defaults to {opts[flag]!r}, but the table's "
                                 f"Default cell says {default_cell!r}")

    # the other direction: an option nobody documented
    for b in sorted(seen_builders):
        for flag in options(b):
            if flag in PLUMBING or not flag.startswith("-"):
                continue
            if flag not in section:
                fails.append(f"{b} has {flag}, which the knobs section never mentions")

    # env-var gates are knobs too, and they are the only ones with no argparse
    src16 = (REPO / "tools" / "mkpatch16.py").read_text(encoding="utf-8")
    for env in sorted(set(re.findall(r"SMS_P16_[A-Z]+", section))):
        if f'"{env}"' not in src16:
            fails.append(f"the table documents the gate {env}, which mkpatch16.py never reads")
    # ...and the REVERSE, which the argparse checks above have always had and the
    # env gates did not. A live miss showed why it matters: SMS_P16_BRACKET was
    # added to the builder and shipped undocumented, and this file passed.
    for env in sorted(set(re.findall(r'"(SMS_P16_[A-Z]+)"', src16))):
        if env not in section:
            fails.append(f"mkpatch16.py reads the gate {env}, which the knobs section never mentions")
    return fails


def selftests():
    """Negative controls: each of the three checks must catch its own failure."""
    bad = []
    if renderings(1600) and "0x0640" not in renderings(1600):
        bad.append("hex rendering of a default is not offered")
    if renderings(False):
        bad.append("a store_true flag was given a value to match — its presence is its default")
    opts = options("mkpatch5.py")
    if opts.get("--speed") != 0x0640:
        bad.append(f"static default extraction is broken: --speed read as {opts.get('--speed')!r}")
    if options("mkpatch17.py").get("--no-pool") is not True:
        bad.append("store_false was not resolved to a True default")
    if options("mkpatch4.py").get("--text") == "<computed>":
        bad.append("the f-string default in mkpatch4.py was not folded")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    fails = check(args.verbose) + [f"SELF-TEST: {b}" for b in selftests()]
    n = len(rows())
    if fails:
        for line in fails:
            print(f"  \033[31mFAIL\033[0m  {line}")
        print(f"\n\033[31m{len(fails)} problems\033[0m between the knobs table and the builders")
        sys.exit(1)
    print(f"\033[32mALL PASS\033[0m ({n} documented knobs; flags, defaults and env gates "
          "match the builders both ways)")


if __name__ == "__main__":
    main()
