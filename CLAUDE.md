# CLAUDE.md — SMS Uranus infinite patch

> **STATUS (2026-08-24): a THIRD build line now exists — the exp-tier ANIME-FIGHTER
> conversion (air dashes/cancels/blocks/juggles, two launchers, a clash; all nine
> characters, one generator `tools/exp_animeroster.py`). Its authority is
> `docs/project/anime_fighter_feasibility.md`; it is NOT a numbered patch and builds
> from clean only. The releases below are unchanged by it.**
>
> **STATUS (2026-08-08): the original objective is DONE and the project has grown well beyond it
> — 17 patches + 2 variants (balance, training mode, taunts/Guts, menu/config edits), plus the
> 100-series: **Sailor Saturn ported in from Super S**. What ships is `release/` **Rev. S-02**
> and **Rev. SS-03** (the two sides are independent — only the side whose bytes
> move gets a new number). The only ACTIVE work item is **patch 16, menu translation**
> (mechanism: `docs/game/menu_system.md`; the working record: `docs/project/menu_text.md`).
> Before doing anything, read `HANDOFF.md` (operational map), `docs/project/NEXT_SESSION.md`
> (60-second orientation), `docs/project/patch_index.md` (registry), and `docs/project/patch_notes.md`
> (per-patch detail). The sections below are the original brief, kept for history.**

## THE MEASUREMENT RULE (non-negotiable, governs everything below)

> **Any data should come from measurements, NEVER guesses. When you don't know
> you measure, when you think you know you measure to check against the
> measurement, and when you're sure you don't have to measure is precisely when
> you absolutely must measure. We do not compromise: the source of truth is the
> original code.**

This is the project's first rule, and it outranks convenience, plausibility and
prior art — including this file. The third clause is the one that bites:
**certainty is the failure signal, not the safety signal**, because confidence is
exactly when the check gets skipped. Every documented fact this project has lost
was lost that way — five ROM facts died the first time the doc tables were
re-derived, four more in the Saturn identity paragraph the entire port rested on,
a recorded hash was stale in four documents while the builder had never changed.

How it applies to code analysis, concretely:

* **No number reaches a doc, a commit message, a patch or a plan without a run
  that produced it in that session.** Inherited numbers are re-derived, not
  carried forward. A figure in a document is a claim, and an unmeasured claim is
  a guess wearing a citation.
* **A number someone else reports is a filed count, not a measurement** — that
  includes a subagent, an issue, a wiki, and this repo's own older notes. Label
  the provenance and re-derive anything load-bearing. (Trap 17: counts are stale
  in BOTH directions.) A report was overturned by reading the ROM as recently as
  2026-08-10: the document it called wrong was right.
* **A number produced with tooling later found defective is contaminated** —
  discard and re-measure. Never adjust it.
* **Measure the negative too.** A predicate that cannot fail where it should is
  not evidence: re-run it at a wrong address, a wrong base, a wrong seed. And a
  negative control is code, so it is wrong until it has failed on purpose
  (HANDOFF traps 20, 22).
* **Reject on measurements, not on intuition.** When an approach is dropped, say
  what was measured and what the number was, so the rejection is auditable.
* **Thresholds live where the run that produced them lives.** A tool recomputes
  its own floors and ceilings; it never hardcodes a figure typed out of a plan.
* **Check the framing before trusting a verdict about a byte.** On this CPU
  "is there an instruction here" has no answer until you say where the decoder
  started — and starting somewhere convenient invents one.

## Objective (REVISED 2026-07-10 — supersedes the 2LP wording below)
Per Dustloop, the real Uranus Infinite™ is `[2LP > 2HP > 66]xN` — the load-bearing link
is **2HP canceled into the 66 forward dash** (2HP's recovery state 0x58 is treated as
neutral, letting the dash come out during recovery). Patch so that this dash cancel
requires a 1-frame link instead of being bufferable: increase the effective recovery of
**crouching heavy punch (2HP)** before the dash becomes available.
(Original objective text — targeting the crouching light attack — kept for history;
all constraints, environment and Definition of done below still apply, applied to 2HP.)

## Original objective (superseded)
Patch Bishoujo Senshi Sailor Moon S: Jougai Rantou!? (SFC, Japan) so Sailor Uranus's
crouching-jab infinite is no longer bufferable: increase the recovery of her
**crouching light attack** by enough frames that the loop requires a 1-frame link.
Deliverable = a BPS/IPS patch against the clean ROM + a writeup of what bytes changed and why.

