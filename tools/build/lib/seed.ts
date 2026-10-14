// Build-state helpers that avoid redoing work a fresh worktree or an unchanged tree has already paid for.
//
// - seedFromMainCheckout(): copies a data/ record from the repository's main checkout into a worktree that
//   lacks it (the same idea as icons/gen seeding in tools/dq_icons/build_step.py). DQ_DATA_SEED names another
//   directory to seed from (it holds the same relative paths, e.g. <dir>/data/map_template_bounds.json);
//   DQ_DATA_SEED=off disables seeding.
// - dmeValidationKey(): the dirty-check key of the validate-dme target.

import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

/** Root of the main checkout when `cwd` is a linked worktree, else null. */
export const mainCheckoutRoot = (cwd: string): string | null => {
  const override = process.env.DQ_DATA_SEED;
  if (override === 'off') return null;
  if (override) return path.resolve(override);
  const r = spawnSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], {
    cwd,
    encoding: 'utf-8',
  });
  if (r.status !== 0) return null;
  const common = r.stdout.trim();
  if (!common) return null;
  const root = path.dirname(common);
  return path.resolve(root) === path.resolve(cwd) ? null : root;
};

/**
 * Copies `rel` (relative to the repo root) from the main checkout when it is missing here.
 * Returns the source path on a copy, else null. Never overwrites an existing file.
 */
export const seedFromMainCheckout = (cwd: string, rel: string): string | null => {
  const dest = path.join(cwd, rel);
  if (fs.existsSync(dest)) return null;
  const root = mainCheckoutRoot(cwd);
  if (!root) return null;
  const src = path.join(root, rel);
  if (!fs.existsSync(src)) return null;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  return src;
};

/** True for the build-output .dm files `analyze gen` restores into code/ (gitignored). */
export const isGeneratedDm = (relPath: string): boolean => {
  const p = relPath.replaceAll('\\', '/');
  return p.startsWith('code/engine/_generated/') || p === 'code/_generated/reads.dm';
};

/**
 * Key for "validate-dme would give the same answer": deepquarry.dme's content, the full list of code/**\/.dm
 * paths, and the size and mtime of every non-generated .dm (a changed #include in an aggregator changes
 * reachability). Generated files count by path only, since `gen` rewrites them on every build.
 */
export const dmeValidationKey = (dmeText: string, dmFiles: string[], statOf: (f: string) => string): string => {
  const hash = createHash('sha256').update('validate-dme-v1|').update(dmeText);
  for (const file of [...dmFiles].map((f) => f.replaceAll('\\', '/')).sort()) {
    hash.update(file);
    if (!isGeneratedDm(file)) hash.update(statOf(file));
  }
  return hash.digest('hex');
};
