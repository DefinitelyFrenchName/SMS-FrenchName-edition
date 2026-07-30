-- gamestate.lua — per-frame RAM snapshot of both fighters (+ projectile slots) and the
-- ring-buffer history. Everything downstream (framedata, HUD, dummy) reads ctx.snap/ctx.hist.
local M = {}

function M.init(ctx)
  local C = ctx.C
  local r = function(a) return emu.read(a, C.WRAM) end
  local O = C.OFF

  local HIST_N = 600
  ctx.hist = { n = 0, head = 0, cap = HIST_N }   -- entries at ctx.hist[1..cap]

  local function samplePlayer(base)
    return {
      char = r(base + O.charID), act = r(base + O.act), step = r(base + O.step),
      tick = r(base + O.tick), frameIdx = r(base + O.frameIdx),
      facing = r(base + O.facing), aflag = r(base + O.aflag) % 2,
      x = r(base + O.posX) + 256 * r(base + O.posX + 1), y = r(base + O.posY),
      hb = r(base + O.hb), hub = r(base + O.hub), coll = r(base + O.coll),
      connected = r(base + O.connected), atkID = r(base + O.atkID),
      hurt = r(base + O.hurt), hp = r(base + O.hp), maxhp = r(base + O.maxhp),
      stop = r(base + O.hitstop), btn = r(base + O.btnHeld), mash = r(base + O.mash),
    }
  end

  local function sampleProj(base)
    local pc = r(base + O.charID)
    return { alive = pc ~= 0 and pc < 0x80, hb = r(base + O.hb), char = pc,
             y = r(base + O.posY) }
  end

  local function step()
    ctx.prev = ctx.snap
    local raw = {}
    for i = 1, 2 do
      raw[i] = r(C.RAW_PAD[i] + 1) * 256 + r(C.RAW_PAD[i])
    end
    ctx.snap = {
      f = ctx.t,
      p = { samplePlayer(C.BASE[1]), samplePlayer(C.BASE[2]) },
      proj = { sampleProj(C.PROJ[1]), sampleProj(C.PROJ[2]) },
      raw = raw,
      cam = r(C.CAMERA_X) + 256 * r(C.CAMERA_X + 1),
    }
    -- ring buffer push (entry is enriched in-place later by framedata: cls/inv/frz)
    local h = ctx.hist
    h.head = (h.head % h.cap) + 1
    if h.n < h.cap then h.n = h.n + 1 end
    h[h.head] = ctx.snap
  end

  -- side helper: is player i on the left?
  function M.onLeft(i)
    local s = ctx.snap
    if not s then return i == 1 end
    local other = 3 - i
    return s.p[i].x <= s.p[other].x
  end

  -- history accessor: k frames ago (0 = current); nil if out of range
  function M.ago(k)
    local h = ctx.hist
    if k >= h.n then return nil end
    local idx = h.head - k
    if idx < 1 then idx = idx + h.cap end
    return h[idx]
  end

  function M.reset()
    ctx.hist.n = 0; ctx.hist.head = 0
    ctx.snap, ctx.prev = nil, nil
  end

  table.insert(ctx.hooks.frame, step)   -- runs first: main registers modules in order
  table.insert(ctx.hooks.reset, M.reset)  -- issue #15: history must not survive savestate loads
end

return M
