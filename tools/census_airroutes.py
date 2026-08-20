#!/usr/bin/env python3
"""census_airroutes.py — which START ROUTES do the jump acts and AIR NORMALS
offer, for all nine characters? (Phase 1 of the anime-fighter feasibility
programme; decides gate G4 — where air-chain cancel points can live.)

Read-only. Derivation is from the ROM, not from the docs:
  $C1:00A6 proc dispatch -> per-char proc base -> the act-table operand of the
  dispatch's own `jmp (tbl,X)` -> handlers for jump acts 0x06/0x07/0x08 ->
  recursive descent (tools/dis65816.descend, bounded to the char's proc block)
  -> route calls, with the last `ldy #imm` before each call as its table:
     jsr $0459  normals (stance table in Y)
     jsr $0958  specials, free start
     jsr $0952  specials, hit-confirm start
     jsr $055A  close throws
     jsr $11E2 / $0BDD  the two per-char movement routines
  The jump handlers' $0459 operands ARE the jump stance tables; their records
  name the air-normal acts, whose handlers get the same treatment.

Controls:
  + Uranus's two jump stance tables must come out $C1:7B0D / $C1:7B19 exactly
    (the one decoded set, sms_engine_internals.md §7.x).
  + the documented specials-route census must reproduce: Moon/Jupiter/Chibi/
    Venus jump acts pass a specials starter, Mercury/Mars/Uranus/Neptune/Pluto
    do not (docs/game/sms_specials.md).
  - a null act slot (0x2B) must yield NO routes (a detector that finds routes
    in a null handler finds them anywhere).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from smspaths import clean_rom
import dis65816

C1 = 0x010000
DISPATCH = C1 + 0x00A6
NAMES = {1: "Moon", 2: "Mercury", 3: "Mars", 4: "Jupiter", 5: "Venus",
         6: "Uranus", 7: "Neptune", 8: "Pluto", 9: "ChibiMoon"}
ROUTES = {0x0459: "normals", 0x0958: "spec-free", 0x0952: "spec-hitconfirm",
          0x055A: "throws", 0x11E2: "double-jump", 0x0BDD: "triangle-jump"}
HAS_AIR_SPECIAL_ROUTE = {"Moon", "Jupiter", "ChibiMoon", "Venus"}   # documented census
URANUS_JUMP_TABLES = {0x7B0D, 0x7B19}                               # documented anchor


def word(rom, off):
    return rom[off] | rom[off + 1] << 8


def act_table(rom, proc):
    """The dispatch preamble's own `jmp (tbl,X)` operand."""
    for a, op, ln, m, x in dis65816.walk(rom, proc, proc + 0x20, m=1, x=0):
        if op == 0x7C:                      # jmp (abs,X)
            return C1 + word(rom, a + 1)
    raise SystemExit(f"no jmp (tbl,X) in dispatch preamble at {proc:06X}")


def routes_of(rom, handler, lo, hi):
    """[(route-name, ldy-operand-or-None)] offered along the handler's own
    descent, bounded to the proc block (shared engine code is not entered)."""
    if handler == 0:
        return []
    code = dis65816.descend(rom, lo, hi, [(C1 + handler, 1, 0)], strict=False)
    found, last_ldy = [], {}
    for a in sorted(code):
        op, ln = code[a]
        if op == 0xA0 and ln == 3:          # ldy #imm16
            last_ldy[a] = word(rom, a + 1)
        elif op == 0x20:                    # jsr abs
            t = word(rom, a + 1)
            if t in ROUTES:
                prev = [v for k, v in sorted(last_ldy.items()) if k < a]
                found.append((ROUTES[t], prev[-1] if prev else None))
    return found


def main():
    rom = Path(clean_rom()).read_bytes()
    procs = {i: word(rom, DISPATCH + i * 2) for i in range(1, 28)}
    bounds = sorted(v for v in procs.values() if v)
    fails = []

    for cid in range(1, 10):
        name = NAMES[cid]
        lo = C1 + procs[cid]
        later = [v for v in bounds if v > procs[cid]]
        hi = C1 + (min(later) if later else 0xBE09)   # else: the bank's free hole
        tbl = act_table(rom, lo)
        print(f"== {name}  proc ${0xC1:02X}:{procs[cid]:04X}  act table ${0xC1:02X}:{tbl - C1:04X} ==")

        # negative control: a null slot offers nothing
        null_handler = word(rom, tbl + 0x2B * 2)
        if null_handler and routes_of(rom, null_handler, lo, hi):
            fails.append(f"{name}: null act 0x2B yielded routes")

        jump_tables = set()
        spec_route = False
        for act in (0x06, 0x07, 0x08):
            h = word(rom, tbl + act * 2)
            rr = routes_of(rom, h, lo, hi)
            spec_route = spec_route or any(r[0].startswith("spec") for r in rr)
            desc = ", ".join(f"{n}(Y=${y:04X})" if y is not None else n for n, y in rr) or "NO ROUTES"
            print(f"  jump act {act:02X} -> ${h:04X}: {desc}")
            for n, y in rr:
                if n == "normals" and y:
                    jump_tables.add(y)

        if name == "Uranus" and jump_tables != URANUS_JUMP_TABLES:
            fails.append(f"Uranus jump tables {sorted(map(hex, jump_tables))} != documented $7B0D/$7B19")
        want = name in HAS_AIR_SPECIAL_ROUTE
        if spec_route != want:
            fails.append(f"{name}: jump specials route = {spec_route}, documented census says {want}")

        # the air normals those stance tables name
        air_acts = {}
        for jt in sorted(jump_tables):
            recs = [(rom[C1 + jt + i * 3], rom[C1 + jt + i * 3 + 1], rom[C1 + jt + i * 3 + 2])
                    for i in range(4)]
            print(f"  stance table ${jt:04X}: " + "  ".join(
                f"[thr={a} far={b:02X} close={c:02X}]" for a, b, c in recs))
            for _, far, close in recs:
                for act in {far, close}:
                    air_acts[act] = word(rom, tbl + act * 2)
        for act in sorted(air_acts):
            rr = routes_of(rom, air_acts[act], lo, hi)
            desc = ", ".join(f"{n}(Y=${y:04X})" if y is not None else n for n, y in rr) or "NO ROUTES"
            print(f"  air normal {act:02X} -> ${air_acts[act]:04X}: {desc}")
        print()

    if fails:
        print("CONTROL FAILURES:")
        for f in fails:
            print("  " + f)
        return 1
    print("controls green: Uranus anchor tables, documented specials census, null-act negative")
    return 0


if __name__ == "__main__":
    sys.exit(main())
