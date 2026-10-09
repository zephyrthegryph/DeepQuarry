/**
 * Machine-wide counting semaphores for the heavy steps every worktree runs (DM compiles, test worlds, cargo builds, look-state
 * pins): the TypeScript side of tools/dq_machine_slots.sh. It uses the SAME directories and file formats, so a slot taken here
 * and a slot taken by a shell command throttle against one budget. Keep the two in sync; machine_slots.test.ts runs both.
 *
 * Layout under `DQ_SLOTS_DIR` (default E:/dq-cache/slots, else ~/.cache/dq/slots), one directory per class:
 * - `slot.N/owner`: a held slot (an atomic mkdir). key=value lines: kind, pid, winpid, worktree, label, started, priority. The
 *   file's mtime is the holder's heartbeat, touched every 15 s while it holds the slot.
 * - `queue/P-T-PID`: a waiter. P is 0 for the merge worktree (DQ_MERGE_WT) and 1 for everyone else, T the arrival time (13
 *   digits), so the merge worktree jumps the queue and the rest go in arrival order. A waiter takes a slot only when first.
 * - `events.tsv`: one line per release: time, class, slot, worktree, label, waited seconds, held seconds.
 * A holder or waiter is dead when its pid is gone or its heartbeat is older than DQ_SLOTS_STALE_SEC (default 600). A dead slot is
 * removed by the next waiter, so a crashed run never blocks the queue.
 *
 * Counts (an env var overrides each; 0 turns that class off; DQ_SLOTS=0 turns all of it off): dm_compile DQ_SLOTS_DM_COMPILE=2,
 * test_world DQ_SLOTS_TEST_WORLD=3, cargo DQ_SLOTS_CARGO=1, look_state_pin DQ_SLOTS_LOOK_STATE_PIN=2 (DQ_LOOK_PIN_SLOTS is the old
 * name). Lock order when a run needs several: look_state_pin, then test_world; dm_compile and cargo are never held while waiting
 * for another class.
 */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export type SlotClass = 'dm_compile' | 'test_world' | 'cargo' | 'look_state_pin' | (string & {});

const DEFAULTS: Record<string, number> = { dm_compile: 2, test_world: 3, cargo: 1, look_state_pin: 2 };
const HEARTBEAT_MS = Number(process.env.DQ_SLOTS_HEARTBEAT_SEC ?? 15) * 1000;
const POLL_MS = Number(process.env.DQ_SLOTS_POLL_SEC ?? 3) * 1000;

export function slotsDir(): string {
  if (process.env.DQ_SLOTS_DIR) return process.env.DQ_SLOTS_DIR;
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/slots';
  return path.join(os.homedir(), '.cache', 'dq', 'slots');
}

/** How many of a class may run at once on this machine; 0 = no limit. */
export function slotCapacity(cls: SlotClass): number {
  if (process.env.DQ_SLOTS === '0') return 0;
  let val = process.env[`DQ_SLOTS_${cls.toUpperCase()}`];
  if (val === undefined && cls === 'look_state_pin') val = process.env.DQ_LOOK_PIN_SLOTS;
  if (val === undefined || val === '') return DEFAULTS[cls] ?? 1;
  const n = Number(val);
  return Number.isInteger(n) && n >= 0 ? n : 1;
}

const norm = (p: string): string =>
  p
    .toLowerCase()
    .replace(/\\/g, '/')
    .replace(/^\/([a-z])\//, '$1:/')
    .replace(/\/+$/, '');

function worktree(): string {
  return process.env.DQ_SLOT_WORKTREE ?? process.env.DQ_BUILD_ROOT ?? process.cwd();
}

function priorityOf(top: string): number {
  if (process.env.DQ_SLOT_PRIORITY !== undefined && process.env.DQ_SLOT_PRIORITY !== '') return Number(process.env.DQ_SLOT_PRIORITY);
  return norm(top) === norm(process.env.DQ_MERGE_WT ?? 'E:/projects/dq-wt/merge-base') ? 0 : 1;
}

function readFields(file: string): Record<string, string> {
  const out: Record<string, string> = {};
  try {
    for (const line of fs.readFileSync(file, 'utf-8').split(/\r?\n/)) {
      const i = line.indexOf('=');
      if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
    }
  } catch {
    // gone or unreadable: no fields
  }
  return out;
}

function mtimeSec(file: string): number {
  try {
    return Math.floor(fs.statSync(file).mtimeMs / 1000);
  } catch {
    return 0;
  }
}

function pidAlive(pid: number): boolean {
  if (!pid || Number.isNaN(pid)) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: unknown) {
    // EPERM: it exists, we may not signal it.
    return (err as NodeJS.ErrnoException)?.code === 'EPERM';
  }
}

