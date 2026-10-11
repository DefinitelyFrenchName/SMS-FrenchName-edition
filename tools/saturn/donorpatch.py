#!/usr/bin/env python3
"""donorpatch.py — the two-ROM ("donor") patch format for Rev. SS: library shared by its builder and its applier.

WHY THIS EXISTS. A plain .bps diffs the clean SMS ROM against the patched one, so
everything Saturn brings from Super S — sprites, voice, her stage — has no source
in SMS and lands in the patch as raw bytes: Rev.SS-03.bps was 153 KB, most of it
Super S content. That contradicted the project's own rule (README: Saturn's
patches "embed ported game content", so they are not distributed).

THE FORMAT. Still plain BPS (byuu's spec, tools/Flips/bps_spec.md), but diffed
against a SOURCE that the player rebuilds from the two cartridges they own:

    source = clean SMS ROM  ||  clean Super S ROM  ||  decompress(Super S, s) for s in streams

`streams` are file offsets of Super S LZ streams (tools/saturn/supers_lz.py):
the stage port stores Super S art DECOMPRESSED, and decompressed bytes exist in
neither ROM, so the applier re-derives them from the player's own Super S. With
that source, everything copied from Super S becomes a SourceCopy instruction
(an offset and a length), never bytes. What the patch still carries literally is
this project's own code, tables and fixups — `audit()` measures that, and the
builder refuses a patch in which a donor run survives verbatim.

The patch is self-describing: its BPS metadata field is JSON naming the format,
both input SHA-1s, the stream list and the target SHA-1. The browser applier
(tools/saturn/applier/donor_applier.js) implements the same steps and is held
byte-for-byte to this file by tools/saturn/test_donorpatch.sh.
"""
import json
import zlib
from hashlib import sha1

import supers_lz as LZ

FORMAT = "sms-donor-bps/1"


def strip_copier_header(data):
    """Drop a 512-byte copier header if present (same rule as smspaths)."""
    return data[0x200:] if len(data) % 0x8000 == 0x200 else data


def build_source(sms, supers, streams):
    """The BPS source: SMS || Super S || each listed Super S LZ stream, decompressed."""
    parts = [sms, supers]
    for off in streams:
        parts.append(LZ.lz_decompress(supers, off))
    return b"".join(parts)


# ── BPS ─────────────────────────────────────────────────────────────────────
def _vint_read(b, i):
    d, s = 0, 1
    while True:
        x = b[i]
        i += 1
        d += (x & 0x7F) * s
        if x & 0x80:
            return d, i
        s <<= 7
        d += s


def _vint_write(n):
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return bytes(out)
        out.append(x)
        n -= 1


def parse_header(patch):
    """-> (source_size, target_size, metadata_bytes, offset_of_first_action)."""
    if patch[:4] != b"BPS1":
        raise ValueError("not a BPS patch")
    i = 4
    ss, i = _vint_read(patch, i)
    ts, i = _vint_read(patch, i)
    ms, i = _vint_read(patch, i)
    return ss, ts, patch[i:i + ms], i + ms


def read_meta(patch):
    meta = json.loads(parse_header(patch)[2].decode("utf-8"))
    if meta.get("format") != FORMAT:
        raise ValueError(f"not a {FORMAT} patch (format={meta.get('format')!r})")
    return meta


def with_meta(patch, meta):
    """Return `patch` with its metadata replaced by `meta` (JSON) and the patch CRC redone."""
    ss, ts, _old, body = parse_header(patch)
    m = json.dumps(meta, sort_keys=True, separators=(",", ":")).encode("utf-8")
    out = b"BPS1" + _vint_write(ss) + _vint_write(ts) + _vint_write(len(m)) + m + patch[body:-4]
    return out + zlib.crc32(out).to_bytes(4, "little")


def bps_apply(patch, source):
    """Apply a BPS patch, verifying all three CRC32s. -> target bytes."""
    if zlib.crc32(patch[:-4]) != int.from_bytes(patch[-4:], "little"):
        raise ValueError("patch CRC mismatch: the patch file is damaged")
    ss, ts, _meta, i = parse_header(patch)
    if len(source) != ss or zlib.crc32(source) != int.from_bytes(patch[-12:-8], "little"):
        raise ValueError("source CRC/size mismatch")
    out = bytearray(ts)
    op = sr = tr = 0
    end = len(patch) - 12
    while i < end:
        d, i = _vint_read(patch, i)
        act, ln = d & 3, (d >> 2) + 1
        if act == 0:                      # SourceRead
            out[op:op + ln] = source[op:op + ln]
        elif act == 1:                    # TargetRead
            out[op:op + ln] = patch[i:i + ln]
            i += ln
        else:
            r, i = _vint_read(patch, i)
            r = -(r >> 1) if r & 1 else r >> 1
            if act == 2:                  # SourceCopy
                sr += r
                out[op:op + ln] = source[sr:sr + ln]
                sr += ln
            else:                         # TargetCopy (may overlap: byte by byte)
                tr += r
                for k in range(ln):
                    out[op + k] = out[tr + k]
                tr += ln
        op += ln
    if op != ts or zlib.crc32(out) != int.from_bytes(patch[-8:-4], "little"):
        raise ValueError("target CRC/size mismatch")
    return bytes(out)


