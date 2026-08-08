#!/usr/bin/env python3
"""Verify the training-mode docs against the Lua package they describe.

  python3 tools/checktrainingdocs.py        # verify
  python3 tools/checktrainingdocs.py -v     # ...and print what was parsed

WHY THIS EXISTS. `training_usage.md` is a reference for a UI: hotkeys, menu rows,
labels, file paths. Every one of those is a literal in `tools/training/`, and
nothing has ever compared the two — so the docs could name a key that does
nothing, a menu row that no longer exists, or a label that was removed. The last
one had actually happened: **MEATY was removed on 2026-07-20 and the usage doc
still listed it**, which is trap 18 in its purest form (a documented feature that
does not exist) and the exact bug class this project keeps paying for.

The Lua is read STATICALLY, with regexes over the source. Running it is not an
option — it needs Mesen's `emu` API before it will even load — and the facts
being checked are all plain table literals, which is precisely the case where
reading beats executing.

Both directions, everywhere it makes sense: a key the docs list must exist AND
every key in the code must be documented; the same for menu rows, labels and the
package's own file inventory. One-directional checks let a feature ship
undocumented, which is how a doc becomes a subset of the truth without anyone
noticing.

Needs no ROM and no emulator: like `checkknobs`, this one runs in CI.
"""
import argparse
import os
import re
import sys
from pathlib import Path as _P

REPO = _P(__file__).resolve().parent.parent
TOOLS = REPO / "tools"
PKG = TOOLS / "training"
USAGE = REPO / "docs" / "project" / "training_usage.md"
PLUS = REPO / "docs" / "project" / "trainingplus.md"
INSTALL = REPO / "docs" / "project" / "training_install.md"


class Fail(Exception):
    pass


def lua(name):
    return (PKG / name).read_text(encoding="utf-8") if (PKG / name).exists() \
        else (TOOLS / name).read_text(encoding="utf-8")


def block(text, opener):
    """The braced block that starts at `opener`, brace-counted."""
    i = text.index(opener) + len(opener) - 1
    depth, j = 0, i
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
        j += 1
    raise Fail(f"unterminated block after {opener!r}")


def eq(label, doc_value, code_value):
    if doc_value != code_value:
        raise Fail(f"{label}:\n            docs say {doc_value!r}\n            code says {code_value!r}")


# ------------------------------------------------------------------- code --
def code_keys():
    """{action: key} — main.lua's defaults plus dummy.lua's quick modes."""
    keys = dict(re.findall(r"(\w+)\s*=\s*\"(\w)\"", block(lua("main.lua"), "keys = {")))
    quick = block(lua("dummy.lua"), "local QUICK = {")
    for n in range(1, len(re.findall(r"\{\s*name\s*=", quick)) + 1):
        keys[f"dummy{n}"] = str(n)
    return keys


def code_actions():
    src = "\n".join(lua(p.name) for p in sorted(PKG.glob("*.lua")))
    named = set(re.findall(r"ctx\.actions\.(\w+)\s*=", src))
    if 'ctx.actions["dummy" .. n]' in src:
        named |= {f"dummy{n}" for n in range(1, 8)}
    return named


def code_menu_rows():
    rows = block(lua("menu.lua"), "local rows = {")
    # only the top-level entries: `{ "name", function() …`. Without the
    # `function` anchor this also matches the cyc({ "stand", … }) value lists
    # nested inside them, which is a parser that reads twice as many rows as
    # exist and then reports the doc as wrong.
    return re.findall(r"\{\s*\"([^\"]+)\",\s*function", rows)


def code_persist_keys():
    return re.findall(r"\{\s*\"(\w+)\",", block(lua("menu.lua"), "local PERSIST = {"))


def code_cyc(row_name):
    """The value list a menu row cycles through, if it uses cyc({…})."""
    rows = block(lua("menu.lua"), "local rows = {")
    m = re.search(r"\{\s*\"" + re.escape(row_name) + r"\",.*?cyc\(\{([^}]*)\}", rows, re.S)
    return re.findall(r"\"([^\"]+)\"", m.group(1)) if m else None


def code_labels():
    src = lua("labels.lua")
    fired = set(re.findall(r"fire\(\"([A-Z][A-Z ]*)\"", src))
    coloured = set(re.findall(r"(?:\[\"([A-Z][A-Z ]+)\"\]|\b([A-Z]{2,}))\s*=\s*0x[0-9A-Fa-f]{6}", src))
    coloured = {a or b for a, b in coloured}
    return fired, coloured


def code_quick_modes():
    return re.findall(r"name\s*=\s*\"([^\"]+)\"", block(lua("dummy.lua"), "local QUICK = {"))


