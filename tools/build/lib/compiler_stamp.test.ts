import { expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pairIsByondOutput, readCompilerStamp, removeCompilerStamp, writeCompilerStamp } from './compiler_stamp';

test('a pair is DreamMaker output only when the stamp says byond', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'compiler-stamp-'));
  try {
    const dmb = path.join(dir, 'world.dmb');
    expect(readCompilerStamp(dmb)).toBeNull();
    expect(pairIsByondOutput(dmb)).toBe(false); // unstamped: not trusted
    writeCompilerStamp(dmb, 'native');
    expect(readCompilerStamp(dmb)).toBe('native');
    expect(pairIsByondOutput(dmb)).toBe(false); // native pair must not satisfy a byond build
    writeCompilerStamp(dmb, 'byond');
    expect(pairIsByondOutput(dmb)).toBe(true);
    removeCompilerStamp(dmb);
    expect(readCompilerStamp(dmb)).toBeNull();
    fs.writeFileSync(`${dmb}.compiler`, 'garbage');
    expect(readCompilerStamp(dmb)).toBeNull();
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
