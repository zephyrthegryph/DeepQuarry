/**
 * Prewarm on publish. A new compiler version means a new daemon with no session, so the first compile after `current` moves
 * used to be cold (about 100 s for whoever compiled next). Instead the new version is published as a CANDIDATE
 * (`<bin>/next`, lib/dmbc_cache.ts `stageDmbcVersion`): every compile keeps resolving `current`, so the old daemon keeps serving
 * its warm sessions, while a child build compiles master's tree with the candidate compiler and leaves a session in the
 * candidate's daemon. Only then does `current` move (`promoteDmbcVersion`): the swap is immediate for new requests, the old daemon
 * (now superseded) drains and exits, and nobody waits for a cold build.
 *
 * What is prewarmed is the variant someone compiled last (the tail of the daemon's compile-stats), because two retained sessions
 * are about 10 GB each and the machine keeps a reserve free. Prewarm is skipped, and `current` moves at once as before, when it is
 * switched off (`DQ_DMBC_PREWARM=0`), nothing was compiled lately, the machine lacks the memory for a second session next to the
 * old daemon's, or another process is already prewarming.
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { dmbcVersionDir, promoteDmbcVersion } from './dmbc_cache';

export type PrewarmVariant = 'production' | 'test';

const LOCK_STALE_MS = 30 * 60 * 1000;
const RECENT_MS = 6 * 3600 * 1000;
/** Free physical memory a prewarm needs: the reserve the daemon keeps plus one cold session's growth. */
const NEED_BYTES = (8 + 12) * 1_000_000_000;

export function prewarmEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return (env.DQ_DMBC_PREWARM ?? '1') !== '0';
}

export function daemonStateDir(env: NodeJS.ProcessEnv = process.env): string {
  if (env.DMB_DAEMON_DIR) return env.DMB_DAEMON_DIR;
  if (process.platform === 'win32' && fs.existsSync('E:/dq-cache')) return 'E:/dq-cache/dmb-daemon';
  return path.join(os.homedir(), '.cache', 'dq', 'dmb-daemon');
}

/** The variant the last compile recorded in the daemon's stats, when that was recent; null otherwise. */
export function lastVariant(stateDir: string = daemonStateDir(), now: number = Date.now()): PrewarmVariant | null {
  let text: string;
  try {
    const file = `${stateDir}/compile-stats.jsonl`;
    const size = fs.statSync(file).size;
    const fd = fs.openSync(file, 'r');
    try {
      const length = Math.min(size, 64 * 1024);
      const buffer = Buffer.alloc(length);
      fs.readSync(fd, buffer, 0, length, size - length);
      text = buffer.toString('utf8');
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return null;
  }
  const lines = text.split('\n').filter((line) => line.trim().startsWith('{'));
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const record = JSON.parse(lines[i]);
      if (typeof record.variant !== 'string' || typeof record.at_ms !== 'number' || record.error) continue;
      if (now - record.at_ms > RECENT_MS) return null;
      if (/^deepquarry\.test\.dme$/i.test(record.variant)) return 'test';
      if (/^deepquarry\.dme$/i.test(record.variant)) return 'production';
    } catch {
      // a torn first line of the window
    }
  }
  return null;
}

/** `DQ_DMBC_PREWARM_NEED_GB` overrides the free memory required (default 8 GB reserve + 12 GB for a cold session). */
export function prewarmNeedBytes(env: NodeJS.ProcessEnv = process.env): number {
  const gb = Number(env.DQ_DMBC_PREWARM_NEED_GB);
  return Number.isFinite(gb) && gb > 0 ? gb * 1_000_000_000 : NEED_BYTES;
}

export function enoughMemoryToPrewarm(free: number = os.freemem(), need: number = prewarmNeedBytes()): boolean {
  return free >= need;
}