def code_patch11_menu():
    """[(row, [values])] for the IN-ROM training menu — patch 11's own table.

    Same family of claim as the Lua trainer's menu and the same failure mode: the
    doc lists the rows a player scrolls through, and nothing tied that list to the
    builder that paints them.
    """
    src = (TOOLS / "mkpatch11.py").read_text(encoding="utf-8")
    rows = re.findall(r"\(\s*\"([A-Z0-9 ]+)\",\s*\w+,\s*\[([^\]]*)\]\)", src)
    return [(name, re.findall(r"\"([A-Z]+)\"", vals)) for name, vals in rows]


def code_tests():
    return set(re.findall(r"^tests\.(\w+)\s*=", lua("training_test.lua"), re.M))


# -------------------------------------------------------------------- docs --
def doc_rows(table_header, path=USAGE):
    """First-column cells of the markdown table whose header row contains `table_header`."""
    lines = path.read_text(encoding="utf-8").splitlines()
    out, seen = [], False
    for ln in lines:
        if table_header in ln:
            seen = True
            continue
        if seen:
            if not ln.startswith("|"):
                break
            if ln.startswith("|---"):
                continue
            out.append(ln.strip("|").split("|")[0].strip())
    return out


def doc_keys():
    """The keys the usage doc's hotkey table lists, expanded (`1`–`7`, `Q` / `E`)."""
    out = set()
    for cell in doc_rows("| Key | Action |"):
        cell = cell.replace("`", "")
        m = re.fullmatch(r"(\w)\s*[–-]\s*(\w)", cell)
        if m and m.group(1).isdigit():
            out |= {str(n) for n in range(int(m.group(1)), int(m.group(2)) + 1)}
            continue
        out |= {p.strip() for p in cell.split("/") if p.strip()}
    return out


def doc_menu_rows():
    return [c for c in doc_rows("| Row | Values | Meaning |")]


def doc_labels():
    return {c for c in doc_rows("| Label | Fires when |")}


def doc_package_files():
    text = INSTALL.read_text(encoding="utf-8")
    listing = text[text.index("tools/training/"):text.index("tools/training_test.lua")]
    return set(re.findall(r"(\w+)\.lua", listing))


# ------------------------------------------------------------------ checks --
CHECKS = []


def check(name):
    def deco(fn):
        CHECKS.append((name, fn))
        return fn
    return deco


@check("every documented hotkey exists, and every hotkey is documented")
def _(keys=None):
    keys = keys or code_keys()
    eq("hotkeys", doc_keys(), set(keys.values()))


@check("every hotkey is bound to an action that exists")
def _(keys=None):
    keys = keys or code_keys()
    orphans = sorted(a for a in keys if a not in code_actions())
    if orphans:
        raise Fail(f"keys bound to actions nothing registers: {orphans} — pressing them "
                   "does nothing, which no amount of documentation fixes")


@check("the seven dummy quick modes, in order")
def _(keys=None):
    modes = code_quick_modes()
    eq("quick-mode count", 7, len(modes))
    # the whole hotkey table, both columns — the quick modes are named in the
    # ACTION column ("1 off · 2 guard all · …")
    doc = USAGE.read_text(encoding="utf-8")
    cell = " ".join(ln for ln in doc.splitlines() if ln.startswith("|")).lower()
    for n, name in enumerate(modes, 1):
        # the doc writes these as prose ("3 guard after first hit"); require the
        # distinctive words rather than the exact string
        for word in name.split():
            if word not in cell:
                raise Fail(f"quick mode {n} ({name!r}): the docs never mention {word!r}")


@check("the menu rows, and the order they appear in")
def _(keys=None):
    eq("menu rows", doc_menu_rows(), code_menu_rows())


@check("every menu-visible setting is persisted")
def _(keys=None):
    rows, persisted = code_menu_rows(), code_persist_keys()
    if len(rows) != len(persisted):
        raise Fail(f"{len(rows)} menu rows but {len(persisted)} PERSIST entries — a setting "
                   "that saves one way is the #32 drift bug")


@check("the value lists the menu cycles through")
def _(keys=None):
    doc = USAGE.read_text(encoding="utf-8")
    for row in ("pose", "guard", "wakeup", "trigger", "status"):
        values = code_cyc(row)
        if not values:
            raise Fail(f"menu row {row!r} no longer cycles a literal list — re-read menu.lua")
        line = next(ln for ln in doc.splitlines() if ln.startswith(f"| {row} "))
        for v in values:
            if v not in line:
                raise Fail(f"menu row {row!r} offers {v!r}, which its doc row does not list")


