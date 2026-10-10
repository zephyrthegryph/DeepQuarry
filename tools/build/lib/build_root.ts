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

export function assertBuildRoot(moduleUrl: string): void {
  const moduleRoot = path.resolve(path.dirname(fileURLToPath(moduleUrl)), '../..');
  const git = spawnSync('git', ['rev-parse', '--show-toplevel'], {
    cwd: process.cwd(), encoding: 'utf8', timeout: 10_000, windowsHide: true,
  });
  if (git.error || git.status !== 0 || !git.stdout.trim()) {
    throw new Error('Build invocation must start inside its Git checkout.');
  }
  validateBuildRoots(moduleRoot, process.env.DQ_BUILD_ROOT, git.stdout.trim(), process.env.BUN_RUNTIME_TRANSPILER_CACHE_PATH);
}
