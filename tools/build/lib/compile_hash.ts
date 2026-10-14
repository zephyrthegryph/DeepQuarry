/**
 * Compile-input hash for the derived test/bench builds (compileDerived in
 * build.ts). The key covers every input DreamMaker reads:
 *  - the derived .dme text, the defines and the compiler version,
 *  - the content of every .dm the .dme includes (transitively),
 *  - the content of every other included file (the .dmf skin),
 *  - every resource file under the .dme's FILE_DIR trees (icons/gen, sound,
 *    maps, ...), keyed by relative path + size + mtime. Stat-only keeps a
 *    warm-tree check cheap; any edit changes the mtime.
 * Paths are relative to the current working directory (the repo root).
 */
import { createHash } from 'node:crypto';
import fs from 'node:fs';

const normalize = (baseDir: string, raw: string): string => {
  const combined = baseDir === '.' ? raw : `${baseDir}/${raw}`;
  const out: string[] = [];
  for (const seg of combined.replace(/\\/g, '/').split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') {
      out.pop();
      continue;
    }
    out.push(seg);
  }
  return out.join('/');
};

const dirOf = (file: string): string => {
  const i = file.lastIndexOf('/');
  return i === -1 ? '.' : file.slice(0, i);
};

/** Every file the .dme #includes: `dm` are code files (walked transitively), `other` are e.g. the .dmf skin. */
export function resolveDmeIncludes(dmeText: string): { dm: string[]; other: string[] } {
  const ACTIVE_INCLUDE = /^[ \t]*#include\s+"([^"]+)"/gm;
  const dm = new Set<string>();
  const other = new Set<string>();
  const queue: string[] = [];
  const seed = (content: string, baseDir: string) => {
    for (const m of content.matchAll(ACTIVE_INCLUDE)) {
      const file = normalize(baseDir, m[1]);
      if (file.endsWith('.dm') || file.endsWith('.dme')) queue.push(file);
      else other.add(file);
    }
  };
  seed(dmeText, '.');
  while (queue.length > 0) {
    const file = queue.pop() as string;
    if (dm.has(file)) continue;
    dm.add(file);
    if (!fs.existsSync(file)) continue; // missing include: DreamMaker will report it
    seed(fs.readFileSync(file, 'utf-8'), dirOf(file));
  }
  return { dm: [...dm].sort(), other: [...other].sort() };
}

/** The FILE_DIR resource roots the .dme declares (active lines only), nested roots collapsed. */
export function fileDirRoots(dmeText: string): string[] {
  const roots = new Set<string>();
  for (const m of dmeText.matchAll(/^[ \t]*#define\s+FILE_DIR\s+(\S+)/gm)) {
    roots.add(normalize('.', m[1]));
  }
  const sorted = [...roots].sort();
  return sorted.filter((r) => !sorted.some((o) => o !== r && r.startsWith(`${o}/`)));
}

/** Sorted "path|size|mtimeMs" lines for every file under the FILE_DIR roots. */
export function resourceStamps(roots: string[]): string[] {
  const lines: string[] = [];
  const walk = (dir: string) => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = `${dir}/${e.name}`;
      if (e.isDirectory()) {
        walk(p);
      } else {
        try {
          const st = fs.statSync(p);
          lines.push(`${p}|${st.size}|${Math.floor(st.mtimeMs)}`);
        } catch {
          lines.push(`${p}|unreadable`);
        }
      }
    }
  };
  for (const r of roots) walk(r);
  return lines.sort();
}

export function computeCompileHash(dmeText: string, defines: string[], dmVersion: string | null): string {
  const hash = createHash('sha256');
  hash.update(dmeText);
  const { dm, other } = resolveDmeIncludes(dmeText);
  for (const file of [...dm, ...other]) {
    hash.update(file);
    try {
      hash.update(fs.readFileSync(file));
    } catch {
      hash.update('<unreadable>');
    }
  }
  hash.update('\0resources\0');
  hash.update(resourceStamps(fileDirRoots(dmeText)).join('\n'));
  hash.update(JSON.stringify([...defines].sort()));
  hash.update(dmVersion ?? '');
  return hash.digest('hex');
}

if (import.meta.main) {
  // CLI: `bun compile_hash.ts <dme> [define...]` prints the hash (used by tools/ci/test_compile_cache.sh).
  const [dme, ...defines] = process.argv.slice(2);
  console.log(computeCompileHash(fs.readFileSync(dme, 'utf-8'), defines, null));
}
