// Per-process copies of the compiled world (`<base>.runN.p<pid>.dmb|rsc|dyn.rsc`) that runIsolatedTestWorld() launches DreamDaemon from.
//
// Why the copy is named for the process too: run-slot names (`run2`) are reused. When a world ended, the cleanup retried removing its copy for
// 5 s and then left it behind ("it will be replaced on the next run") if something still held it (the daemon closing its handles, a scanner).
// The next occupant of the slot then copied onto that name and failed with `EBUSY: copyfile 'deepquarry.test.dmb' -> 'deepquarry.test.run2.dmb'`.
// A name no earlier run used cannot be held by an earlier run, so the copy cannot collide; leftovers of dead processes are pruned, and one that
// is still locked is reported with its error code (no blind retry of the copy).
import fs from 'node:fs';
import path from 'node:path';

export function runCopyBase(base: string, tag: string, pid: number): string {
  return `${base}.${tag}.p${pid}`;
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Removes the run copies of `base` whose process is gone. Returns the names removed; `warn` receives each one that could not be. */
export function pruneStaleRunCopies(base: string, alive: (pid: number) => boolean, warn: (message: string) => void): string[] {
  const dir = path.dirname(base);
  const stem = path.basename(base);
  let names: string[] = [];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return [];
  }
  const re = new RegExp(`^${escapeRegExp(stem)}\\.run\\d+\\.p(\\d+)\\.(?:dmb|rsc|dyn\\.rsc)$`);
  const removed: string[] = [];
  for (const name of names) {
    const m = re.exec(name);
    if (!m || alive(Number(m[1]))) continue;
    try {
      fs.rmSync(path.join(dir, name), { force: true });
      removed.push(name);
    } catch (e) {
      warn(`Stale world copy ${name} (process ${m[1]} is gone) is still locked: ${(e as NodeJS.ErrnoException).code ?? e}`);
    }
  }
  return removed;
}
