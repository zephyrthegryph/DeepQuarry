import { expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import * as Juke from './juke/index.js';

// The `dir/**/*.ext` fast path must list what the glob library lists: nested files, no dot files or dot directories, sorted.
test('fast glob matches the library for dir/**/*.ext', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'jukeglob-'));
  const prev = process.cwd();
  try {
    for (const f of ['a/x.dm', 'a/b/y.dm', 'z.dm', 'a/.hidden.dm', '.dot/q.dm', 'a/n.txt']) {
      fs.mkdirSync(path.join(root, 'src', path.dirname(f)), { recursive: true });
      fs.writeFileSync(path.join(root, 'src', f), '');
    }
    process.chdir(root);
    const fast = Juke.glob('src/**/*.dm');
    const slow = Juke.glob('src/**/*.d[m]'); // a character class takes the library path
    expect(fast).toEqual(['src/a/b/y.dm', 'src/a/x.dm', 'src/z.dm']);
    expect(slow).toEqual(fast);
  } finally {
    process.chdir(prev);
    fs.rmSync(root, { recursive: true, force: true });
  }
});
