/**
 * Per-worktree dmbc daemon namespaces and the machine-wide resident-daemon cap.
 *
 * The daemon endpoint is per user and a client with a different compiler build retires the daemon it finds, so concurrent
 * worktrees used to evict each other's daemon and fall back to full compiles ("no patch base retained"). Every native compile
 * now runs with `DMB_DAEMON_NAMESPACE` defaulted to `wt-<hash of the git toplevel>`: each worktree owns one daemon, and a
 * different build in another worktree cannot reach it. `DMB_DAEMON_NAMESPACE` set by the caller wins (validated by dmbc).
 *
 * A daemon holds about 8 GB, so at most `DQ_DMBC_MAX_DAEMONS` (default 2, the DM compile slot cap) stay resident. Registry
 * under `DQ_DMBC_DAEMON_DIR` (default E:/dq-cache/dmb-daemon/ns, else ~/.cache/dq/dmb-daemon/ns):
 * - `<ns>.json`: {namespace, root, lastUsed}, written when a compile in that namespace starts and ends.
 * - `<ns>.lease.<pid>`: one per running compile; live while the pid is alive and the heartbeat (mtime) is under 15 minutes.
 * Before a compile starts, if more namespaces are registered than the cap, the least recently used ones with no live lease are
 * asked to retire (`dmbc --daemon-retire`, which drains running builds first). A namespace with a live lease is never touched,
 * so the cap is soft when every resident daemon is busy. `DQ_DMBC_MAX_DAEMONS=0` turns the cap off.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const LEASE_STALE_MS = 15 * 60 * 1000;
const LEASE_BEAT_MS = 60 * 1000;
const LOCK_STALE_MS = 2 * 60 * 1000;

export function daemonRegistryDir(): string {
  if (process.env.DQ_DMBC_DAEMON_DIR) return process.env.DQ_DMBC_DAEMON_DIR;
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/dmb-daemon/ns';
  return path.join(os.homedir(), '.cache', 'dq', 'dmb-daemon', 'ns');
}

export function maxResidentDaemons(): number {
  const raw = process.env.DQ_DMBC_MAX_DAEMONS ?? '2';
  if (!/^[0-9]+$/.test(raw)) throw new Error('DQ_DMBC_MAX_DAEMONS must be a non-negative integer.');
  return Number(raw);
}

/** `wt-<16 hex>` of the normalised checkout root; stable across runs, valid for DMB_DAEMON_NAMESPACE. */
export function worktreeNamespace(root: string): string {
  const key = path.resolve(root).replace(/\\/g, '/').toLowerCase().replace(/\/+$/, '');
  return `wt-${createHash('sha256').update(key).digest('hex').slice(0, 16)}`;
}

/** The namespace a compile from `root` uses: the caller's override, else the per-worktree default. */
export function effectiveNamespace(root: string): string {
  return process.env.DMB_DAEMON_NAMESPACE || worktreeNamespace(root);
}

function pidAlive(pid: number): boolean {
  if (!pid || Number.isNaN(pid)) return false;
  try { process.kill(pid, 0); return true; }
  catch (error) { return (error as NodeJS.ErrnoException)?.code === 'EPERM'; }
}

function log(message: string): void {
  try { process.stderr.write(`dmbc daemons: ${message}\n`); } catch { /* logging only */ }
}

function liveLeases(dir: string, namespace: string): number {
  let live = 0;
  for (const name of fs.readdirSync(dir)) {
    if (!name.startsWith(`${namespace}.lease.`)) continue;
    const file = path.join(dir, name);
    const pid = Number(name.slice(`${namespace}.lease.`.length));
    let fresh = false;
    try { fresh = Date.now() - fs.statSync(file).mtimeMs < LEASE_STALE_MS; } catch { /* raced away */ }
    if (pidAlive(pid) && fresh) live++;
    else try { fs.unlinkSync(file); } catch { /* raced away */ }
  }
  return live;
}

