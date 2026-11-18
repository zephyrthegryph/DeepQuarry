import fs from 'node:fs';
import path from 'node:path';

/**
 * Every Cargo build stays incremental, including lane, gate, CI and retries.
 * This explicit user policy overrides profile defaults and earlier opt-outs.
 * Clear the incompatible rustc wrapper; preserve workspace instrumentation.
 * Existing retry count, failure behavior and cache cleanup remain unchanged.
 */
export type CargoKind = 'lane' | 'gate';

export function cargoIncrementalEnv(_env: NodeJS.ProcessEnv = process.env, _kind: CargoKind = 'gate'): Record<string, string> {
  return { CARGO_INCREMENTAL: '1', RUSTC_WRAPPER: '' };
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
  const env = { ...process.env, ...(options?.env ?? {}), ...cargoIncrementalEnv(options?.env ?? process.env, deps.kind ?? 'lane') };
  let result = await deps.exec(args, env, options?.cwd);
  if (result.code !== 0 && compilerPanicSignature(result.combined ?? '')) {
    const target = cargoTargetDir(args, env, path.resolve(options?.cwd ?? '.'));
    const removed = clearIncremental(target);
    deps.warn(`cargo ${args[0]}: rustc panicked; removed ${removed.length} incremental dir(s) under ${target} and retrying once`);
    result = await deps.exec(args, { ...env, ...cargoIncrementalEnv(env, deps.kind ?? 'lane') }, options?.cwd);
  }
  if (result.code !== 0) throw new Error(`cargo ${args[0]} failed (exit ${result.code})`);
}
