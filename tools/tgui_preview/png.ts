/**
 * Minimal PNG decode/encode and DMI frame cropping for the render preview (no dependencies: node:zlib only).
 * Decodes non-interlaced PNGs of any colour type at bit depth 1-8 (what BYOND and Chrome write) to RGBA8.
 */
import { deflateSync, inflateSync } from 'node:zlib';

export type Image = {
  width: number;
  height: number;
  data: Uint8Array;
  text: Record<string, string>;
};

const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export function decodePng(buf: Uint8Array): Image {
  const b = Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength);
  if (!b.subarray(0, 8).equals(SIG)) throw new Error('not a PNG');
  let pos = 8;
  let width = 0,
    height = 0,
    depth = 8,
    ctype = 6,
    interlace = 0;
  let palette: Buffer | null = null;
  let trns: Buffer | null = null;
  const idat: Buffer[] = [];
  const text: Record<string, string> = {};
  while (pos < b.length) {
    const len = b.readUInt32BE(pos);
    const type = b.toString('latin1', pos + 4, pos + 8);
    const body = b.subarray(pos + 8, pos + 8 + len);
    pos += 12 + len;
    if (type === 'IHDR') {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      depth = body[8];
      ctype = body[9];
      interlace = body[12];
    } else if (type === 'PLTE') palette = body;
    else if (type === 'tRNS') trns = body;
    else if (type === 'IDAT') idat.push(body);
    else if (type === 'zTXt' || type === 'tEXt') {
      const nul = body.indexOf(0);
      const key = body.toString('latin1', 0, nul);
      text[key] =
        type === 'tEXt'
          ? body.toString('latin1', nul + 1)
          : inflateSync(body.subarray(nul + 2)).toString('utf8');
    } else if (type === 'IEND') break;
  }
  if (interlace) throw new Error('interlaced PNG');
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ctype as 0 | 2 | 3 | 4 | 6];
  const raw = inflateSync(Buffer.concat(idat));
  const bpp = Math.max(1, (channels * depth) >> 3);
  const stride = (width * channels * depth + 7) >> 3;
  const lines = new Uint8Array(stride * height);
  let prev = new Uint8Array(stride);
  for (let y = 0, r = 0; y < height; y++) {
    const filter = raw[r++];
    const line = lines.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? line[x - bpp] : 0;
      const up = prev[x];
      const c = x >= bpp ? prev[x - bpp] : 0;
      let v = raw[r++];
      if (filter === 1) v += a;
      else if (filter === 2) v += up;
      else if (filter === 3) v += (a + up) >> 1;
      else if (filter === 4) {
        const p = a + up - c,
          pa = Math.abs(p - a),
          pb = Math.abs(p - up),
          pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c;
      }
      line[x] = v & 255;
    }
    prev = line;
  }
  const out = new Uint8Array(width * height * 4);
  const sample = (line: Uint8Array, i: number) => {
    if (depth === 8) return line[i];
    const bit = i * depth;
    return (line[bit >> 3] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
  };
  const scale = depth === 8 ? 1 : 255 / ((1 << depth) - 1);
  for (let y = 0; y < height; y++) {
    const line = lines.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      if (ctype === 3) {
        const i = sample(line, x);
        out[o] = palette![i * 3];
        out[o + 1] = palette![i * 3 + 1];
        out[o + 2] = palette![i * 3 + 2];
        out[o + 3] = trns && i < trns.length ? trns[i] : 255;
      } else if (ctype === 0 || ctype === 4) {
        const g = ctype === 0 ? sample(line, x) * scale : line[x * 2];
        out[o] = out[o + 1] = out[o + 2] = g;
        out[o + 3] = ctype === 4 ? line[x * 2 + 1] : 255;
      } else {
        for (let k = 0; k < channels; k++) out[o + k] = line[x * channels + k];
        if (channels === 3) out[o + 3] = 255;
      }
    }
  }
  return { width, height, data: out, text };
}

const CRC = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function chunk(type: string, body: Buffer): Buffer {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(body.length, 0);
  head.write(type, 4, 'latin1');
  let c = -1;
  for (const byte of Buffer.concat([head.subarray(4), body]))
    c = CRC[(c ^ byte) & 255] ^ (c >>> 8);
  const crc = Buffer.alloc(4);
  crc.writeInt32BE(~c, 0);
  return Buffer.concat([head, body, crc]);
}

