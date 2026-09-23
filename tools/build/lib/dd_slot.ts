/**
 * TypeScript-native port of the scratchpad `dd-slot.sh` protocol: a
 * machine-wide DreamDaemon concurrency limiter shared by every agent working
 * on this codebase (shell tooling wrapped in `dd-slot.sh`, and now the
 * sharded test runner below). It uses the SAME lock directories, so a
 * shard's DreamDaemon and any shell command someone else wrapped in
 * `dd-slot.sh` throttle against one shared budget instead of two separate
 * ones.
 *
 * Protocol (must stay in sync with the scratchpad's dd-slot.sh):
 * - `DQ_DD_SLOT_COUNT` (default 5) directory locks named `${base}${1..N}`.
 * - The last `DQ_DD_PRIORITY_RESERVED` (default 3) slots are reserved for
 *   callers that pass `priority: true` (DQ_DD_PRIORITY=1 for shell callers).
 * - `DQ_DD_SLOT_BASE` gives the lock directory prefix; with nothing set,
 *   dd-slot.sh falls back to a directory beside the checkout (not shared
 *   across worktrees) -- mirrored here for the same not-shared behavior.
 * - A slot directory holds a `pid` file; a stale lock (owner pid gone) is
 *   reclaimed.
 * - An exclusive bench lock directory (`DQ_BENCH_EXCLUSIVE_LOCK`) blocks all
 *   acquisition while held (see lib/bench.ts's acquireBenchExclusiveLock()),
 *   unless it's older than 20 minutes (stale).
 */

import fs from 'node:fs';
import path from 'node:path';

const SLOT_COUNT = Number(process.env.DQ_DD_SLOT_COUNT ?? 5);
const PRIORITY_RESERVED = Number(process.env.DQ_DD_PRIORITY_RESERVED ?? 3);
const EXCLUSIVE_MAX_AGE_SECONDS = 1200; // matches dd-slot.sh and lib/bench.ts's default
const POLL_INTERVAL_MS = 2000;

function defaultBaseParent(): string {
  if (process.env.DQ_BENCH_STORE) return path.dirname(process.env.DQ_BENCH_STORE);
  // Not shared across worktrees, same fallback dd-slot.sh uses.
  return path.resolve(__dirname, '..', '..', '..');
}

function slotBase(): string {
  return process.env.DQ_DD_SLOT_BASE ?? path.join(defaultBaseParent(), '.dq-dd-slot-');
}

function exclusiveLockPath(): string {
  return process.env.DQ_BENCH_EXCLUSIVE_LOCK ?? path.join(defaultBaseParent(), '.dq-bench-exclusive');
}

function isAlive(pid: number): boolean {
  if (!pid || Number.isNaN(pid)) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function exclusiveHeld(): boolean {
  const lock = exclusiveLockPath();
  if (!fs.existsSync(lock)) return false;
  try {
    const started = Number(fs.readFileSync(path.join(lock, 'started'), 'utf-8').trim());
    if (started && Date.now() / 1000 - started > EXCLUSIVE_MAX_AGE_SECONDS) {
      fs.rmSync(lock, { recursive: true, force: true });
      return false;
    }
  } catch {
    // No readable `started` marker: treat the lock as held rather than race it.
  }
  return true;
}

export type DdSlot = {
  /** 1-based slot index, matching the `${base}${index}` directory dd-slot.sh uses. */
  index: number;
  release: () => void;
};

/**
 * Blocks until one machine-wide DreamDaemon slot is held, then returns it.
 * Call `release()` once that slot's DreamDaemon has exited. `priority` mirrors
 * `DQ_DD_PRIORITY=1` for shell callers -- true reaches every slot, false only
 * the non-reserved ones.
 */
export async function acquireDdSlot(priority: boolean): Promise<DdSlot> {
  const base = slotBase();
  const top = priority ? SLOT_COUNT : Math.max(SLOT_COUNT - PRIORITY_RESERVED, 1);
  for (;;) {
    if (!exclusiveHeld()) {
      for (let i = 1; i <= top; i++) {
        const dir = `${base}${i}`;
        try {
          fs.mkdirSync(dir);
          fs.writeFileSync(path.join(dir, 'pid'), String(process.pid));
          let released = false;
          return {
            index: i,
            release: () => {
              if (released) return;
              released = true;
              try {
                fs.rmSync(dir, { recursive: true, force: true });
              } catch {
                // best-effort: a slower cleanup on Windows shouldn't fail the run
              }
            },
          };
        } catch (err: unknown) {
          const code = (err as NodeJS.ErrnoException)?.code;
          if (code !== 'EEXIST') throw err;
          try {
            const pid = Number(fs.readFileSync(path.join(dir, 'pid'), 'utf-8').trim());
            if (!isAlive(pid)) fs.rmSync(dir, { recursive: true, force: true });
          } catch {
            // Slot directory vanished mid-check, or its pid file is unreadable:
            // leave it for the next poll rather than risk deleting a live slot.
          }
        }
      }
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }
}
