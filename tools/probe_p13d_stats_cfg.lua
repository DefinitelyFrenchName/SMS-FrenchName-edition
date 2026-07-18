-- P1 attacker stats: 1070 attack, 1073 special, 1074 secret; P2 defender: 10F1 defense, 10F2 health
MEASURES = {
  {addr=0,      val=0, move="jab"}, {addr=0,      val=0, move="fb"},
  {addr=0x1070, val=1, move="jab"}, {addr=0x1070, val=3, move="jab"}, {addr=0x1070, val=7, move="jab"},
  {addr=0x1070, val=3, move="fb"},  {addr=0x1070, val=7, move="fb"},
  {addr=0x10F1, val=1, move="jab"}, {addr=0x10F1, val=3, move="jab"}, {addr=0x10F1, val=7, move="jab"},
  {addr=0x10F1, val=3, move="fb"},  {addr=0x10F1, val=7, move="fb"},
  {addr=0x1073, val=3, move="jab"}, {addr=0x1073, val=1, move="fb"},  {addr=0x1073, val=3, move="fb"}, {addr=0x1073, val=7, move="fb"},
  {addr=0x1074, val=3, move="fb"},  {addr=0x1074, val=7, move="fb"},
  {addr=0x10F2, val=7, move="jab"},
}
