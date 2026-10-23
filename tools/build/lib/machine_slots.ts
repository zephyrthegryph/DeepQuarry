/**
 * Machine-wide counting semaphores for the heavy steps every worktree runs (DM compiles, test worlds, cargo builds): the TypeScript side of tools/dq_machine_slots.sh. It uses the SAME directories and file formats, so a slot taken here
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
 * Counts (an env var overrides each; 0 turns that class off; DQ_SLOTS=0 turns all of it off): dm_compile DQ_SLOTS_DM_COMPILE=1,
 * test_world DQ_SLOTS_TEST_WORLD=2, cargo DQ_SLOTS_CARGO=1. dm_compile and cargo are never held while waiting for another class.
 */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export type SlotClass = 'dm_compile' | 'test_world' | 'cargo' | (string & {});

/**
 * Test worlds the machine hosts at once for a full-suite run (`dm-test` over a whole tier): four. One world is one DreamDaemon thread at about 1 core and
 * 3 GB private (data/bench/process-shard*.json of the run-5 profile: 2.9 GB private, 1.8 GB working set, 0.9 core), so four are 12 GB and 4 of 16
 * cores, which fits beside two dmbc daemons (8 GB each) with the 12 GB kept free on a 64 GB machine. Everyone else (focused runs, selections)
 * holds at most focusedTestWorlds(): the machine is also the user's desktop (2026-10-19). Same numbers as slots_default_test_world() in
 * dq_machine_slots.sh. DQ_SLOTS_TEST_WORLD=N sets one limit for every caller.
 */
export function defaultTestWorlds(_cpus: number = os.cpus().length): number {
  return 4;
}

/** Test worlds a caller that is not a full-suite run may hold at once (DQ_SLOTS_TEST_WORLD_FOCUSED, default 2). */
export function focusedTestWorlds(): number {
  const n = Number(process.env.DQ_SLOTS_TEST_WORLD_FOCUSED);
  return Number.isInteger(n) && n >= 1 ? n : 2;
}

/**
 * What a caller may hold of a class once its role is known (same rule as slots_role_cap() in dq_machine_slots.sh). Only test_world has roles, and only
 * while DQ_SLOTS_TEST_WORLD is unset (setting it is choosing one limit for all): a full-suite run (DQ_SLOTS_SUITE=1 or opts.suite) may hold every slot,
 * the merge reserve included; any other caller holds at most focusedTestWorlds().
 */
export function roleCap(cls: SlotClass, usable: number, max: number, suite: boolean): number {
  if (cls !== 'test_world' || (process.env.DQ_SLOTS_TEST_WORLD ?? '') !== '') return usable;
  return suite ? max : Math.min(usable, focusedTestWorlds());
}

function isSuite(opts?: { suite?: boolean }): boolean {
  return opts?.suite ?? process.env.DQ_SLOTS_SUITE === '1';
}

const DEFAULTS: Record<string, number> = { dm_compile: 1, test_world: defaultTestWorlds(), cargo: 1 };
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
  if (val === undefined || val === '') return DEFAULTS[cls] ?? 1;
  const n = Number(val);
  return Number.isInteger(n) && n >= 0 ? n : 1;
}

/**
 * Slots kept free for the merge worktree (same rule as slots_usable() in dq_machine_slots.sh): a caller with priority 1 may hold only
 * the first (capacity - reserve) slots. DQ_SLOTS_MERGE_RESERVE_<CLASS> or DQ_SLOTS_MERGE_RESERVE; default 1 for test_world with at
 * least 3 slots, else 0.
 */
