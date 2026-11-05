import fs from 'node:fs';
import path from 'node:path';

/**
 * rustc's incremental cache is the usual cause of "the compiler unexpectedly panicked": concurrent or killed builds leave a corrupt
 * session directory and every later build of that target dies on it. Two kinds of cargo run:
 *
 *  - `lane` (the default for build.ts's cargo runs): a lane or dev build in a worktree of its own. Each worktree has its own target
 *    directory and the machine cargo slot serialises builds, so incremental is safe and an edit rebuilds only what changed. No
 *    CARGO_INCREMENTAL is set: the profile decides (`lane`, `dev-fast` and `dev` are incremental; `release` is not). Production
 *    and CI builds use `release`, so they stay non-incremental by profile as well as by the CI rule below.
 *  - `gate` (analyze_test_cache and other one-shot builds whose output is cached by content): CARGO_INCREMENTAL=0.
 *
 * CI (`CI` set) is always non-incremental. DQ_CARGO_INCREMENTAL=0 forces non-incremental for any run (the opt-out), =1 lets the
 * profile decide even in CI or a gate. If a build still panics, the build tooling logs it, deletes the target's incremental directories and retries once
 * (cargoWithIceRetry below).
 */
export type CargoKind = 'lane' | 'gate';

export function cargoIncrementalEnv(env: NodeJS.ProcessEnv = process.env, kind: CargoKind = 'gate'): Record<string, string> {
  if (env.DQ_CARGO_INCREMENTAL === '0') return { CARGO_INCREMENTAL: '0' };
  // =1 never sets CARGO_INCREMENTAL itself: sccache (the machine's rustc wrapper) refuses to run when the variable is set at all.
  if (env.DQ_CARGO_INCREMENTAL === '1') return {};
  if (env.CI || kind === 'gate') return { CARGO_INCREMENTAL: '0' };
  return {};
}

/** True when cargo output shows rustc itself crashed (an ICE), not a source error. */
export const compilerPanicSignature = (output: string): boolean => /the compiler unexpectedly panicked|internal compiler error/i.test(output);

/** The `incremental` directories of a cargo target dir: `<target>/<profile>/incremental` and `<target>/<triple>/<profile>/incremental`. */
export function incrementalDirs(target: string): string[] {
  const out: string[] = [];
  const subdirs = (dir: string): string[] => {
    try {
      return fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => path.join(dir, e.name));
    } catch {
      return [];
    }
  };
  const walk = (dir: string, depth: number) => {
    for (const child of subdirs(dir)) {
      if (path.basename(child) === 'incremental') out.push(child);
      else if (depth < 3 && !['deps', 'build', '.fingerprint'].includes(path.basename(child))) walk(child, depth + 1);
    }
  };
  walk(target, 1);
  return out.filter((dir) => fs.existsSync(dir));
}

/** Deletes the incremental caches of `target`; returns the directories removed. */
export function clearIncremental(target: string): string[] {
  const dirs = incrementalDirs(target);
  for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true });
  return dirs;
}

/** The target directory a cargo invocation uses: CARGO_TARGET_DIR, else `target` beside the manifest, else under `cwd`. */
export function cargoTargetDir(args: string[], env: NodeJS.ProcessEnv, cwd: string): string {
  if (env.CARGO_TARGET_DIR) return path.resolve(cwd, env.CARGO_TARGET_DIR);
  const at = args.indexOf('--manifest-path');
  if (at >= 0 && args[at + 1]) return path.resolve(cwd, path.dirname(args[at + 1]), 'target');
  return path.resolve(cwd, 'target');
}

export type CargoRunResult = { code: number; combined?: string };
export type CargoRunDeps = {
  /** Runs `cargo <args>` with this environment and working directory; never throws on a non-zero exit. */
  exec: (args: string[], env: NodeJS.ProcessEnv, cwd: string | undefined) => Promise<CargoRunResult>;
  warn: (message: string) => void;
  kind?: CargoKind;
};

/** One cargo run under the incremental policy above. If rustc panics (the corrupt incremental cache ICE) the panic is logged, the
 * target's incremental directories are deleted and the build runs once more without RUSTC_WRAPPER. Any other failure throws. */
export async function cargoWithIceRetry(args: string[], options: { cwd?: string; env?: NodeJS.ProcessEnv } | undefined, deps: CargoRunDeps): Promise<void> {
  const env = { ...process.env, ...cargoIncrementalEnv(process.env, deps.kind ?? 'lane'), ...(options?.env ?? {}) };
  let result = await deps.exec(args, env, options?.cwd);
  if (result.code !== 0 && compilerPanicSignature(result.combined ?? '')) {
    const target = cargoTargetDir(args, env, path.resolve(options?.cwd ?? '.'));
    const removed = clearIncremental(target);
    deps.warn(`cargo ${args[0]}: rustc panicked; removed ${removed.length} incremental dir(s) under ${target} and retrying once`);
    result = await deps.exec(args, { ...env, RUSTC_WRAPPER: '', CARGO_BUILD_RUSTC_WRAPPER: '' }, options?.cwd);
  }
  if (result.code !== 0) throw new Error(`cargo ${args[0]} failed (exit ${result.code})`);
}