function withLock<T>(dir: string, body: () => T): T {
  const lock = path.join(dir, 'registry.lock');
  const deadline = Date.now() + 30_000;
  for (;;) {
    try { fs.mkdirSync(lock); break; }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
      try { if (Date.now() - fs.statSync(lock).mtimeMs > LOCK_STALE_MS) { fs.rmdirSync(lock); continue; } } catch { continue; }
      if (Date.now() > deadline) return body(); // never block a build on bookkeeping
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
    }
  }
  try { return body(); } finally { try { fs.rmdirSync(lock); } catch { /* already gone */ } }
}

function writeEntry(dir: string, namespace: string, root: string): void {
  fs.writeFileSync(path.join(dir, `${namespace}.json`), JSON.stringify({ namespace, root, lastUsed: Date.now() }));
}

function readEntries(dir: string): { namespace: string; root: string; lastUsed: number }[] {
  const entries = [];
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith('.json')) continue;
    try {
      const entry = JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8'));
      if (typeof entry.namespace === 'string' && typeof entry.lastUsed === 'number') entries.push(entry);
    } catch { /* torn write: ignore */ }
  }
  return entries;
}

function retire(executable: string, namespace: string): string {
  const result = spawnSync(executable, ['--daemon-retire'], {
    env: { ...process.env, DMB_DAEMON_NAMESPACE: namespace, DMB_DAEMON_AUTOSTART: '0' },
    encoding: 'utf8', timeout: 15_000, windowsHide: true,
  });
  if (result.status === 0) return result.stdout.trim() || 'retiring';
  return `failed (${(result.stderr || result.error?.message || `status ${result.status}`).trim()})`;
}

export type DaemonScope = { namespace: string; release(): void };

/**
 * Enter the compile's daemon scope: pick the namespace (exported through DMB_DAEMON_NAMESPACE for the dmbc child), take a
 * lease, and evict least-recently-used idle daemons beyond the cap. Never throws: bookkeeping failure only loses the cap.
 */
export function enterDaemonScope(root: string, executable: string): DaemonScope {
  const namespace = effectiveNamespace(root);
  process.env.DMB_DAEMON_NAMESPACE = namespace;
  let dir: string;
  let lease: string;
  let beat: NodeJS.Timeout | undefined;
  try {
    dir = daemonRegistryDir();
    fs.mkdirSync(dir, { recursive: true });
    lease = path.join(dir, `${namespace}.lease.${process.pid}`);
    withLock(dir, () => {
      fs.writeFileSync(lease, String(Date.now()));
      writeEntry(dir, namespace, path.resolve(root));
      const cap = maxResidentDaemons();
      if (cap === 0) return;
      const others = readEntries(dir).filter((entry) => entry.namespace !== namespace).sort((a, b) => a.lastUsed - b.lastUsed);
      let resident = others.length + 1;
      for (const entry of others) {
        if (resident <= cap) break;
        if (liveLeases(dir, entry.namespace) > 0) { log(`keeping ${entry.namespace} (${entry.root}): a build is running`); continue; }
        const outcome = retire(executable, entry.namespace);
        log(`evicting idle ${entry.namespace} (${entry.root}) to stay within DQ_DMBC_MAX_DAEMONS=${cap}: ${outcome}`);
        if (outcome.startsWith('failed')) continue; // still resident as far as we know: keep it registered
        try { fs.unlinkSync(path.join(dir, `${entry.namespace}.json`)); } catch { /* raced away */ }
        resident--;
      }
      if (resident > cap) log(`${resident} daemons resident, cap ${cap}: the rest are busy; the cap is soft until they finish`);
    });
    beat = setInterval(() => { try { const now = new Date(); fs.utimesSync(lease, now, now); } catch { /* lease gone */ } }, LEASE_BEAT_MS);
    beat.unref();
  } catch (error) {
    log(`registry unavailable, resident-daemon cap not enforced: ${error}`);
    return { namespace, release() {} };
  }
  return {
    namespace,
    release() {
      if (beat) clearInterval(beat);
      try { fs.unlinkSync(lease); } catch { /* already gone */ }
      try { withLock(dir, () => writeEntry(dir, namespace, path.resolve(root))); } catch { /* bookkeeping only */ }
    },
  };
}
