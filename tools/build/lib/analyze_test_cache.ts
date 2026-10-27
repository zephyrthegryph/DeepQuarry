// Cargo embeds CARGO_MANIFEST_DIR in the analyzer's tests. Bind each entry to its
// checkout as well as its inputs: an otherwise identical sibling must never test
// this checkout's fixture tree. Only compilation is cached; every harness runs.
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { cargoIncrementalEnv, cargoTargetDir, clearIncremental, compilerPanicSignature } from './cargo_ice';

type Result = { code: number; stdout: string; stderr?: string };
type RunOptions = { cwd: string; env: NodeJS.ProcessEnv; capture: boolean };
export type TestCommand = (command: string, args: string[], options: RunOptions) => Promise<Result>;
type Artifact = { file: string; sha256: string; run: boolean; name: string };
type Manifest = { key: string; checkout: string; artifacts: Artifact[] };
export type AnalyzeTestOptions = {
  root: string;
  cache?: string | null;
  profile?: string;
  testArgs?: string[];
  env?: NodeJS.ProcessEnv;
  run?: TestCommand;
  buildSlot?: <T>(action: () => Promise<T>) => Promise<T>;
  log?: (message: string) => void;
  budgetBytes?: number;
  maxAgeMs?: number;
  now?: () => number;
};

const DAY_MS = 24 * 60 * 60 * 1000;

function sizeOf(dir: string): number {
  let total = 0;
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const child = path.join(dir, item.name);
    total += item.isDirectory() ? sizeOf(child) : fs.statSync(child).size;
  }
  return total;
}

// The cache is disposable: entries older than the age cap go first, then the least recently used until the
// total fits the size cap. The entry in use (`keep`) is never removed. Lock files are never touched.
export function evictAnalyzeTestCache(cache: string, keep: string, budgetBytes: number, maxAgeMs: number, now: number, log: (message: string) => void): void {
  if (!fs.existsSync(cache)) return;
  const entries = fs.readdirSync(cache, { withFileTypes: true })
    .filter((item) => item.isDirectory() && item.name !== keep)
    .map((item) => {
      const dir = path.join(cache, item.name);
      return { name: item.name, dir, mtime: fs.statSync(dir).mtimeMs, size: sizeOf(dir) };
    })
    .sort((a, b) => a.mtime - b.mtime);
  const kept = path.join(cache, keep);
  let total = (fs.existsSync(kept) ? sizeOf(kept) : 0) + entries.reduce((sum, e) => sum + e.size, 0);
  for (const entry of entries) {
    const old = now - entry.mtime > maxAgeMs;
    if (!old && total <= budgetBytes) break;
    fs.rmSync(entry.dir, { recursive: true, force: true });
    total -= entry.size;
    log(`analyze test cache: evicted ${entry.name} (${old ? 'age' : 'size'} cap)`);
  }
}

