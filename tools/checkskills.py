#!/usr/bin/env python3
"""Verify the skill/rules pairs carry identical rule-ID sets, both ways.

  python3 tools/checkskills.py                 # the two repo pairs
  python3 tools/checkskills.py -v              # ...and print every ID found
  python3 tools/checkskills.py --user-dir ~/.claude/skills   # + the user-level pairs

WHY THIS EXISTS. The project's distilled lessons ship in TWO renditions per tier:
an agent-facing skill (`.claude/skills/<name>/SKILL.md`, terse MUST/NEVER rules)
and a human document (prose with the incident behind each rule). Two hand-written
renditions of one rule set is exactly the shape that drifts — trap 18's lesson
("a documented knob either works or does not exist") pointed at documentation
itself: a rule added to one file and not the other leaves a reader and an agent
obeying different laws, and nothing links the two prose files together. So every
rule carries a stable bracketed ID (`[SMS-31]`), a DEFINITION looks different
from a cross-REFERENCE, and this check asserts the definition sets match in both
directions per pair. IDs are never reused; gaps (deletions) are fine.

Definition syntax (anything else is a reference and is ignored):

  skill files:  a list item opening with the ID     `- [SMS-3] **THE ...`
  human files:  a paragraph opening with the ID     `**[SMS-3]** The nine-wide...`

Checked per pair: set equality both ways, no duplicate definitions in either
file, and every definition carries the pair's own prefix (defining an RH rule
inside the SMS skill is a filing error, not a cross-reference).

The extractors are negative-controlled on synthetic content every run — a family
that has stopped matching passes every claim it no longer finds (trap 20). This
needs no ROM and no emulator, so it runs anywhere, including CI. The user-level
pairs (romhacking-methodology, snes-romhacking) live outside the repo, so they
are checked only when --user-dir is given — a repo gate must not depend on a
machine-specific path.
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# (tier prefix, skill rendition, human rendition) — repo-hosted pairs.
REPO_PAIRS = [
    ("SMS", REPO / ".claude/skills/sms-romhacking/SKILL.md",
            REPO / "docs/game/sms_hacking_playbook.md"),
    ("SSP", REPO / ".claude/skills/supers-porting/SKILL.md",
            REPO / "docs/project/saturn/porting_lessons.md"),
]
# User-level pairs, relative to --user-dir (skill and guide share a directory).
USER_PAIRS = [
    ("RH",   "romhacking-methodology/SKILL.md", "romhacking-methodology/GUIDE.md"),
    ("SNES", "snes-romhacking/SKILL.md",        "snes-romhacking/GUIDE.md"),
]

ID = r"\[([A-Z]+-\d+)\]"
DEF_SKILL = re.compile(rf"^- {ID}", re.M)          # `- [SMS-3] ...`
DEF_HUMAN = re.compile(rf"^\*\*{ID}\*\*", re.M)    # `**[SMS-3]** ...`


def defs(text, pattern):
    """All definition IDs in order of appearance (duplicates preserved)."""
    return pattern.findall(text)


def check_pair(prefix, skill_path, human_path, verbose=False):
    fails = []
    texts = {}
    for p in (skill_path, human_path):
        if not p.exists():
            return [f"{prefix}: {p} does not exist"]
        texts[p] = p.read_text(encoding="utf-8")

    s_defs = defs(texts[skill_path], DEF_SKILL)
    h_defs = defs(texts[human_path], DEF_HUMAN)
    if verbose:
        print(f"  {prefix}: skill defines {len(s_defs)}, human defines {len(h_defs)}")

    for name, found in (("skill", s_defs), ("human", h_defs)):
        if not found:
            fails.append(f"{prefix}: the {name} rendition defines NO rules — "
                         "has the definition syntax changed?")
        dupes = sorted({i for i in found if found.count(i) > 1})
        if dupes:
            fails.append(f"{prefix}: duplicate definition(s) in the {name} rendition: "
                         + ", ".join(dupes))
        wrong = sorted({i for i in found if not i.startswith(prefix + "-")})
        if wrong:
            fails.append(f"{prefix}: the {name} rendition DEFINES foreign-prefix rule(s) "
                         f"{', '.join(wrong)} — cross-references don't open a bullet/paragraph")

    only_s = sorted(set(s_defs) - set(h_defs), key=lambda i: int(i.split("-")[1]))
    only_h = sorted(set(h_defs) - set(s_defs), key=lambda i: int(i.split("-")[1]))
    if only_s:
        fails.append(f"{prefix}: in the skill but not the human doc: {', '.join(only_s)}")
    if only_h:
        fails.append(f"{prefix}: in the human doc but not the skill: {', '.join(only_h)}")
    return fails


def selftests():
    """Negative controls: each failure mode must be caught on synthetic pairs."""
    bad = []
    skill = "- [XX-1] rule one ([YY-9])\n- [XX-2] rule two\n"
    human = "**[XX-1]** Rule one, with its incident.\n\n**[XX-2]** Rule two.\n"

    # the family still matches at all (an extractor that finds nothing passes everything)
    if defs(skill, DEF_SKILL) != ["XX-1", "XX-2"] or defs(human, DEF_HUMAN) != ["XX-1", "XX-2"]:
        bad.append("extractors no longer match the definition syntax")
    # a cross-reference must NOT count as a definition
    if "YY-9" in defs(skill, DEF_SKILL):
        bad.append("a cross-reference was read as a definition")

    import tempfile, os
    with tempfile.TemporaryDirectory() as d:
        sp, hp = Path(d) / "SKILL.md", Path(d) / "HUMAN.md"

        # a rule missing from one rendition must fail
        sp.write_text(skill + "- [XX-3] rule three\n"); hp.write_text(human)
        if not check_pair("XX", sp, hp):
            bad.append("a missing ID in one rendition was not caught")
        # a duplicate definition must fail
        sp.write_text(skill + "- [XX-2] rule two again\n")
        hp.write_text(human + "**[XX-2]** Again.\n")
        if not any("duplicate" in f for f in check_pair("XX", sp, hp)):
            bad.append("a duplicate definition was not caught")
        # a foreign-prefix definition must fail
        sp.write_text(skill + "- [ZZ-1] filed under the wrong tier\n")
        hp.write_text(human + "**[ZZ-1]** Same.\n")
        if not any("foreign-prefix" in f for f in check_pair("XX", sp, hp)):
            bad.append("a foreign-prefix definition was not caught")
        # and the matched case must PASS, or every check above is vacuous
        sp.write_text(skill); hp.write_text(human)
        if check_pair("XX", sp, hp):
            bad.append("a matched synthetic pair FAILS — the checks are wrong, not the files")
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--user-dir", metavar="DIR",
                    help="also check the user-level pairs under DIR (e.g. ~/.claude/skills)")
    args = ap.parse_args()

    pairs = list(REPO_PAIRS)
    if args.user_dir:
        base = Path(args.user_dir).expanduser()
        pairs += [(pfx, base / s, base / h) for pfx, s, h in USER_PAIRS]

    fails, total = [], 0
    for prefix, sp, hp in pairs:
        f = check_pair(prefix, sp, hp, args.verbose)
        fails += f
        if not f:
            total += len(defs(sp.read_text(encoding="utf-8"), DEF_SKILL))
    fails += [f"SELF-TEST: {b}" for b in selftests()]

    if fails:
        for line in fails:
            print(f"  \033[31mFAIL\033[0m  {line}")
        print(f"\n\033[31m{len(fails)} problems\033[0m between the skill and human renditions")
        sys.exit(1)
    print(f"\033[32mALL PASS\033[0m ({total} rules across {len(pairs)} pairs; "
          "both renditions define the same IDs, both ways)")


if __name__ == "__main__":
    main()
