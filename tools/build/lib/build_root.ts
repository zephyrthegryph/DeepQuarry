/** Checkout admission before Juke changes the process working directory. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

function canonical(directory: string): string {
  const value = fs.realpathSync.native(directory);
  return process.platform === 'win32' ? value.toLowerCase() : value;
}

export function validateBuildRoots(moduleRoot: string, wrapperRoot: string | undefined, invokingRoot: string, cache: string | undefined): void {
  if (!wrapperRoot || !path.isAbsolute(wrapperRoot) || cache !== '0') {
    throw new Error('Enter through tools/build/build.sh or build.bat: checkout pin and disabled Bun transpiler cache are required.');
  }
  const expected = canonical(wrapperRoot);
  if (canonical(moduleRoot) !== expected || canonical(invokingRoot) !== expected) {
    throw new Error('Build checkout differs from the wrapper or invoking Git checkout; refusing a sibling-worktree build.');
  }
}

export interface ToplevelProbe { error?: Error & { code?: string }; status: number | null; stdout: string }
export type ToplevelRunner = (cwd: string, timeoutMs: number) => ToplevelProbe;

const probeAttempts = 3;
const probeTimeoutMs = 30_000;

function runToplevel(cwd: string, timeoutMs: number): ToplevelProbe {
  const r = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8', timeout: timeoutMs, windowsHide: true });
  return { error: r.error as ToplevelProbe['error'], status: r.status, stdout: r.stdout ?? '' };
}

/**
 * The repository toplevel for `cwd`. A timeout or spawn failure (a loaded machine) is retried with
 * backoff; a clean non-zero answer means "not in a checkout" and is final.
 */
export function probeToplevel(
  cwd: string,
  run: ToplevelRunner = runToplevel,
  sleep: (ms: number) => void = (ms) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); },
): string {
  let transient = '';
  for (let attempt = 1; attempt <= probeAttempts; attempt++) {
    const r = run(cwd, probeTimeoutMs);
    if (!r.error && r.status === 0 && r.stdout.trim()) return r.stdout.trim();
    if (!r.error) {
      throw new Error(`Build invocation must start inside its Git checkout (rev-parse exited ${r.status} in ${cwd}).`);
    }
    transient = r.error.code === 'ETIMEDOUT' ? `timed out after ${probeTimeoutMs} ms` : `failed to run (${r.error.message})`;
    console.error(`build_root: rev-parse --show-toplevel ${transient} (attempt ${attempt}/${probeAttempts})`);
    if (attempt < probeAttempts) sleep(1000 * 2 ** (attempt - 1));
  }
  throw new Error(`Could not determine the checkout: rev-parse --show-toplevel ${transient} on all ${probeAttempts} attempts; the machine is probably overloaded, retry.`);
}

export function assertBuildRoot(moduleUrl: string): void {
  const moduleRoot = path.resolve(path.dirname(fileURLToPath(moduleUrl)), '../..');
  const top = probeToplevel(process.cwd());
  validateBuildRoots(moduleRoot, process.env.DQ_BUILD_ROOT, top, process.env.BUN_RUNTIME_TRANSPILER_CACHE_PATH);
}
