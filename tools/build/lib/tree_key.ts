// A cheap "did anything under these paths change?" key from git, for the build's skip-when-unchanged records (deepquarry.dme
// generation, `analyze gen`, validate-dme). Walking and stat-ing the ~8k .dm files in Bun took 1.5-16 s on a loaded machine (and
// blocked the event loop); git keeps those stats in its index and answers in well under a second.
//
// The key is: the index entries of the paths (`git ls-files -s`: blob ids), `git status` of the paths with untracked AND ignored files listed one
// by one (ignored build output such as code/engine/_generated counts), and the size and mtime of every file that status lists (so an
// edit to an already-modified or ignored file changes the key). Extra files (a binary outside git, say) are keyed by size and mtime.
// A file whose content is unchanged but was touched is not listed by status, so it keeps the key, which is the point.
// Returns null when git is unavailable: callers then run their step as if the key had changed.
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';

const git = (cwd: string, args: string[]): Promise<string | null> =>
  new Promise((resolve) => {
    // --no-optional-locks: status must not take index.lock (another git command may run in this worktree).
    execFile('git', ['--no-optional-locks', ...args], { cwd, encoding: 'utf-8', maxBuffer: 256 * 1024 * 1024, windowsHide: true }, (err, stdout) =>
      resolve(err ? null : stdout),
    );
  });

const statOf = (file: string): string => {
  try {
    const st = fs.statSync(file);
    return `${st.size}:${st.mtimeMs}`;
  } catch {
    return 'missing';
  }
};

// A `git status --porcelain=v1 -z` token is `XY path`; a rename's second token is its bare old path, which is stat-ed too (harmless).

export const gitTreeKey = async (
  root: string,
  label: string,
  paths: string[],
  extraFiles: string[] = [],
  // false: an ignored file counts by presence only (gen_dme.py leaves ignored build output out of the manifest, so the bindings
  // generator rewriting _bindings.dm must not make it run again).
  statIgnored = true,
): Promise<string | null> => {
  const [tree, status] = await Promise.all([
    git(root, ['ls-files', '-s', '--', ...paths]),
    git(root, ['status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignored=traditional', '--', ...paths]),
  ]);
  if (tree === null || status === null) return null;
  const hash = createHash('sha256').update(`tree-key-v1|${label}|`).update(tree).update('\0|').update(status).update('\0|');
  for (const t of status.split('\0')) {
    if (!t) continue;
    const p = t.length > 3 && t[2] === ' ' ? t.slice(3) : t;
    if (!statIgnored && t.startsWith('!! ')) continue;
    hash.update(`${p}=${statOf(`${root}/${p}`)}\n`);
  }
  for (const f of extraFiles) hash.update(`extra ${f}=${statOf(f)}\n`);
  return hash.digest('hex');
};

/** The key stored in a record file by writeKeyRecord, or null. */
export const readKeyRecord = (file: string): string | null => {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf-8')).key ?? null;
  } catch {
    return null;
  }
};

export const writeKeyRecord = (file: string, key: string): void => {
  fs.mkdirSync(file.replace(/[/\\][^/\\]*$/, ''), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ key, checkedAt: new Date().toISOString() }));
};

/** Async spawn with captured output (spawnSync blocks Bun's event loop, so every target beside it stalls for its whole run). */
export const runCaptured = (
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<{ status: number | null; out: string; error?: Error }> =>
  new Promise((resolve) => {
    execFile(cmd, args, { ...opts, encoding: 'utf-8', maxBuffer: 256 * 1024 * 1024, windowsHide: true }, (err, stdout, stderr) => {
      const out = `${stdout || ''}${stderr || ''}`;
      if (err && typeof (err as NodeJS.ErrnoException).code === 'string') resolve({ status: null, out, error: err });
      else resolve({ status: err ? ((err as { code?: number }).code ?? 1) : 0, out });
    });
  });
