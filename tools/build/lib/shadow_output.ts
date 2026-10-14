/** Stable copied bytes only; this cannot authenticate the producing invocation. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
const MAX_FILE_BYTES = 2 * 1024 * 1024 * 1024;
function digest(file: string): { sha256: string; bytes: number } {
  const fd = fs.openSync(file, 'r');
  try {
    const initial = fs.fstatSync(fd);
    if (!initial.isFile() || initial.size > MAX_FILE_BYTES) throw new Error('Shadow output exceeds regular-file capture bound (2GiB).');
    const hash = createHash('sha256');
    const buffer = Buffer.allocUnsafe(64 * 1024);
    let bytes = 0;
    for (;;) {
      const length = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (!length) break;
      bytes += length;
      if (bytes > MAX_FILE_BYTES) throw new Error('Shadow output grew beyond capture bound.');
      hash.update(buffer.subarray(0, length));
    }
    const final = fs.fstatSync(fd);
    if (bytes !== initial.size || final.size !== initial.size || final.mtimeMs !== initial.mtimeMs || final.ctimeMs !== initial.ctimeMs) throw new Error('Shadow output changed while hashing.');
    return { sha256: hash.digest('hex'), bytes };
  } finally { fs.closeSync(fd); }
}
export function captureShadowOutputPair(project: string, directory: string, afterCopy?: () => void) {
  const sources = [project.replace(/\.dme$/i, '.dmb'), project.replace(/\.dme$/i, '.rsc')];
  const copies = [path.join(directory, 'byond-captured.dmb'), path.join(directory, 'byond-captured.rsc')];
  const before = sources.map(digest);
  const created: string[] = [];
  try {
    for (let i = 0; i < sources.length; i++) {
      fs.copyFileSync(sources[i], copies[i], fs.constants.COPYFILE_EXCL);
      created.push(copies[i]);
    }
    afterCopy?.();
    const captured = copies.map(digest);
    const after = sources.map(digest);
    for (let i = 0; i < sources.length; i++) {
      if (before[i].sha256 !== captured[i].sha256 || before[i].sha256 !== after[i].sha256 || before[i].bytes !== captured[i].bytes || before[i].bytes !== after[i].bytes) throw new Error('Shadow output pair changed during capture.');
    }
    // Read-only owned copies prevent ordinary later writes; no generation claim.
    for (const copy of copies) fs.chmodSync(copy, 0o444);
    return { dmb: copies[0], rsc: copies[1], proof: {
      schema: 'stable-shadow-output-pair-v1', stable_output_pair: true,
      invocation_generation_complete: false, file_byte_limit: MAX_FILE_BYTES,
      dmb: captured[0], rsc: captured[1],
    } };
  } catch (error) {
    for (const file of created) { try { fs.chmodSync(file, 0o666); fs.unlinkSync(file); } catch {} }
    throw error;
  }
}