/** Is the process that wrote this owner or queue file gone, or its heartbeat stale? */
function isDead(file: string): boolean {
  if (!fs.existsSync(file)) return true;
  const f = readFields(file);
  const stale = Number(process.env.DQ_SLOTS_STALE_SEC ?? 600);
  if (Date.now() / 1000 - mtimeSec(file) > stale) return true;
  // A bash holder's own pid is an MSYS pid; its winpid is the Windows one this process can signal. A node holder has both equal.
  const pid = Number(f.kind === 'bash' && process.platform === 'win32' ? f.winpid : (f.winpid || f.pid));
  if (!pid) return false;
  return !pidAlive(pid);
}

function reap(dir: string, log?: (m: string) => void): void {
  let queue: string[] = [];
  try {
    queue = fs.readdirSync(path.join(dir, 'queue'));
  } catch {
    // no queue yet
  }
  for (const q of queue) {
    const f = path.join(dir, 'queue', q);
    if (isDead(f)) fs.rmSync(f, { force: true });
  }
  let slots: string[] = [];
  try {
    slots = fs.readdirSync(dir).filter((n) => n.startsWith('slot.'));
  } catch {
    return;
  }
  for (const s of slots) {
    const sd = path.join(dir, s);
    const owner = path.join(sd, 'owner');
    if (!fs.existsSync(owner)) {
      // mkdir done, owner not written yet: a young directory is its taker's; an old one is dead.
      let age = 0;
      try {
        age = Date.now() - fs.statSync(sd).mtimeMs;
      } catch {
        continue;
      }
      if (age > 2000) fs.rmSync(sd, { recursive: true, force: true });
    } else if (isDead(owner)) {
      const f = readFields(owner);
      log?.(`== machine slots: reclaiming a dead slot (${sd}: ${f.worktree} pid ${f.pid} ${f.label})`);
      fs.rmSync(sd, { recursive: true, force: true });
    }
  }
}

function who(dir: string, max: number): string {
  let out = '';
  const now = Math.floor(Date.now() / 1000);
  for (let i = 1; i <= max; i++) {
    const f = readFields(path.join(dir, `slot.${i}`, 'owner'));
    if (f.pid) out += ` [slot.${i}: ${f.worktree} '${f.label}' pid ${f.pid}, held ${now - Number(f.started || now)}s]`;
  }
  return out || ' nobody';
}

export type HeldSlot = {
  cls: string;
  index: number;
  /** Seconds spent in the queue. */
  waited: number;
  release: () => void;
};

const held = new Set<HeldSlot>();
let exitHooked = false;

/**
 * Waits for a slot of `cls`, prints who holds the slots while it waits, and returns the slot (call `release()` when the step is
 * done). Resolves to null at once when the class is switched off (capacity 0) or the slot directory cannot be created: a missing
 * limiter must not stop a build.
 */
