// Tests for the machine-wide slots (lib/machine_slots.ts and tools/dq_machine_slots.sh share one on-disk protocol).
// Run with `bun test tools/build/lib/machine_slots.test.ts`.
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { acquireSlot, slotCapacity, slotsDir, slotsStatus } from './machine_slots';

const ENV_KEYS = ['DQ_SLOTS_DIR', 'DQ_SLOTS', 'DQ_SLOTS_CARGO', 'DQ_SLOTS_DM_COMPILE', 'DQ_SLOTS_TEST_WORLD', 'DQ_SLOTS_LOOK_STATE_PIN', 'DQ_LOOK_PIN_SLOTS', 'DQ_SLOT_PRIORITY', 'DQ_SLOT_WORKTREE', 'DQ_SLOTS_POLL_SEC', 'DQ_MERGE_WT'] as const;
const saved: Record<string, string | undefined> = {};
for (const k of ENV_KEYS) saved[k] = process.env[k];
let tmp = '';
const quiet = () => {};

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dq-slots-'));
  process.env.DQ_SLOTS_DIR = tmp;
  process.env.DQ_SLOTS_POLL_SEC = '1';
  process.env.DQ_SLOT_WORKTREE = '/x/test';
  delete process.env.DQ_SLOT_PRIORITY;
  delete process.env.DQ_SLOTS;
});

afterEach(() => {
  for (const k of ENV_KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe('capacity', () => {
  test('defaults and the environment', () => {
    for (const k of ENV_KEYS) if (k.startsWith('DQ_SLOTS_') && k !== 'DQ_SLOTS_DIR' && k !== 'DQ_SLOTS_POLL_SEC') delete process.env[k];
    delete process.env.DQ_LOOK_PIN_SLOTS;
    expect(slotCapacity('dm_compile')).toBe(2);
    expect(slotCapacity('test_world')).toBe(3);
    expect(slotCapacity('cargo')).toBe(1);
    expect(slotCapacity('look_state_pin')).toBe(2);
    process.env.DQ_SLOTS_DM_COMPILE = '5';
    expect(slotCapacity('dm_compile')).toBe(5);
    process.env.DQ_LOOK_PIN_SLOTS = '4';
    expect(slotCapacity('look_state_pin')).toBe(4);
    process.env.DQ_SLOTS_CARGO = '0';
    expect(slotCapacity('cargo')).toBe(0);
    process.env.DQ_SLOTS = '0';
    expect(slotCapacity('test_world')).toBe(0);
  });

  test('a class that is off returns no slot at once', async () => {
    process.env.DQ_SLOTS_CARGO = '0';
    expect(await acquireSlot('cargo', 'off', quiet)).toBeNull();
  });
});

describe('the queue', () => {
  test('the second holder waits for the first, the merge worktree goes first', async () => {
    process.env.DQ_SLOTS_CARGO = '1';
    const a = await acquireSlot('cargo', 'a', quiet);
    expect(a).not.toBeNull();
    const order: string[] = [];
    process.env.DQ_SLOT_PRIORITY = '1';
    const b = acquireSlot('cargo', 'b', quiet).then((s) => {
      order.push('b');
      return s;
    });
    await new Promise((r) => setTimeout(r, 1200));
    process.env.DQ_SLOT_PRIORITY = '0';
    const c = acquireSlot('cargo', 'c-merge', quiet).then((s) => {
      order.push('c');
      return s;
    });
    await new Promise((r) => setTimeout(r, 1200));
    expect(order).toEqual([]);
    expect(slotsStatus(['cargo'])).toContain("'a'");
    a?.release();
    const cs = await c;
    expect(order).toEqual(['c']);
    cs?.release();
    (await b)?.release();
    expect(order).toEqual(['c', 'b']);
    const events = fs.readFileSync(path.join(slotsDir(), 'events.tsv'), 'utf-8').trim().split('\n');
    expect(events.map((l) => l.split('\t')[4])).toEqual(['a', 'c-merge', 'b']);
  });

  test('a dead holder is reclaimed', async () => {
    process.env.DQ_SLOTS_CARGO = '1';
    const dir = path.join(tmp, 'cargo', 'slot.1');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'owner'), `kind=node\npid=2147480000\nwinpid=2147480000\nworktree=/x/crashed\nlabel=crashed\nstarted=${Math.floor(Date.now() / 1000)}\n`);
    const msgs: string[] = [];
    const s = await acquireSlot('cargo', 'after-crash', (m) => msgs.push(m));
    expect(s).not.toBeNull();
    expect(msgs.join('\n')).toContain('reclaiming a dead slot');
    s?.release();
  });

  test('a stale heartbeat reclaims a slot whose pid we cannot tell is dead', async () => {
    process.env.DQ_SLOTS_CARGO = '1';
    process.env.DQ_SLOTS_STALE_SEC = '5';
    const dir = path.join(tmp, 'cargo', 'slot.1');
    fs.mkdirSync(dir, { recursive: true });
    const owner = path.join(dir, 'owner');
    // Our own pid is alive, but the heartbeat is an hour old.
    fs.writeFileSync(owner, `kind=node\npid=${process.pid}\nwinpid=${process.pid}\nworktree=/x/frozen\nlabel=frozen\nstarted=1\n`);
    const old = new Date(Date.now() - 3600 * 1000);
    fs.utimesSync(owner, old, old);
    const s = await acquireSlot('cargo', 'after-freeze', quiet);
    expect(s).not.toBeNull();
    s?.release();
    delete process.env.DQ_SLOTS_STALE_SEC;
  });
});

describe('agrees with tools/dq_machine_slots.sh', () => {
  const script = path.resolve(import.meta.dir, '../../dq_machine_slots.sh').split(path.sep).join('/');
  const exited = (c: ReturnType<typeof spawn>) => new Promise<number | null>((resolve) => c.on('exit', resolve));
  const bash = spawnSync('bash', ['--version'], { encoding: 'utf-8' });

  test.skipIf(bash.status !== 0)('a slot held by the script blocks the build tool, and the other way round', async () => {
    process.env.DQ_SLOTS_CARGO = '1';
    // The script holds the only slot for 4 s.
    const child = spawn('bash', [script, 'run', 'cargo', '--label', 'shell-holder', '--', 'sleep', '6'], { env: process.env, stdio: 'ignore' });
    const childDone = exited(child);
    // bash takes a few seconds to start on a loaded Windows machine: wait until it holds the slot.
    for (let i = 0; i < 40 && !fs.existsSync(path.join(tmp, 'cargo', 'slot.1', 'owner')); i++) await new Promise((r) => setTimeout(r, 500));
    expect(slotsStatus(['cargo'])).toContain("'shell-holder'");
    const t0 = Date.now();
    const s = await acquireSlot('cargo', 'node-waiter', quiet);
    expect(Date.now() - t0).toBeGreaterThan(1500);
    expect(s).not.toBeNull();
    // Now this process holds it; the script must wait.
    const status = spawnSync('bash', [script, 'status', 'cargo'], { env: process.env, encoding: 'utf-8' });
    expect(status.stdout).toContain("'node-waiter'");
    const waiter = spawn('bash', [script, 'run', 'cargo', '--label', 'shell-waiter', '--', 'true'], { env: process.env, stdio: 'ignore' });
    const waiterDone = exited(waiter);
    // The script is slow to start and polls every second: it must still be waiting after several of its polls.
    await new Promise((r) => setTimeout(r, 6000));
    expect(waiter.exitCode).toBeNull();
    s?.release();
    expect(await waiterDone).toBe(0);
    await childDone;
  }, 60000);
});