def literal_runs(patch):
    """Yield (target_offset, bytes) for every TargetRead action: what the patch carries verbatim."""
    _ss, _ts, _meta, i = parse_header(patch)
    op, end = 0, len(patch) - 12
    while i < end:
        d, i = _vint_read(patch, i)
        act, ln = d & 3, (d >> 2) + 1
        if act == 1:
            yield op, patch[i:i + ln]
            i += ln
        elif act in (2, 3):
            _r, i = _vint_read(patch, i)
        op += ln


def referenced_source(patch):
    """Yield (source_offset, length) for every SourceCopy/SourceRead: what the patch borrows."""
    _ss, _ts, _meta, i = parse_header(patch)
    op = sr = 0
    end = len(patch) - 12
    while i < end:
        d, i = _vint_read(patch, i)
        act, ln = d & 3, (d >> 2) + 1
        if act == 0:
            yield op, ln
        elif act == 1:
            i += ln
        else:
            r, i = _vint_read(patch, i)
            r = -(r >> 1) if r & 1 else r >> 1
            if act == 2:
                sr += r
                yield sr, ln
                sr += ln
        op += ln


# ── apply, as a player runs it ──────────────────────────────────────────────
def identify(files, meta):
    """Map two dumps (any order, copier headers allowed) to (sms, supers) by SHA-1."""
    want = {meta["sms_sha1"]: "sms", meta["supers_sha1"]: "supers"}
    got = {}
    for name, data in files:
        data = strip_copier_header(data)
        h = sha1(data).hexdigest()
        if h not in want:
            raise ValueError(f"{name}: SHA-1 {h} is neither the clean Sailor Moon S "
                             f"({meta['sms_sha1']}) nor the clean Super S ({meta['supers_sha1']})")
        got[want[h]] = data
    for role, label in (("sms", "Sailor Moon S"), ("supers", "Sailor Moon SuperS")):
        if role not in got:
            raise ValueError(f"the clean {label} ROM is missing")
    return got["sms"], got["supers"]


def apply(patch, sms, supers):
    meta = read_meta(patch)
    streams = [int(s, 16) for s in meta["streams"]]
    out = bps_apply(patch, build_source(sms, supers, streams))
    if sha1(out).hexdigest() != meta["target_sha1"]:
        raise ValueError("output SHA-1 does not match the patch's target")
    return out


# ── audit: what does the patch carry verbatim? ──────────────────────────────
def donor_corpus(supers, max_jobs=400):
    """Every Super S LZ stream the job table points at, decompressed (junk entries skipped)."""
    seen, out = set(), []
    for idx in range(max_jobs):
        src, _vram, _flags = LZ.job_entry(supers, idx)
        if src in seen or not (0 < src < len(supers) - 2):
            continue
        seen.add(src)
        try:
            out.append(LZ.lz_decompress(supers, src))
        except (ValueError, IndexError):
            continue
    return out


def audit(patch, sms, supers, k=8, min_run=16, verbatim=0.9):
    """Measure the patch's literal payload against the donor.

    Returns a dict:
      literal_bytes   total TargetRead bytes
      donor_8grams    literal bytes covered by a k-gram found in Super S (raw or
                      decompressed) and NOT in SMS — i.e. donor bytes shipped as-is
      verbatim_runs   [(target_off, len, ratio, where)] literal runs >= min_run that
                      are >= `verbatim` position-identical to a donor region
      near_runs       same, for ratios in [0.5, verbatim) — transformed donor data
                      (rebased pointer tables, edited tilemaps): reported, not refused
    """
    corpus = donor_corpus(supers)
    donors = {"Super S": supers, "Super S (decompressed)": b"".join(corpus)}

    def grams(b):
        return {b[j:j + k] for j in range(len(b) - k + 1)}

    sms_g = grams(sms)
    donor_g = set().union(*(grams(b) for b in donors.values()))
    index = {}
    for name, b in donors.items():
        for j in range(len(b) - 4):
            g = b[j:j + 4]
            if len(set(g)) > 2:
                index.setdefault(g, []).append((name, j))

    lit = cov_total = 0
    verbatim_runs, near_runs = [], []
    for op, data in literal_runs(patch):
        ln = len(data)
        lit += ln
        cov = bytearray(ln)
        for j in range(ln - k + 1):
            g = data[j:j + k]
            if g in donor_g and g not in sms_g and len(set(g)) > 2:
                cov[j:j + k] = b"\x01" * k
        cov_total += sum(cov)
        if ln < min_run:
            continue
        votes = {}
        for j in range(ln - 4):
            for name, p in index.get(data[j:j + 4], [])[:50]:
                votes[(name, p - j)] = votes.get((name, p - j), 0) + 1
        best = (0.0, None)
        for (name, base), _n in sorted(votes.items(), key=lambda kv: -kv[1])[:5]:
            b = donors[name]
            if 0 <= base and base + ln <= len(b):
                r = sum(1 for t in range(ln) if b[base + t] == data[t]) / ln
                if r > best[0]:
                    best = (r, name)
        if best[0] >= verbatim:
            verbatim_runs.append((op, ln, best[0], best[1]))
        elif best[0] >= 0.5:
            near_runs.append((op, ln, best[0], best[1]))
    return {"literal_bytes": lit, "donor_8grams": cov_total,
            "verbatim_runs": verbatim_runs, "near_runs": near_runs}