export async function acquireSlot(cls: SlotClass, label: string, log: (m: string) => void = (m) => console.log(m)): Promise<HeldSlot | null> {
  const max = slotCapacity(cls);
  if (max <= 0) return null;
  const dir = path.join(slotsDir(), cls);
  try {
    fs.mkdirSync(path.join(dir, 'queue'), { recursive: true });
  } catch {
    log(`== machine slots: cannot create ${dir}; running without a ${cls} limit`);
    return null;
  }
  const top = worktree();
  const prio = priorityOf(top);
  const queued = Math.floor(Date.now() / 1000);
  const name = `${prio}-${String(queued).padStart(13, '0')}-${process.pid}`;
  const queueFile = path.join(dir, 'queue', name);
  const identity = `kind=node\npid=${process.pid}\nwinpid=${process.pid}\nworktree=${top}\nlabel=${label}\n`;
  fs.writeFileSync(queueFile, `${identity}queued=${queued}\n`);
  let waited = 0;
  let last = 0;
  for (;;) {
    reap(dir, log);
    let first = '';
    try {
      first = fs.readdirSync(path.join(dir, 'queue')).sort()[0] ?? '';
    } catch {
      // queue vanished: recreated below
    }
    if (first === name) {
      for (let i = 1; i <= max; i++) {
        const sd = path.join(dir, `slot.${i}`);
        try {
          fs.mkdirSync(sd);
        } catch {
          continue;
        }
        const owner = path.join(sd, 'owner');
        const started = Math.floor(Date.now() / 1000);
        fs.writeFileSync(owner, `${identity}started=${started}\npriority=${prio}\n`);
        fs.rmSync(queueFile, { force: true });
        const beat = setInterval(() => {
          try {
            const now = new Date();
            fs.utimesSync(owner, now, now);
          } catch {
            clearInterval(beat);
          }
        }, HEARTBEAT_MS);
        beat.unref();
        let released = false;
        const slot: HeldSlot = {
          cls,
          index: i,
          waited,
          release: () => {
            if (released) return;
            released = true;
            clearInterval(beat);
            held.delete(slot);
            const now = Math.floor(Date.now() / 1000);
            try {
              fs.appendFileSync(path.join(slotsDir(), 'events.tsv'), `${now}\t${cls}\t${i}\t${top}\t${label}\t${started - queued}\t${now - started}\n`);
            } catch {
              // the log is best-effort
            }
            fs.rmSync(sd, { recursive: true, force: true });
          },
        };
        held.add(slot);
        if (!exitHooked) {
          exitHooked = true;
          process.on('exit', () => {
            for (const s of [...held]) s.release();
          });
        }
        log(waited > 0 ? `== machine slots: ${cls} slot ${i} of ${max} after ${waited}s in the queue` : `== machine slots: ${cls} slot ${i} of ${max}`);
        return slot;
      }
    }
    if (waited === 0 || waited - last >= 30) {
      last = waited;
      let pos = '?';
      let total = 0;
      try {
        const names = fs.readdirSync(path.join(dir, 'queue')).sort();
        total = names.length;
        pos = String(names.indexOf(name) + 1);
      } catch {
        // gone
      }
      log(`== machine slots: ${cls}: waiting ${waited}s, place ${pos} of ${total} in the queue (at most ${max} at once on this machine; the merge worktree goes first). Held by:${who(dir, max)}`);
    }
    try {
      const now = new Date();
      fs.utimesSync(queueFile, now, now);
    } catch {
      fs.mkdirSync(path.join(dir, 'queue'), { recursive: true });
      fs.writeFileSync(queueFile, `${identity}queued=${queued}\n`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    waited += Math.round(POLL_MS / 1000);
  }
}

/** Runs `fn` while holding a slot of `cls`. */
export async function withSlot<T>(cls: SlotClass, label: string, fn: () => Promise<T>, log?: (m: string) => void): Promise<T> {
  const slot = await acquireSlot(cls, label, log);
  try {
    return await fn();
  } finally {
    slot?.release();
  }
}

/** For the tests and `bun tools/build/lib/machine_slots.ts`: the same table `dq_machine_slots.sh status` prints. */
export function slotsStatus(classes: string[] = ['dm_compile', 'test_world', 'cargo', 'look_state_pin']): string {
  const now = Math.floor(Date.now() / 1000);
  const lines: string[] = [];
  for (const cls of classes) {
    const max = slotCapacity(cls);
    lines.push(`${cls}: at most ${max} at once${max === 0 ? ' (limit off)' : ''}`);
    const dir = path.join(slotsDir(), cls);
    for (let i = 1; i <= Math.max(max, 1); i++) {
      const f = readFields(path.join(dir, `slot.${i}`, 'owner'));
      if (f.pid) lines.push(`  slot.${i}: ${f.worktree} '${f.label}' pid ${f.pid}, held ${now - Number(f.started || now)}s`);
    }
    try {
      for (const q of fs.readdirSync(path.join(dir, 'queue')).sort()) {
        const f = readFields(path.join(dir, 'queue', q));
        lines.push(`  waiting ${q}: ${f.worktree} '${f.label}' pid ${f.pid}`);
      }
    } catch {
      // no queue
    }
  }
  return lines.join('\n');
}

/** `git rev-parse --show-toplevel` of a directory, for callers that do not run under build.sh (DQ_BUILD_ROOT). */
export function toplevelOf(cwd: string): string {
  const r = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf-8' });
  return r.status === 0 ? r.stdout.trim() : cwd;
}
