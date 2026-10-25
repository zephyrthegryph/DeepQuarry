/**
 * One resident dmbc daemon for the whole machine, plus the registry used when a caller opts into a namespace.
 *
 * Every native compile goes through the one shared compiler binary (lib/dmbc_cache.ts `sharedDmbcExe`), so every worktree
 * has the same compiler identity and talks to the same generation endpoint: one daemon serves all checkouts, keeping one
 * retained session per project root (the daemon bounds them by DMB_DAEMON_MEMORY_BUDGET_GB, evicts the least recently
 * used project, exits after DMB_DAEMON_IDLE_EXIT_SECS idle, and exits when its roots are gone). The old per-worktree
 * namespace default is gone: it multiplied an 8 GB daemon per checkout, and only daemons this file registered were ever
 * evicted. Daemons never replace each other: the endpoint is keyed by the compiler image, so a client talks only to the daemon
 * of its own version, a development build (anything not under `<bin>/v/<current>`) runs in a private namespace chosen by dmbc
 * itself, and a daemon leaves only for idleness, memory, or (a superseded published version) having no client left. There is no
 * machine-wide cap and no newcomer-retires-incumbent rule on the daemon side.
 *
 * `DMB_DAEMON_NAMESPACE` set by the caller still isolates that caller (a benchmark or an experiment build). Such a
 * namespace is bookkept here under `DQ_DMBC_DAEMON_DIR` (default E:/dq-cache/dmb-daemon/ns, else ~/.cache/dq/dmb-daemon/ns):
 * - `<ns>.json`: {namespace, root, lastUsed}, written when a compile in that namespace starts and ends.
 * - `<ns>.lease.<pid>`: one per running compile; live while the pid is alive and the heartbeat (mtime) is under 15 minutes.
 * Before a compile starts, if more namespaces are registered than the cap, the least recently used ones with no live lease are
 * asked to retire (`dmbc --daemon-retire`, which drains running builds first).
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const LEASE_STALE_MS = 15 * 60 * 1000;
const LEASE_BEAT_MS = 60 * 1000;
const LOCK_STALE_MS = 2 * 60 * 1000;
/** A caller-namespace daemon used within this long is never retired for the count: retirement is for idleness and memory. */
const NAMESPACE_MIN_IDLE_MS = 10 * 60 * 1000;
/** Memory a cold compile of a fresh namespace grows by (matches the daemon's cold growth default), and the reserve the shared daemon keeps free. */
const COLD_GROWTH_BYTES = 12e9;
function freeReserveBytes(): number {
  const gb = Number(process.env.DMB_DAEMON_FREE_RESERVE_GB ?? '12');
  return (Number.isFinite(gb) && gb >= 0 ? gb : 12) * 1e9;
}
/**
 * Memory-aware cap: a caller namespace that would start a cold session while free memory is under reserve + growth makes the
 * shared daemon shed its sessions (every game/test alternation then recompiles in full). Idle caller namespaces are retired
 * first, whatever their recency, least recently used first, until the new one fits; busy ones (live lease) are kept.
 */
export function memoryShortfallBytes(freeBytes: number = os.freemem()): number {
  return Math.max(0, freeReserveBytes() + COLD_GROWTH_BYTES - freeBytes);
}

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

/** The namespace a compile uses: the caller's override, else none (the one machine-wide daemon). */
export function effectiveNamespace(): string | undefined {
  return process.env.DMB_DAEMON_NAMESPACE || undefined;
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

export type DaemonScope = { namespace: string | undefined; release(): void };

/**
 * Enter the compile's daemon scope. Every native dmbc spawn goes through here. Without a caller namespace the compile uses
 * the one machine-wide daemon and there is nothing to bookkeep (the daemon caps and retires itself). With a namespace it takes
 * a lease and evicts least-recently-used idle namespaces beyond the cap. Never throws: bookkeeping failure only loses the cap.
 */
export function enterDaemonScope(root: string, executable: string): DaemonScope {
  const namespace = effectiveNamespace();
  if (!namespace) {
    delete process.env.DMB_DAEMON_NAMESPACE;
    return { namespace, release() {} };
  }
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
        if (Date.now() - entry.lastUsed < NAMESPACE_MIN_IDLE_MS) { log(`keeping ${entry.namespace} (${entry.root}): used within the last ${NAMESPACE_MIN_IDLE_MS / 60000} minutes`); continue; }
        if (liveLeases(dir, entry.namespace) > 0) { log(`keeping ${entry.namespace} (${entry.root}): a build is running`); continue; }
        const outcome = retire(executable, entry.namespace);
        log(`evicting idle ${entry.namespace} (${entry.root}) to stay within DQ_DMBC_MAX_DAEMONS=${cap}: ${outcome}`);
        if (outcome.startsWith('failed')) continue; // still resident as far as we know: keep it registered
        try { fs.unlinkSync(path.join(dir, `${entry.namespace}.json`)); } catch { /* raced away */ }
        resident--;
      }
      if (cap > 0 && memoryShortfallBytes() > 0) {
        for (const entry of others) {
          if (memoryShortfallBytes() <= 0) break;
          if (!fs.existsSync(path.join(dir, `${entry.namespace}.json`))) continue; // already retired above
          if (liveLeases(dir, entry.namespace) > 0) continue;
          const outcome = retire(executable, entry.namespace);
          log(`free memory ${(os.freemem() / 1e9).toFixed(1)} GB is under reserve + cold growth: retired idle ${entry.namespace} (${entry.root}): ${outcome}`);
          if (outcome.startsWith('failed')) continue;
          try { fs.unlinkSync(path.join(dir, `${entry.namespace}.json`)); } catch { /* raced away */ }
          resident--;
          break; // the daemon exits asynchronously: one retirement per start, the next start re-checks
        }
        if (memoryShortfallBytes() > 0) log(`warning: free memory is ${(os.freemem() / 1e9).toFixed(1)} GB, under the ${(freeReserveBytes() / 1e9).toFixed(0)} GB reserve plus a cold compile; the shared session may be evicted`);
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