export function encodePng(
  width: number,
  height: number,
  rgba: Uint8Array,
): Buffer {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * width * 4, width * 4).copy(
      raw,
      y * (width * 4 + 1) + 1,
    );
  }
  return Buffer.concat([
    SIG,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

type DmiState = { name: string; dirs: number; frames: number; offset: number };
export type Dmi = {
  image: Image;
  width: number;
  height: number;
  states: DmiState[];
};

/** Parses a .dmi: the PNG plus its "Description" metadata (the state list in sheet order). */
export function parseDmi(buf: Uint8Array): Dmi {
  const image = decodePng(buf);
  const desc = image.text.Description ?? '';
  let width = 32,
    height = 32;
  const states: DmiState[] = [];
  let offset = 0;
  let cur: DmiState | null = null;
  for (const raw of desc.split('\n')) {
    const m = raw.trim().match(/^(\w+)\s*=\s*(.*)$/);
    if (!m) continue;
    const [, key, value] = m;
    if (key === 'width' && !cur) width = Number(value);
    else if (key === 'height' && !cur) height = Number(value);
    else if (key === 'state') {
      if (cur) offset += cur.dirs * cur.frames;
      cur = { name: JSON.parse(value), dirs: 1, frames: 1, offset };
      states.push(cur);
    } else if (cur && key === 'dirs') cur.dirs = Number(value);
    else if (cur && key === 'frames') cur.frames = Number(value);
  }
  return { image, width, height, states };
}

const DIR_ORDER = [2, 1, 4, 8, 6, 10, 5, 9]; // S N E W SE SW NE NW

/** One frame of one state as a PNG, or null when the state is not in the file (the first state stands in for ''). */
export function dmiFrame(
  dmi: Dmi,
  state: string,
  dir = 2,
  frame = 1,
): Buffer | null {
  const s =
    dmi.states.find((x) => x.name === state) ??
    (state === '' ? dmi.states[0] : undefined);
  if (!s) return null;
  const d = Math.max(0, DIR_ORDER.indexOf(dir));
  const index =
    s.offset +
    (Math.min(Math.max(frame, 1), s.frames) - 1) * s.dirs +
    (d < s.dirs ? d : 0);
  const cols = Math.max(1, Math.floor(dmi.image.width / dmi.width));
  const x0 = (index % cols) * dmi.width;
  const y0 = Math.floor(index / cols) * dmi.height;
  const out = new Uint8Array(dmi.width * dmi.height * 4);
  for (let y = 0; y < dmi.height; y++) {
    const from = ((y0 + y) * dmi.image.width + x0) * 4;
    out.set(
      dmi.image.data.subarray(from, from + dmi.width * 4),
      y * dmi.width * 4,
    );
  }
  return encodePng(dmi.width, dmi.height, out);
}

/** Fraction of pixels whose channels differ by more than `tolerance` (0-255); sizes that differ count as 1. */
export function diffRatio(
  a: Image,
  b: Image,
  tolerance = 16,
  ignore?: Image,
): number {
  if (a.width !== b.width || a.height !== b.height) return 1;
  const masked =
    ignore && ignore.width === a.width && ignore.height === a.height
      ? ignore
      : undefined;
  let bad = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    // `ignore` is a second frame of b: a pixel that moved between b's own frames is animation, not a change.
    if (
      masked &&
      (Math.abs(masked.data[i] - b.data[i]) > tolerance ||
        Math.abs(masked.data[i + 1] - b.data[i + 1]) > tolerance ||
        Math.abs(masked.data[i + 2] - b.data[i + 2]) > tolerance)
    )
      continue;
    if (
      Math.abs(a.data[i] - b.data[i]) > tolerance ||
      Math.abs(a.data[i + 1] - b.data[i + 1]) > tolerance ||
      Math.abs(a.data[i + 2] - b.data[i + 2]) > tolerance
    )
      bad++;
  }
  return bad / (a.width * a.height);
}

/** Share of the image covered by its single most common colour: near 1 is a blank render. */
export function dominantShare(img: Image): number {
  const counts = new Map<number, number>();
  let best = 0;
  for (let i = 0; i < img.data.length; i += 16) {
    const k = (img.data[i] << 16) | (img.data[i + 1] << 8) | img.data[i + 2];
    const n = (counts.get(k) ?? 0) + 1;
    counts.set(k, n);
    if (n > best) best = n;
  }
  return best / (img.data.length / 16);
}