export const runTestCommand: TestCommand = (command, args, options) => new Promise((resolve, reject) => {
  // stderr is piped and echoed so a compiler panic (rustc's ICE banner) can be recognised after the fact.
  const child = spawn(command, args, { cwd: options.cwd, env: options.env, stdio: ['ignore', options.capture ? 'pipe' : 'inherit', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout?.on('data', (bytes) => { stdout += bytes.toString(); });
  child.stderr?.on('data', (bytes) => { process.stderr.write(bytes); stderr = (stderr + bytes.toString()).slice(-200_000); });
  child.on('error', reject);
  child.on('close', (code) => resolve({ code: code ?? 1, stdout, stderr }));
});

function filesUnder(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const files: string[] = [];
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    if (item.name === '.git' || item.name === 'target' || item.name.startsWith('target-')) continue;
    const child = path.join(dir, item.name);
    if (item.isSymbolicLink()) throw new Error(`analyze test cache: symlink input needs uncached Cargo: ${child}`);
    if (item.isDirectory()) files.push(...filesUnder(child));
    else if (item.isFile()) files.push(child);
  }
  return files;
}

function executableDoctests(files: string[]): boolean {
  for (const file of files.filter((file) => file.endsWith('.rs'))) {
    const text = fs.readFileSync(file, 'utf8');
    // Doc attributes and block-doc fences need rustdoc's full parser; retain Cargo.
    if (/#[ \t]*\[doc\b/.test(text) || (text.match(/\/\*\*[\s\S]*?\*\//g) || []).some((block) => block.includes('```'))) return true;
    let open = false;
    for (const line of text.split('\n')) {
      const fence = /^\s*\/\/(?:\/|!)\s*```([^`]*)\s*$/.exec(line);
      if (!fence) continue;
      if (open) { open = false; continue; }
      open = true;
      const language = fence[1].trim().split(/[ ,]/)[0];
      if (!['text', 'toml', 'dm', 'json', 'sh', 'bash', 'ignore'].includes(language)) return true;
    }
    if (open) return true;
  }
  return false;
}

function digest(file: string): string {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function readManifest(dir: string, key: string, checkout: string): Manifest | null {
  try {
    const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8')) as Manifest;
    if (manifest.key !== key || manifest.checkout !== checkout || !Array.isArray(manifest.artifacts) || !manifest.artifacts.some((a) => a.run)) return null;
    const seen = new Set<string>();
    for (const artifact of manifest.artifacts) {
      if (typeof artifact.file !== 'string' || path.basename(artifact.file) !== artifact.file || seen.has(artifact.file)) return null;
      seen.add(artifact.file);
      if (digest(path.join(dir, artifact.file)) !== artifact.sha256) return null;
    }
    return manifest;
  } catch { return null; }
}

export async function runAnalyzeTests(options: AnalyzeTestOptions): Promise<void> {
  const root = fs.realpathSync(options.root);
  const cwd = path.join(root, 'tools/analyze');
  // One-shot gate builds are not incremental (lib/cargo_ice.ts): a corrupt incremental cache is what makes rustc panic.
  const env = { ...process.env, ...cargoIncrementalEnv(), ...options.env, CARGO_BUILD_JOBS: '2' };
  const run = options.run ?? runTestCommand;
  const log = options.log ?? console.log;
  const profile = options.profile ?? env.DQ_ANALYZE_TEST_PROFILE ?? 'dev';
  const profileArgs = profile === 'dev' ? [] : ['--profile', profile];
  const testArgs = options.testArgs ?? [];
  const slot = options.buildSlot ?? ((action) => action());
  const configuredCache = options.cache === undefined ? env.DQ_ANALYZE_TEST_CACHE : options.cache;
  const cache = configuredCache === null || configuredCache === 'off' || configuredCache === '0' ? null
    : configuredCache || (process.platform === 'win32' ? 'E:/dq-cache/analyze-test' : path.join(os.homedir(), '.cache/dq/analyze-test'));
  const execute = async (command: string, args: string[], capture = true): Promise<string> => {
    let result = await run(command, args, { cwd, env, capture });
    if (result.code !== 0 && command === 'cargo' && compilerPanicSignature(result.stderr ?? '')) {
      // The classic corrupt-incremental-cache ICE: log it, drop this target's incremental directories, build once more. A retry
      // also leaves RUSTC_WRAPPER out, so a wrapper (sccache) cannot be what panics the second time.
      const target = cargoTargetDir(args, env, cwd);
      const removed = clearIncremental(target);
      log(`analyze tests: rustc panicked (cargo ${args[0]}); removed ${removed.length} incremental dir(s) under ${target} and retrying once`);
      result = await run(command, args, { cwd, env: { ...env, RUSTC_WRAPPER: '', CARGO_BUILD_RUSTC_WRAPPER: '' }, capture });
    }
    if (result.code !== 0) throw new Error(`analyze tests: ${command} failed (exit ${result.code})`);
    return result.stdout;
  };
  const uncached = async (why: string) => {
    log(`analyze test cache: bypass (${why})`);
    await slot(() => execute('cargo', ['test', '--no-fail-fast', ...profileArgs, ...(testArgs.length ? ['--', ...testArgs] : [])], false));
  };
  if (!cache) { await uncached('disabled'); return; }

  let key: string;
  let inputs: string[];
  let makeKey: () => string;
  try {
    // Metadata supplies every local/path dependency, including patch overrides;
    // registry/git versions are pinned by the lockfile. No compilation occurs.
    const metadata = JSON.parse(await execute('cargo', ['metadata', '--locked', '--offline', '--format-version=1']));
    const packageDirs: string[] = metadata.packages.filter((p: { source: string | null }) => p.source === null)
      .map((p: { manifest_path: string }) => fs.realpathSync(path.dirname(p.manifest_path)));
    const configurationCandidates: string[] = [];
    inputs = [...new Set(packageDirs.flatMap(filesUnder))];
    for (let ancestor = cwd; ; ancestor = path.dirname(ancestor)) {
      for (const relative of ['.cargo/config', '.cargo/config.toml', 'rust-toolchain', 'rust-toolchain.toml']) {
        const file = path.join(ancestor, relative);
        configurationCandidates.push(file);
        if (fs.existsSync(file)) inputs.push(file);
      }
      if (path.dirname(ancestor) === ancestor) break;
    }
    const cargoHome = env.CARGO_HOME || path.join(os.homedir(), '.cargo');
    for (const name of ['config', 'config.toml']) {
      const file = path.join(cargoHome, name);
      configurationCandidates.push(file);
      if (fs.existsSync(file)) inputs.push(file);
    }
    // The fixture tests read the repo's lint scopes (outside the package), so a scope change must miss the cache.
    const scopesFile = path.join(root, 'tools/ci/lint_scopes.toml');
    if (fs.existsSync(scopesFile)) inputs.push(scopesFile);
    inputs = [...new Set(inputs)].sort();
    // Doctests run only for the package under test: `cargo test` in tools/analyze (its own workspace root) never runs a path
    // dependency's doctests ("Doc-tests dq_analyze" is the only doctest section). So only that package's own files are classified;
    // a vendored dependency (vendor/dreammaker's `#[doc(hidden)]`, vendor/interval-tree's untagged fences) made every gate bypass the
    // cache and recompile the harnesses (~9 min of a 10-11 min analyze_tests job, train gates 2026-10-26). Files still hash into the key.
    const own = fs.realpathSync(cwd);
    const nested = packageDirs.filter((dir) => dir !== own && dir.startsWith(`${own}${path.sep}`));
    const ownFiles = filesUnder(own).filter((file) => !nested.some((dir) => file.startsWith(`${dir}${path.sep}`)));
    if (executableDoctests(ownFiles)) throw new Error('executable or unclassified doctests');
    const toolchain = `${await execute('rustc', ['-vV'])}\0${await execute('cargo', ['--version'])}`;
    const settings = [...new Set(['RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'RUSTC', 'RUSTDOC', 'RUSTUP_TOOLCHAIN', 'RUSTC_BOOTSTRAP', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER', 'CC', 'CFLAGS', 'CXX', 'CXXFLAGS', 'AR',
      ...Object.keys(env).filter((name) => name.startsWith('CARGO_PROFILE_') || name.startsWith('CARGO_TARGET_') || name.startsWith('CARGO_BUILD_')),
    ])].sort().map((name) => `${name}=${env[name] || ''}`).join('\0');
    makeKey = () => {
      const hash = createHash('sha256').update(`analyze-tests-v1\0${root}\0${profile}\0${process.platform}\0${process.arch}\0${toolchain}\0${settings}\0`);
      const currentInputs = [...new Set([...packageDirs.flatMap(filesUnder), ...configurationCandidates.filter((file) => fs.existsSync(file))])].sort();
      for (const file of currentInputs) {
        const bytes = fs.readFileSync(file);
        hash.update(`${file}\0${bytes.length}\0`).update(bytes);
      }
      return hash.digest('hex');
    };
    key = makeKey();
  } catch (error) {
    await uncached(error instanceof Error ? error.message : String(error));
    return;
  }
  const dir = path.join(cache, key);
  const budgetBytes = options.budgetBytes ?? Number(env.DQ_ANALYZE_TEST_BUDGET_GB || 4) * 1024 ** 3;
  const maxAgeMs = options.maxAgeMs ?? Number(env.DQ_ANALYZE_TEST_MAX_AGE_DAYS || 7) * DAY_MS;
  const now = options.now ?? Date.now;
  let manifest = readManifest(dir, key, root);
  if (!manifest) {
    await slot(async () => {
      // The cargo machine slot serializes builders. A waiter may now find the
      // complete entry another gate published; readers need no mutable locks.
      manifest = readManifest(dir, key, root);
      if (manifest) return;
      log(`analyze test cache: miss ${key.slice(0, 16)}; compiling harnesses`);
      const stdout = await execute('cargo', ['test', '--locked', '--no-run', '--message-format=json', ...profileArgs]);
      if (makeKey() !== key) throw new Error('analyze tests: inputs changed during compilation; nothing cached or executed');
      const sources = new Map<string, { file: string; run: boolean; name: string }>();
      for (const line of stdout.split('\n').filter(Boolean)) {
        const message = JSON.parse(line);
        if (message.reason === 'compiler-artifact' && message.profile?.test && message.executable) {
          sources.set(path.basename(message.executable), { file: message.executable, run: true, name: message.target.name });
          // Native dynamic dependencies live beside Cargo's artifacts.
          for (const file of fs.readdirSync(path.dirname(message.executable))) {
            if (/\.(dll|so|dylib)$/.test(file)) sources.set(file, { file: path.join(path.dirname(message.executable), file), run: false, name: file });
          }
        }
      }
      if (![...sources.values()].some((source) => source.run)) throw new Error('analyze tests: Cargo emitted no test executables');
      fs.mkdirSync(cache, { recursive: true });
      const staging = path.join(cache, `.stage-${process.pid}-${randomUUID()}`);
      fs.mkdirSync(staging);
      const built: Manifest = { key, checkout: root, artifacts: [] };
      for (const [file, source] of sources) {
        fs.copyFileSync(source.file, path.join(staging, file));
        built.artifacts.push({ file, sha256: digest(path.join(staging, file)), run: source.run, name: source.name });
      }
      fs.writeFileSync(path.join(staging, 'manifest.json'), JSON.stringify(built));
      // Never delete lock files or mutate a binary that another reader runs.
      // A damaged entry is retained separately, then replaced as one directory.
      if (fs.existsSync(dir)) fs.renameSync(dir, `${dir}.invalid-${randomUUID()}`);
      fs.renameSync(staging, dir);
      manifest = readManifest(dir, key, root);
      if (!manifest) throw new Error('analyze tests: cached artifact integrity check failed');
    });
  } else log(`analyze test cache: hit ${key.slice(0, 16)}; running harnesses without Cargo test`);
  const stamp = new Date(now());
  fs.utimesSync(dir, stamp, stamp); // recency for eviction
  evictAnalyzeTestCache(cache, key, budgetBytes, maxAgeMs, now(), log);
  if (makeKey() !== key) throw new Error('analyze tests: inputs changed before harness execution');
  const failed: string[] = [];
  for (const artifact of manifest!.artifacts.filter((artifact) => artifact.run)) {
    log(`analyze tests: ${artifact.name}`);
    const result = await run(path.join(dir, artifact.file), testArgs, { cwd, env, capture: false });
    if (result.code !== 0) failed.push(`${artifact.name} (exit ${result.code})`);
  }
  if (makeKey() !== key) throw new Error('analyze tests: inputs changed during the test run');
  if (failed.length) throw new Error(`analyze tests failed: ${failed.join(', ')}`);
}
