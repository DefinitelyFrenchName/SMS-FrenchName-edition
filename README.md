# SMS Uranus balance/feature patches

Target: Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan),
clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` (HiROM+FastROM, headerless,
file offset = SNES addr & 0x3FFFFF).

This document covers nine independent patches (1–5 gameplay/cosmetic, 6–9 optional/
experimental). Each is a separate stackable BPS built by its own `tools/mkpatchN.py`; their
edits are byte-disjoint, so they combine cleanly. **New here? Read `HANDOFF.md` first** — it is
the operational map (current state, deliverables, tooling, findings, gotchas).

## Deliverables & how they stack

| Patch                                     | What                                                         | Builder                 | Standalone BPS                                         | Patched SHA-1 |
| ----------------------------------------- | ------------------------------------------------------------ | ----------------------- | ------------------------------------------------------ | ------------- |
| 1. 1f-link **(CANONICAL)**                | Uranus infinite → **1-frame meaty** (N=6): exactly one press connects, and it's an unblockable-by-block meaty (escapable by invincible reversal / jump) | `tools/mkpatch.py 0x04` | `build/sms_uranus_infinite_1f.bps` (+`.ips`)           | `c773d99a…`   |
| 1b. 1f-link (true combo)                  | **Alternative to patch 1** — true unblockable 1-frame combo (N=5); wider (2-frame connect: combo@0 + meaty@+1) | `tools/mkpatch.py 0x05` | `build/sms_uranus_infinite_1f_truecombo.bps` (+`.ips`) | `8966c119…`   |
| 2. Dash-fix                               | Remove reversal-dash invincibility                           | `tools/mkpatch2.py`     | `build/sms_dashfix.bps` (+`.ips`)                      | `07d760fe…`   |
| 3. Palettes                               | Sprint / Big Zam extended character colors ( + "FrenchName" rom header for easy rom ID) | `tools/mkpatch3.py`     | `build/sms_palettes.bps`                               | `291f6474…`   |
| 4. Title                                  | Title subtitle → "FrenchName ver. X.Y"                       | `tools/mkpatch4.py`     | `build/sms_title.bps`                                  | `e5dce7d5…`   |
| 5. Dash dist                              | Cut Uranus forward-dash distance ~1/3                        | `tools/mkpatch5.py`     | `build/sms_dashdist.bps`                               | `99acb686…`   |
| 6. Dash i-frames **(OPTIONAL)**           | Uranus forward dash gains ~6 strike-invuln frames mid-move   | `tools/mkpatch6.py`     | `build/sms_dashinvuln.bps` (+`.ips`)                   | `34c5d458…`   |
| 7. Pluto 5HP **(OPTIONAL)**               | Pluto 5HP hitbox extended down to hit crouchers (all but Chibi) | `tools/mkpatch7.py`     | `build/sms_pluto5hp.bps`                               | `fc757936…`   |
| 8. Venus throw tech **(OPTIONAL)**        | Venus 6HP throw mash-escape window 6f → 13f (standard-ish; Jupiter=15f) | `tools/mkpatch8.py`     | `build/sms_venustech.bps`                              | `63ce0748…`   |
| 9. Neptune fireball **(OPTIONAL)**        | Deep Submerge fireball hitbox tracks the descending sprite (was stuck at head level) | `tools/mkpatch9.py`     | `build/sms_neptune_ds.bps`                             | `d5ee12a3…`   |
| 10. In-match combo counter **(OPTIONAL)** | Live combo-hit counter rendered by the base game under each attacker's bar (no overlay needed) | `tools/mkpatch10.py`    | `build/sms_combocounter.bps`                           |               |
