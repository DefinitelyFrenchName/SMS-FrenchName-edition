# Per-character ROM maps

One page per fighter, **generated** by `tools/mkcharmap.py` — every address is
read out of the clean ROM at generation time, so these cannot drift from the
cartridge or from each other. Run `mkcharmap.py --check` to prove it.

The engine-wide map is [`../sms_data_architecture.md`](../sms_data_architecture.md);
these pages hold only what differs per character.

| charID | Character | proc block | hit / hurt / coll | poses | cels | d48 |
|---|---|---|---|---|---|---|
| 1 | [Moon](moon.md) | `$C1:270B` (4206 B) | `17` / `89` / `6` | 122 | 103 | 0 |
| 2 | [Mercury](mercury.md) | `$C1:3779` (4141 B) | `22` / `87` / `6` | 117 | 105 | 0 |
| 3 | [Mars](mars.md) | `$C1:47A6` (4320 B) | `33` / `96` / `6` | 125 | 114 | 0 |
| 4 | [Jupiter](jupiter.md) | `$C1:5886` (4740 B) | `26` / `104` / `6` | 122 | 113 | **1** |
| 5 | [Venus](venus.md) | `$C1:6B0A` (3816 B) | `18` / `88` / `6` | 118 | 107 | 0 |
| 6 | [Uranus](uranus.md) | `$C1:79F2` (5040 B) | `21` / `81` / `6` | 115 | 99 | 0 |
| 7 | [Neptune](neptune.md) | `$C1:8DA2` (4200 B) | `25` / `96` / `6` | 134 | 120 | **2** |
| 8 | [Pluto](pluto.md) | `$C1:9E0A` (4157 B) | `21` / `77` / `6` | 105 | 92 | 0 |
| 9 | [Chibi Moon](chibimoon.md) | `$C1:AE47` (4025 B) | `16` / `76` / `6` | 103 | 85 | 0 |

Two things that table says at a glance: **every character has exactly 6 push
boxes**, and **first-hit defense is non-zero for only two of the nine** —
Jupiter 1 and Neptune 2, which is the entire source of the "damage varies"
folklore.
