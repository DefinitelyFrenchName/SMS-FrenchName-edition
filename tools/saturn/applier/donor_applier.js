// donor_applier.js — the browser twin of tools/saturn/donorpatch.py (apply side only).
//
// Same format, same steps, same refusals: identify the two dumps by SHA-1 (any
// order, copier header stripped), rebuild SOURCE = SMS || Super S || the listed
// Super S LZ streams decompressed, apply the BPS with all three CRC32s checked,
// and require the target SHA-1 from the patch's own metadata.
// Held byte-for-byte to the Python tool of record by tools/saturn/test_donorpatch.sh.
// Plain script (no modules): inlined into release/Rev.SS-NN.html by
// tools/saturn/mkapplier.py, and loadable by node for that test.
"use strict";
const DonorApplier = (() => {
  const FORMAT = "sms-donor-bps/1";

  class ApplierError extends Error {}

  async function sha1Hex(bytes) {
    const d = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes));
    return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
  }

  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(b, end = b.length) {
    let c = 0xffffffff;
    for (let i = 0; i < end; i++) c = CRC_TABLE[(c ^ b[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }
  const u32 = (b, i) => (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0;

  function stripCopierHeader(b) {
    return b.length % 0x8000 === 0x200 ? b.subarray(0x200) : b;
  }

  // supers_lz.lz_decompress, line for line.
  function lzDecompress(rom, src) {
    let count = rom[src] | (rom[src + 1] << 8);
    src += 2;
    const out = [];
    while (count > 0) {
      let ctrl = rom[src++];
      let bits = 8;
      while (bits > 0 && count > 0) {
        let k = 0;
        while (bits > 0 && ctrl & 1) { ctrl >>= 1; bits--; k++; }
        if (k) {
          for (let i = 0; i < k; i++) out.push(rom[src + i]);
          src += k;
          count -= k;
          if (count <= 0) break;
        }
        if (bits === 0) break;
        ctrl >>= 1;
        bits--;
        const w = rom[src] | (rom[src + 1] << 8);
        src += 2;
        const start = out.length - (w >> 4) - 1;
        if (start < 0) throw new ApplierError("LZ back-reference before start");
        for (let i = 0; i < (w & 0xf) + 3; i++) out.push(out[start + i]);
        count--;
      }
    }
    return Uint8Array.from(out);
  }

  function vint(b, pos) {
    let d = 0, s = 1;
    for (;;) {
      const x = b[pos.i++];
      d += (x & 0x7f) * s;
      if (x & 0x80) return d;
      s *= 128;
      d += s;
    }
  }

  function parseHeader(p) {
    if (p[0] !== 0x42 || p[1] !== 0x50 || p[2] !== 0x53 || p[3] !== 0x31) throw new ApplierError("not a BPS patch");
    const pos = { i: 4 };
    const ss = vint(p, pos), ts = vint(p, pos), ms = vint(p, pos);
    const meta = p.subarray(pos.i, pos.i + ms);
    pos.i += ms;
    return { ss, ts, meta, pos };
  }

  function readMeta(p) {
    const meta = JSON.parse(new TextDecoder().decode(parseHeader(p).meta));
    if (meta.format !== FORMAT) throw new ApplierError(`not a ${FORMAT} patch`);
    return meta;
  }

  function bpsApply(p, source) {
    const n = p.length;
    if (crc32(p, n - 4) !== u32(p, n - 4)) throw new ApplierError("patch CRC mismatch: the patch is damaged");
    const { ss, ts, pos } = parseHeader(p);
    if (source.length !== ss || crc32(source) !== u32(p, n - 12)) throw new ApplierError("source CRC/size mismatch");
    const out = new Uint8Array(ts);
    let op = 0, sr = 0, tr = 0;
    const end = n - 12;
    while (pos.i < end) {
      const d = vint(p, pos);
      const act = d % 4, len = Math.floor(d / 4) + 1;
      if (act === 0) {
        out.set(source.subarray(op, op + len), op);
      } else if (act === 1) {
        out.set(p.subarray(pos.i, pos.i + len), op);
        pos.i += len;
      } else {
        let r = vint(p, pos);
        r = r & 1 ? -Math.floor(r / 2) : Math.floor(r / 2);
        if (act === 2) {
          sr += r;
          out.set(source.subarray(sr, sr + len), op);
          sr += len;
        } else {
          tr += r;
          for (let k = 0; k < len; k++) out[op + k] = out[tr + k];
          tr += len;
        }
      }
      op += len;
    }
    if (op !== ts || crc32(out) !== u32(p, n - 8)) throw new ApplierError("target CRC/size mismatch");
    return out;
  }

  // files: [{name, bytes: Uint8Array}] — two dumps, any order.
  async function identify(files, meta) {
    const want = { [meta.sms_sha1]: "sms", [meta.supers_sha1]: "supers" };
    const got = {};
    for (const f of files) {
      const b = stripCopierHeader(f.bytes);
      const h = await sha1Hex(b);
      if (!(h in want)) {
        throw new ApplierError(`${f.name}: SHA-1 ${h} is neither the clean Sailor Moon S (${meta.sms_sha1}) nor the clean Super S (${meta.supers_sha1})`);
      }
      got[want[h]] = b;
    }
    if (!got.sms) throw new ApplierError("the clean Sailor Moon S ROM is missing");
    if (!got.supers) throw new ApplierError("the clean Sailor Moon SuperS ROM is missing");
    return got;
  }

  function buildSource(sms, supers, streams) {
    const parts = [sms, supers, ...streams.map((s) => lzDecompress(supers, parseInt(s, 16)))];
    const out = new Uint8Array(parts.reduce((a, b) => a + b.length, 0));
    let at = 0;
    for (const b of parts) { out.set(b, at); at += b.length; }
    return out;
  }

  async function apply(patch, files, say = () => {}) {
    const meta = readMeta(patch);
    say("checking your two ROMs");
    const { sms, supers } = await identify(files, meta);
    say("rebuilding the source from them");
    const source = buildSource(sms, supers, meta.streams);
    say("applying the patch");
    const out = bpsApply(patch, source);
    if ((await sha1Hex(out)) !== meta.target_sha1) throw new ApplierError("output SHA-1 does not match the patch's target");
    return { bytes: out, name: meta.target_name, sha1: meta.target_sha1 };
  }

  return { FORMAT, ApplierError, sha1Hex, crc32, lzDecompress, readMeta, bpsApply, identify, buildSource, apply };
})();
if (typeof module !== "undefined") module.exports = DonorApplier;
