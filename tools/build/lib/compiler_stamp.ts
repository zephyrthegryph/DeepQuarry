/**
 * Which compiler produced the conventional `<project>.dmb/.rsc` pair in the tree.
 *
 * Juke decides that the DM target is up to date from output mtimes alone, and a native build publishes the same file
 * names DreamMaker does, so a plain `build.sh dm` after `DQ_COMPILER=native build.sh dm` used to treat the native pair
 * as its own. Every compile records the backend that wrote the pair in `<project>.dmb.compiler`; the byond target
 * only counts the pair as up to date when that record names byond.
 */
import fs from 'node:fs';

export type StampedBackend = 'byond' | 'native';

export function compilerStampPath(dmbFile: string): string {
  return `${dmbFile}.compiler`;
}

/** Records the backend that produced `dmbFile`; a failed write only costs a later rebuild, so it never throws. */
export function writeCompilerStamp(dmbFile: string, backend: StampedBackend): void {
  try {
    fs.writeFileSync(compilerStampPath(dmbFile), `${backend}\n`);
  } catch {
    // best-effort: a missing stamp makes the byond target rebuild
  }
}

/** The recorded backend, or null when there is no readable stamp. */
export function readCompilerStamp(dmbFile: string): StampedBackend | null {
  try {
    const text = fs.readFileSync(compilerStampPath(dmbFile), 'utf-8').trim();
    return text === 'byond' || text === 'native' ? text : null;
  } catch {
    return null;
  }
}

/** True only when the pair on disk is recorded as DreamMaker output. An unstamped pair is not trusted. */
export function pairIsByondOutput(dmbFile: string): boolean {
  return readCompilerStamp(dmbFile) === 'byond';
}

/** The stamp is removed with the pair it describes (clean targets, failed compiles). */
export function removeCompilerStamp(dmbFile: string): void {
  fs.rmSync(compilerStampPath(dmbFile), { force: true });
}