/** Take the machine-wide prewarm lock (one prewarm at a time). A lock older than half an hour is a crashed holder and is replaced. */
export function acquirePrewarmLock(binDir: string, now: number = Date.now()): (() => void) | null {
  const file = `${binDir}/prewarm.lock`;
  const token = `${process.pid} ${now}\n`;
  try {
    fs.writeFileSync(file, token, { flag: 'wx' });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'EEXIST') return null;
    let age = 0;
    try {
      age = now - fs.statSync(file).mtimeMs;
    } catch {
      return null;
    }
    if (age < LOCK_STALE_MS) return null;
    fs.writeFileSync(file, token);
  }
  return () => {
    try {
      if (fs.readFileSync(file, 'utf8') === token) fs.rmSync(file, { force: true });
    } catch {
      // already gone
    }
  };
}

export type PrewarmDecision = { variant: PrewarmVariant; release: () => void } | { skipped: string };

/** Decide whether to prewarm now and, if so, take the lock. */
export function planPrewarm(binDir: string, env: NodeJS.ProcessEnv = process.env): PrewarmDecision {
  if (!prewarmEnabled(env)) return { skipped: 'DQ_DMBC_PREWARM=0' };
  // No daemon keeps a prewarmed session, so a prewarm would be one whole cold compile thrown away.
  if (env.DQ_NATIVE_NO_DAEMON === '1') return { skipped: 'DQ_NATIVE_NO_DAEMON=1' };
  if (env.DMB_DAEMON_AUTOSTART === '0') return { skipped: 'DMB_DAEMON_AUTOSTART=0' };
  const variant = lastVariant(daemonStateDir(env));
  if (!variant) return { skipped: 'no compile in the last 6 hours' };
  if (!enoughMemoryToPrewarm(os.freemem(), prewarmNeedBytes(env))) return { skipped: `under ${(prewarmNeedBytes(env) / 1e9).toFixed(0)} GB of free memory (${(os.freemem() / 1e9).toFixed(1)} GB free)` };
  const release = acquirePrewarmLock(binDir);
  if (!release) return { skipped: 'another prewarm is running' };
  return { variant, release };
}

/**
 * Compile `variant` of the checkout at `root` with the candidate compiler (`<bin>/v/<id>`), through the ordinary build so it uses
 * the shared compile root and leaves its session in the candidate's daemon. Resolves with the child's exit code; never rejects.
 */
export function runPrewarmBuild(root: string, binDir: string, id: string, variant: PrewarmVariant, timeoutMs = 20 * 60 * 1000): Promise<number> {
  const exe = `${dmbcVersionDir(binDir, id)}/dmbc${process.platform === 'win32' ? '.exe' : ''}`;
  const logDir = `${path.dirname(binDir)}/dmb-prewarm`;
  fs.mkdirSync(logDir, { recursive: true });
  const log = fs.openSync(`${logDir}/${id}-${variant}.log`, 'w');
  return new Promise((resolve) => {
    const child = spawn('bash', ['tools/build/build.sh', 'prewarm', `--prewarm-variant=${variant}`], {
      cwd: root,
      env: { ...process.env, DQ_COMPILER: 'native', DQ_NATIVE_COMPILER: exe, DQ_DREAMCHECKER: '0' },
      stdio: ['ignore', log, log],
      windowsHide: true,
    });
    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.on('error', () => {
      clearTimeout(timer);
      resolve(-1);
    });
    child.on('exit', (code) => {
      clearTimeout(timer);
      resolve(code ?? -1);
    });
  });
}

/** Warm the candidate, then make it current whatever happened (a failed warm-up costs only the cold compile it was meant to save). */
export async function warmAndPromote(
  decision: { variant: PrewarmVariant; release: () => void },
  binDir: string,
  id: string,
  warm: (variant: PrewarmVariant) => Promise<number>,
  log: (message: string) => void = () => {},
): Promise<{ code: number; seconds: number }> {
  const started = Date.now();
  let code = -1;
  try {
    log(`dmbc prewarm: building a ${decision.variant} session with candidate ${id} while the current daemon keeps serving`);
    code = await warm(decision.variant);
  } catch (error) {
    log(`dmbc prewarm failed: ${error instanceof Error ? error.message : error}`);
  } finally {
    promoteDmbcVersion(binDir, id);
    decision.release();
  }
  const seconds = (Date.now() - started) / 1000;
  log(`dmbc prewarm: ${code === 0 ? 'session ready' : `warm-up exited ${code}`} after ${seconds.toFixed(0)}s; ${id} is now current`);
  return { code, seconds };
}
