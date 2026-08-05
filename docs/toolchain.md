# Toolchain — the four things this repo does not contain

Everything in `tools/` is ours and is tracked. Four external pieces are **not**,
and a fresh clone has none of them. That is deliberate — two are copyrighted, one
is third-party work that isn't ours to vendor, and one is a 100 MB app — but it
used to be undocumented, so a clone failed with `ModuleNotFoundError` and no hint
(issue #3).

**Run `tools/health.sh` first.** It reports exactly which of these are missing and
what that stops you doing, and it exits 0 when the tree itself is consistent.

| Piece | Where it goes | Get it from | Without it |
|---|---|---|---|
| **Clean ROM** — *Bishoujo Senshi Sailor Moon S: Jougai Rantou!?* (SFC, Japan), SHA-1 `bc0e29ee383574443226695215496eb0d09aaa1c` | `$SMS_ROM_DIR`, `roms/`, or `../roms/` (preferred: above the tree, so it can never be committed) | not distributed | nothing builds |
| **Super S donor** — *Zenin Sanka!!*, SHA-1 `1ada34177e7384612ae83464288f3860e4c4426e` | same directory | not distributed | no Saturn build (patch 100/101, Rev. SS) |
| **Mesen 2.1.1** | `tools/Mesen.app` (macOS) | https://github.com/SourMesen/Mesen2/releases — any Mesen 2 with the Lua script window | no regression suite, no Saturn gate, no probes |
| **Floating IPS (flips)** | `tools/Flips/flips` | https://github.com/Alcaro/Flips | no `.bps` can be created or applied |
| **sprntgd's sms-training-mode** | `vendor/sms-training-mode/` | the community release this project builds on (see the acknowledgement in `README.md`) | **patch 3 only** — it re-applies that patcher's palette work |

`tools/Dispel/` (disassembler) is optional: build it once with
`cc -O2 -o dispel main.c 65816.c` in that directory. Nothing in the build or test
path needs it.

## What a fresh clone *can* do

Everything that needs none of the above:

```bash
tools/health.sh          # generated artifacts in sync, syntax, release folder
python3 tools/mksigs.py --check
python3 tools/mkrelease.py --check
```

Those are also what CI runs (`.github/workflows/health.yml`) — a hosted runner
has no ROM and no emulator, so it verifies the source tree against itself and
says so. **A green tick there is not a verified build.** The real gates are local:

```bash
ROM=build/SailorMoonS_Rev_S-NN.sfc  tools/run.sh tools/test_regression.lua 900
ROM=build/SailorMoonS_Rev_SS-NN.sfc tools/saturn/verify_saturn.sh
```