## Ground truth (verified — do NOT re-derive; details in docs/game/sms_quickref.md)
- Clean ROM SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c`, HiROM+FastROM,
  headerless, file offset = SNES addr & 0x3FFFFF.
- Characters: 1 Moon … **6 Uranus** … 9 Chibimoon. (10 "Saturn" = Super S carry-over,
  **not in the clean ROM** — no assets, which is why the extractors stop at 9. She IS
  playable in the **Rev. SS** builds, ported from Super S: `docs/project/saturn/`.)
- Player structs: P1 `$7E:1000`, P2 `$7E:1080` (0x80 bytes).
  +0x00 charID, +0x01 actionID, +0x02 step, +0x06/07 tick/frame,
  +0x40 hitbox idx, +0x41 hurtbox idx, +0x42 collision idx,
  +0x43 attack_connected latch (hitstop is +0x4D), +0x44 attackID, +0x47 hitstun?, +0x49 HP.
- Uranus box data (ROM, bank $8A): hit `0xAE3E1` (21×8B), hurt `0xAE489` (81×16B),
  coll `0xAE999` (6×8B). Box = [x_off_R, w_R, x_off_L, w_L, y_off, h, flags, ?].
- Hit resolution: `$C0:BFC0`; on-hit tables `[dmg, hitstun, level, flags]` at
  `$C0:CDD5` + variants (CE15…D015), indexed by (attackID>>1)*4.
  **These tables look GLOBAL (strength-class indexed). Do not patch hitstun here
  unless proven per-character — it would change every character's jab.**
- Per-frame object update: `JSL $C1:0000` (state procs ≈ $C1:122A, $C1:15BD).
  Animation scripts (the thing we must find) set +0x40/41/42 with per-step durations.
- Char load `$C0:879B`; manifest ptr table `$E0:0238+id*2`; one manifest pointer's
  payload is copied/expanded to `$7E:6A00` by `$C0:916B` (suspected animation data —
  if scripts execute from WRAM, the ROM source must be located through this copy).
- Action IDs: universal states 0x00–0x2A documented in
  vendor/sms-training-mode/SailorMoonS.lua (attack IDs for Uranus ≈ 0x2B+;
  her light-attack recovery-cancel states are {0x42,0x48,0x54,0x58} per that Lua —
  useful to identify which action IDs are the jabs).

## Environment & conventions
- Emulator: build Mesen2 headless (preferred) or BizHawk/mono for Lua write-callbacks
  and frame advance. Scripts in tools/, traces in traces/, keep them out of git if huge.
- Disassembler: pelrun/Dispel — vendored at tools/Dispel/, build once with
  `cc -O2 -o dispel main.c 65816.c`. (An earlier tools/disasm65816.py no longer exists;
  tools/asm65816.py is the assembler, not a disassembler.)
- Maintain docs/game/annotations.md (address → label/comment). Commit after each finding.
- Never patch the ROM in place; generate patches via flips (BPS) from build/.
- All timing claims must be validated by frame-advance in emulator, not inferred
  (the measurement rule at the top of this file, applied to timing specifically).
- The engine processes attacks starting the frame AFTER action start (per Lua comments);
  watch for a possible 30Hz update quirk when counting frames.

## Definition of done
1. ROM offset + format of Uranus's crouching-light animation script identified,
   with the specific duration byte(s) controlling recovery.
2. Patch increases recovery by N frames where N is derived from measurement:
   current frame advantage on hit vs the game's buffer window, such that the loop
   becomes a 1f link. Show the arithmetic.
3. Verified in-emulator: (a) the old bufferable timing no longer connects,
   (b) a frame-perfect re-press still does (infinite becomes 1f link, not removed),
   (c) no side effects on her other moves (scripts may share data/pointers).
4. BPS patch + docs/project/patch_notes.md documenting every changed byte.

## Reference material
- docs/game/sms_hacking_playbook.md — **the distilled rules and traps** (methodology tier for this game; its agent rendition is `.claude/skills/sms-romhacking/`, the donor-port tier is `docs/project/saturn/porting_lessons.md` + `.claude/skills/supers-porting/`, and the general/SNES tiers are user-level skills — pairs ID-locked by `tools/checkskills.py`)
- docs/game/sms_engine_internals.md — **how the engine works, by subsystem** (the synthesis; start here to understand/modify the game)
- docs/game/sms_data_architecture.md — **where the data lives and what shape it is** (four memory maps, the object struct, the record catalogue)
- docs/game/sms_quickref.md — the one-page address card (start here to orient, then follow its pointers)
- docs/game/sms_all_boxes.json + tools/extract_sms_hitboxes.py
- vendor/sms-training-mode/ — sprntgd's Lua (RAM map source) & WLA-DX hook examples;
  its color-edit patcher shows a working ROM-expansion/hook workflow if in-place
  editing proves too tight. The Big Zam hack proves hook-based balance edits work.
- Dustloop SMS wiki — community frame data to sanity-check measurements.
