import fs from 'node:fs';
import path from 'node:path';

/**
 * rustc's incremental cache is the usual cause of "the compiler unexpectedly panicked": concurrent or killed builds leave a corrupt
 * session directory and every later build of that target dies on it. Gate and CI builds are one-shot, so incremental buys them nothing
 * and costs them this failure: they run with CARGO_INCREMENTAL=0. An interactive dev build opts back in with DQ_CARGO_INCREMENTAL=1
 * (the `dev-fast` profile's own incremental setting then applies). If a build still panics, the build tooling logs it, deletes the
 * target's incremental directories and retries once (see cargoWithIceRetry in build.ts and executeCargo in analyze_test_cache.ts).
 */
export function cargoIncrementalEnv(env: NodeJS.ProcessEnv = process.env): Record<string, string> {
  if (env.DQ_CARGO_INCREMENTAL === '1') return {};
  return { CARGO_INCREMENTAL: '0' };
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