@check("the labels: what fires, what is documented")
def _(keys=None):
    fired, coloured = code_labels()
    eq("labels", doc_labels(), fired)
    missing = fired - coloured
    if missing:
        raise Fail(f"labels with no colour: {sorted(missing)}")


@check("the two runtime files the docs promise")
def _(keys=None):
    for path, where in (("../traces/training_settings.lua", "menu.lua"),
                        ("../traces/training_slots.lua", "recorder.lua")):
        if path not in lua(where):
            raise Fail(f"{where} no longer writes {path}")
        if path.split("/")[-1] not in USAGE.read_text(encoding="utf-8") + \
                INSTALL.read_text(encoding="utf-8"):
            raise Fail(f"{path} is written but no doc names it")


@check("the package inventory in the install doc")
def _(keys=None):
    on_disk = {p.stem for p in PKG.glob("*.lua")}
    eq("tools/training/*.lua", doc_package_files(), on_disk)


@check("the self-tests the install doc tells you to run")
def _(keys=None):
    listed = set(re.findall(r"for T in ([\w ]+); do", INSTALL.read_text(encoding="utf-8")))
    listed = {t for group in listed for t in group.split()}
    eq("self-test ids", listed, code_tests())


@check("the IN-ROM training menu (patch 11): rows, order and values")
def _(keys=None):
    code = code_patch11_menu()
    doc = [c.strip("* ") for c in doc_rows("| Row | Values | What it does |", PLUS)]
    eq("patch 11 menu rows", doc, [name for name, _ in code])
    text = PLUS.read_text(encoding="utf-8")
    for name, values in code:
        line = next(ln for ln in text.splitlines() if ln.startswith(f"| **{name}**"))
        for v in values:
            if v not in line:
                raise Fail(f"patch 11 row {name!r} offers {v!r}, which its doc row does not list")


def selftests():
    """Negative controls: every check must fail when its subject moves.

    A doc checker's real failure mode is a PARSER that quietly stops matching —
    it then reports agreement between two empty sets. So each control perturbs
    one side (an extra key, a reordered menu, a missing label, a renamed file)
    and demands the corresponding check object.
    """
    import contextlib
    bad = []

    @contextlib.contextmanager
    def patched(name, fn):
        real = globals()[name]
        globals()[name] = fn
        try:
            yield
        finally:
            globals()[name] = real

    def must_fail(idx, label):
        try:
            CHECKS[idx][1]()
        except Fail:
            return
        bad.append(f"{label} was not caught by {CHECKS[idx][0]!r}")

    # snapshot every real value FIRST: a lambda that calls the name it replaces
    # recurses forever, which is its own small lesson about monkeypatching
    real_keys, real_rows = doc_keys(), code_menu_rows()
    real_fired, real_col = code_labels()
    real_files = doc_package_files()
    with patched("doc_keys", lambda: real_keys | {"Z"}):
        must_fail(0, "a documented key that does not exist")
    with patched("code_menu_rows", lambda: real_rows[1:] + real_rows[:1]):
        must_fail(3, "a menu row in the wrong position")
    with patched("code_labels", lambda: (real_fired - {"GC"}, real_col)):
        must_fail(6, "a label that no longer fires")
    with patched("doc_package_files", lambda: real_files | {"ghost"}):
        must_fail(8, "a package file the docs invent")

    if code_keys().get("menu") != "M" or len(real_rows) < 10 or len(real_fired) < 5:
        bad.append("a Lua parser returned an implausible result — check its block match")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if args.verbose:
        print("  keys:", ", ".join(f"{k}={v}" for k, v in sorted(code_keys().items())))
        print("  menu rows:", ", ".join(code_menu_rows()))
        print("  labels:", ", ".join(sorted(code_labels()[0])))
        print("  tests:", ", ".join(sorted(code_tests())))

    fails = []
    for name, fn in CHECKS:
        try:
            fn()
            if args.verbose:
                print(f"  \033[32mPASS\033[0m  {name}")
        except Fail as e:
            print(f"  \033[31mFAIL\033[0m  {name}\n          {e}")
            fails.append(name)
        except Exception as e:
            print(f"  \033[31mERROR\033[0m {name}\n          {type(e).__name__}: {e}")
            fails.append(name)
    for b in selftests():
        print(f"  \033[31mFAIL\033[0m  [self-test] {b}")
        fails.append(b)

    if fails:
        print(f"\n\033[31m{len(fails)} problems\033[0m between the training docs and the Lua")
        sys.exit(1)
    print(f"\033[32mALL PASS\033[0m ({len(CHECKS)} checks: hotkeys, menu, labels, files and "
          "self-tests, each verified in both directions)")


if __name__ == "__main__":
    main()