export function usableSlots(cls: SlotClass, max: number, prio: number): number {
  if (prio === 0) return max;
  const raw = process.env[`DQ_SLOTS_MERGE_RESERVE_${cls.toUpperCase()}`] ?? process.env.DQ_SLOTS_MERGE_RESERVE;
  let reserve = raw !== undefined && raw !== '' ? Number(raw) : cls === 'test_world' && max >= 3 ? 1 : 0;
  if (!Number.isInteger(reserve) || reserve < 0) reserve = 0;
  return max - Math.min(reserve, max - 1);
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

/** Is this worktree a compiler or light lane slot (pool-c1/pool-c2, pool-light), or declared one with DQ_LANE_CLASS? (_slots_is_lane in dq_machine_slots.sh) */
function isLane(top: string, kind: 'compiler' | 'light'): boolean {
  if (process.env.DQ_LANE_CLASS === kind) return true;
  const base = norm(top).split('/').pop() ?? '';
  return kind === 'compiler' ? /^pool-c[0-9]/.test(base) : base === 'pool-light';
}

/** The merge worktree and a compiler lane go to the front of every queue (priority 0). */
function priorityOf(top: string): number {
  if (process.env.DQ_SLOT_PRIORITY !== undefined && process.env.DQ_SLOT_PRIORITY !== '') return Number(process.env.DQ_SLOT_PRIORITY);
  if (norm(top) === norm(process.env.DQ_MERGE_WT ?? 'E:/projects/dq-wt/merge-base')) return 0;
  return isLane(top, 'compiler') ? 0 : 1;
}

/** Slots beyond the cap a caller may hold: a compiler lane gets one extra cargo slot (_slots_extra). */
function extraSlots(cls: SlotClass, top: string): number {
  if (cls !== 'cargo' || !isLane(top, 'compiler')) return 0;
  const n = Number(process.env.DQ_SLOTS_COMPILER_EXTRA_CARGO ?? '1');
  return Number.isInteger(n) && n >= 0 ? n : 1;
}

/** A light lane never compiles DM or runs a test world (_slots_refuse_light). */
function refuseLight(cls: SlotClass, top: string): void {
  if ((cls === 'dm_compile' || cls === 'test_world') && isLane(top, 'light')) {
    throw new Error(`REFUSED: ${top} is a light lane: it never runs a DM compile or a test world (${cls}). Lease a general lane (tools/dq_lane_pool.sh lease <branch>) for work that needs the game build.`);
  }
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
    } else if (fs.existsSync(owner) && isDead(owner)) {
      // (the owner file can vanish between the two tests when its holder releases: that is not a dead holder, and removing the directory could take a slot another waiter just made)
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

/** A focused run (tools/dq_focused_test.sh) sets DQ_WORLD_REGISTRY: the first slot it holds starts the clock of its wall-clock cap
 * (time queued for a slot is not run time). tools/dq_run_guard.js reads the file's mtime. */
function markRunning(): void {
  const dir = process.env.DQ_WORLD_REGISTRY;
  if (!dir) return;
  try {
    const f = path.join(dir, '.running');
    if (!fs.existsSync(f)) { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(f, `${Math.floor(Date.now() / 1000)}\n`); }
  } catch { /* best effort */ }
}

const held = new Set<HeldSlot>();
let exitHooked = false;

/**
 * Waits for a slot of `cls`, prints who holds the slots while it waits, and returns the slot (call `release()` when the step is
 * done). Resolves to null at once when the class is switched off (capacity 0) or the slot directory cannot be created: a missing
 * limiter must not stop a build.
 */
export async function acquireSlot(cls: SlotClass, label: string, log: (m: string) => void = (m) => console.log(m)): Promise<HeldSlot | null> {
  return (await acquireSlotGroup(cls, 1, label, log))[0] ?? null;
}

/** A parent that took the slots for its worlds as a group sets DQ_SLOTS_PREHELD=<class,...>: those worlds do not queue again. */
function preheld(cls: SlotClass): boolean {
  return (process.env.DQ_SLOTS_PREHELD ?? '').split(',').includes(cls);
}

/** How many slots a group that wants `want` of `cls` gets: the wish, clamped to the class capacity (a group larger than the budget
 * could never be satisfied). 0 when the class is off or the slots are held by a parent. */
export function slotGroupSize(cls: SlotClass, want: number, opts?: { suite?: boolean }): number {
  const max = slotCapacity(cls);
  if (max <= 0 || preheld(cls)) return 0;
  return Math.min(want, roleCap(cls, usableSlots(cls, max, priorityOf(worktree())), max, isSuite(opts)));
}

/**
 * Waits until `want` slots of `cls` can be held together (clamped to the capacity) and returns them. One queue entry for the whole
 * group: the head of the queue takes slots as they free up and returns nothing until it has all of them, and only the head ever holds
 * a part, so two groups cannot each hold a part of the budget and wait on each other. Each slot is released on its own, so a sharded
 * run hands one back as its world finishes. Returns [] when the class is off.
 */
export async function acquireSlotGroup(cls: SlotClass, want: number, label: string, log: (m: string) => void = (m) => console.log(m), opts?: { suite?: boolean }): Promise<HeldSlot[]> {
  refuseLight(cls, worktree());
  const max = slotCapacity(cls);
  if (max <= 0 || preheld(cls)) return [];
  const prio = priorityOf(worktree());
  const usable = roleCap(cls, usableSlots(cls, max, prio), max, isSuite(opts)) + extraSlots(cls, worktree());
  want = Math.min(Math.max(want, 1), usable);
  const dir = path.join(slotsDir(), cls);
  try {
    fs.mkdirSync(path.join(dir, 'queue'), { recursive: true });
  } catch {
    log(`== machine slots: cannot create ${dir}; running without a ${cls} limit`);
    return [];
  }
  const top = worktree();
  const queued = Math.floor(Date.now() / 1000);
  const name = `${prio}-${String(queued).padStart(13, '0')}-${process.pid}`;
  const queueFile = path.join(dir, 'queue', name);
  const identity = `kind=node\npid=${process.pid}\nwinpid=${process.pid}\nworktree=${top}\nlabel=${label}\n`;
  fs.writeFileSync(queueFile, `${identity}queued=${queued}\n${want > 1 ? `group=${want}\n` : ''}`);
  let waited = 0;
  let last = 0;
  const taken: HeldSlot[] = [];
  for (;;) {
    reap(dir, log);
    let order: string[] = [];
    try {
      order = fs.readdirSync(path.join(dir, 'queue')).sort();
    } catch {
      // queue vanished: recreated below
    }
    // Small requests are not starved (dq_machine_slots.sh _slots_single_may_go): a single slot may pass groups still within their
    // patience; a group takes slots only when it can take them all at once, or, past its patience, whatever is free.
    const patience = Number(process.env.DQ_SLOTS_GROUP_PATIENCE_SEC ?? 120);
    const nowS = Math.floor(Date.now() / 1000);
    let mayGo = order[0] === name;
    if (!mayGo && want === 1) {
      mayGo = true;
      for (const q of order) {
        if (q === name) break;
        const f = readFields(path.join(dir, 'queue', q));
        if (!f.group || nowS - Number(f.queued || nowS) >= patience) {
          mayGo = false;
          break;
        }
      }
    }
    if (mayGo && want > 1 && taken.length === 0) {
      let free = 0;
      for (let i = 1; i <= usable; i++) if (!fs.existsSync(path.join(dir, `slot.${i}`))) free++;
      if (free < want) {
        if (waited >= patience && free >= 1) want = free;
        else mayGo = false;
      }
    }
    if (mayGo) {
      for (let i = 1; i <= usable && taken.length < want; i++) {
        const sd = path.join(dir, `slot.${i}`);
        try {
          fs.mkdirSync(sd);
        } catch {
          continue;
        }
        const owner = path.join(sd, 'owner');
        const started = Math.floor(Date.now() / 1000);
        fs.writeFileSync(owner, `${identity}started=${started}\npriority=${prio}\n`);
        markRunning();
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
        taken.push(slot);
      }
      if (taken.length >= want) {
        fs.rmSync(queueFile, { force: true });
        const which = taken.map((t) => t.index).join(',');
        log(waited > 0 ? `== machine slots: ${cls} slot ${which} of ${max} after ${waited}s in the queue` : `== machine slots: ${cls} slot ${which} of ${max}`);
        return taken;
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
      log(`== machine slots: ${cls}: waiting ${waited}s${want > 1 ? ` for a group of ${want}, holding ${taken.length}` : ''}, place ${pos} of ${total} in the queue (at most ${max} at once on this machine; the merge worktree goes first). Held by:${who(dir, max)}`);
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
export function slotsStatus(classes: string[] = ['dm_compile', 'test_world', 'cargo']): string {
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
