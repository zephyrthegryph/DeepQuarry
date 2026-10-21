// Controlled fake Cargo/Rust harnesses: no Rust or DM compilation.
// Run: bun test tools/ci/analyze_test_cache.test.ts
import { afterEach, beforeEach, expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { evictAnalyzeTestCache, runAnalyzeTests, type TestCommand } from '../build/lib/analyze_test_cache';

let temp: string;
let root: string;
let cache: string;
let cargoBuilds: number;
let calls: { command: string; args: string[]; cwd: string }[];
let rustcVersion: string;
let failHarness: boolean;
let localDependency: string;

beforeEach(() => {
  const base = process.env.DQ_ANALYZE_TEST_FIXTURES || 'E:/dq-cache/analyze-test-fixtures';
  fs.mkdirSync(base, { recursive: true });
  temp = fs.mkdtempSync(path.join(base, 'case-'));
  root = path.join(temp, 'checkout');
  cache = path.join(temp, 'cache');
  fs.mkdirSync(path.join(root, 'tools/analyze/src'), { recursive: true });
  fs.writeFileSync(path.join(root, 'tools/analyze/Cargo.toml'), '[package]\nname="fixture"\nversion="0.1.0"\n');
  fs.writeFileSync(path.join(root, 'tools/analyze/Cargo.lock'), 'lock-v1');
  fs.writeFileSync(path.join(root, 'tools/analyze/src/lib.rs'), '// source-v1\n');
  calls = [];
  cargoBuilds = 0;
  rustcVersion = 'rustc 1.90 host=test';
  failHarness = false;
  localDependency = '';
});

afterEach(() => {
  // Only this test's freshly created fixture tree; no lock files are created.
  const target = fs.realpathSync(temp);
  const parent = fs.realpathSync(path.dirname(temp));
  if (!target.startsWith(`${parent}${path.sep}`)) throw new Error('fixture cleanup escaped its parent');
  fs.rmSync(target, { recursive: true });
});

const fake: TestCommand = async (command, args, options) => {
  calls.push({ command, args, cwd: options.cwd });
  if (command === 'rustc') return { code: 0, stdout: rustcVersion };
  if (command === 'cargo' && args[0] === '--version') return { code: 0, stdout: 'cargo 1.90' };
  if (command === 'cargo' && args[0] === 'metadata') return { code: 0, stdout: JSON.stringify({ packages: [
    { source: null, manifest_path: path.join(root, 'tools/analyze/Cargo.toml') },
    ...(localDependency ? [{ source: null, manifest_path: path.join(localDependency, 'Cargo.toml') }] : []),
  ] }) };
  if (command === 'cargo' && args[0] === 'test') {
    cargoBuilds++;
    if (!args.includes('--no-run')) return { code: 0, stdout: 'uncached doctests ran' };
    const build = path.join(temp, `build-${cargoBuilds}`);
    fs.mkdirSync(build);
    const rows = ['lib-harness', 'integration-harness'].map((name) => {
      const file = path.join(build, name);
      fs.writeFileSync(file, `${name} binary generation ${cargoBuilds}`);
      return JSON.stringify({ reason: 'compiler-artifact', profile: { test: true }, executable: file, target: { name } });
    });
    return { code: 0, stdout: rows.join('\n') };
  }
  expect(fs.existsSync(command)).toBe(true);
  expect(fs.readFileSync(command, 'utf8')).toContain(path.basename(command));
  return { code: failHarness && path.basename(command) === 'lib-harness' ? 1 : 0, stdout: '' };
};

const run = (extra = {}) => runAnalyzeTests({ root, cache, run: fake, log: () => {}, env: { CARGO_HOME: path.join(temp, 'cargo-home') }, ...extra });

test('miss compiles both harnesses, hit executes both without Cargo test; exact args and cwd survive', async () => {
  let slots = 0;
  const buildSlot = async <T>(action: () => Promise<T>): Promise<T> => { slots++; return action(); };
  await run({ testArgs: ['needle', '--exact', '--nocapture'], buildSlot });
  expect(cargoBuilds).toBe(1);
  expect(calls.filter((c) => c.command === 'cargo' && c.args[0] === 'test')[0].args).toContain('--no-run');
  calls = [];
  await run({ testArgs: ['different', '--test-threads=1'], buildSlot });
  expect(cargoBuilds).toBe(1);
  expect(slots).toBe(1);
  const harnesses = calls.filter((c) => c.command !== 'cargo' && c.command !== 'rustc');
  expect(harnesses.length).toBe(2);
  for (const call of harnesses) {
    expect(call.args).toEqual(['different', '--test-threads=1']);
    expect(call.cwd).toBe(path.join(root, 'tools/analyze'));
  }
});

test('changed inputs during compilation never publish or execute the stale harnesses', async () => {
  const changing: TestCommand = async (command, args, options) => {
    const result = await fake(command, args, options);
    if (command === 'cargo' && args[0] === 'test') fs.writeFileSync(path.join(root, 'tools/analyze/src/added.rs'), '// new module');
    return result;
  };
  await expect(run({ run: changing })).rejects.toThrow('inputs changed during compilation');
  expect(calls.filter((c) => c.command !== 'cargo' && c.command !== 'rustc').length).toBe(0);
  expect(fs.existsSync(cache)).toBe(false);
});

test('missing Cargo test artifacts cannot produce a passing cache entry', async () => {
  const empty: TestCommand = async (command, args, options) => command === 'cargo' && args[0] === 'test'
    ? { code: 0, stdout: '' } : fake(command, args, options);
  await expect(run({ run: empty })).rejects.toThrow('no test executables');
  expect(fs.existsSync(cache)).toBe(false);
});

test('source, Cargo.lock, toolchain and profile changes independently invalidate', async () => {
  await run();
  fs.appendFileSync(path.join(root, 'tools/analyze/src/lib.rs'), '// change\n');
  await run();
  fs.appendFileSync(path.join(root, 'tools/analyze/Cargo.lock'), '\nlock-v2');
  await run();
  rustcVersion = 'rustc 1.91 host=test';
  await run();
  await run({ profile: 'release' });
  expect(cargoBuilds).toBe(5);
  expect(calls.filter((c) => c.command === 'cargo' && c.args[0] === 'test').at(-1)?.args).toContain('release');
});

test('a transitive path dependency and Cargo configuration invalidate the key', async () => {
  localDependency = path.join(temp, 'dependency');
  fs.mkdirSync(path.join(localDependency, 'src'), { recursive: true });
  fs.writeFileSync(path.join(localDependency, 'Cargo.toml'), '[package]\nname="dependency"\n');
  fs.writeFileSync(path.join(localDependency, 'src/lib.rs'), '// dep-v1');
  await run();
  fs.appendFileSync(path.join(localDependency, 'src/lib.rs'), '\n// dep-v2');
  await run();
  fs.mkdirSync(path.join(root, '.cargo'));
  fs.writeFileSync(path.join(root, '.cargo/config.toml'), '[build]\nrustflags=[]');
  await run();
  expect(cargoBuilds).toBe(3);
});

test('Cargo build target and build rustflags invalidate cached executables', async () => {
  const env = { CARGO_HOME: path.join(temp, 'cargo-home'), CARGO_BUILD_TARGET: 'first-target' };
  await run({ env });
  await run({ env });
  expect(cargoBuilds).toBe(1);
  await run({ env: { ...env, CARGO_BUILD_TARGET: 'second-target' } });
  await run({ env: { ...env, CARGO_BUILD_TARGET: 'second-target', CARGO_BUILD_RUSTFLAGS: '--cfg another_build' } });
  expect(cargoBuilds).toBe(3);
});

test('a sibling checkout never reuses binaries with another CARGO_MANIFEST_DIR', async () => {
  await run();
  const sibling = path.join(temp, 'sibling');
  fs.cpSync(root, sibling, { recursive: true });
  root = sibling;
  await run();
  expect(cargoBuilds).toBe(2);
});

test('a corrupted artifact is rebuilt instead of executed', async () => {
  await run();
  const entry = fs.readdirSync(cache)[0];
  fs.writeFileSync(path.join(cache, entry, 'lib-harness'), 'corrupt');
  await run();
  expect(cargoBuilds).toBe(2);
  expect(fs.readdirSync(cache).some((name) => name.includes('.invalid-'))).toBe(true);
});

test('no-fail-fast executes later harnesses and rejects any failure, even on a hit', async () => {
  await run();
  calls = [];
  failHarness = true;
  await expect(run()).rejects.toThrow('lib-harness (exit 1)');
  expect(calls.some((c) => path.basename(c.command) === 'integration-harness')).toBe(true);
  expect(cargoBuilds).toBe(1);
});

test('executable doctests use original Cargo and preserve harness arguments', async () => {
  fs.appendFileSync(path.join(root, 'tools/analyze/src/lib.rs'), '\n/// ```\n/// assert!(true);\n/// ```\n');
  await run({ testArgs: ['sample', '--exact'] });
  expect(calls.find((c) => c.command === 'cargo' && c.args[0] === 'test')?.args).toEqual(['test', '--no-fail-fast', '--', 'sample', '--exact']);
  expect(fs.existsSync(cache)).toBe(false);
});

test('eviction removes entries past the age cap, then least recently used past the size cap, never the entry in use', async () => {
  fs.mkdirSync(cache, { recursive: true });
  const day = 24 * 60 * 60 * 1000;
  const now = Date.now();
  const make = (name: string, ageDays: number) => {
    const dir = path.join(cache, name);
    fs.mkdirSync(dir);
    fs.writeFileSync(path.join(dir, 'blob'), 'x'.repeat(100));
    const when = new Date(now - ageDays * day);
    fs.utimesSync(dir, when, when);
  };
  make('ancient', 30);
  make('older', 3);
  make('newer', 1);
  make('current', 40);
  evictAnalyzeTestCache(cache, 'current', 250, 7 * day, now, () => {});
  expect(fs.existsSync(path.join(cache, 'ancient'))).toBe(false); // age cap
  expect(fs.existsSync(path.join(cache, 'older'))).toBe(false); // size cap: 300 bytes left, oldest goes first
  expect(fs.existsSync(path.join(cache, 'newer'))).toBe(true);
  expect(fs.existsSync(path.join(cache, 'current'))).toBe(true); // in use, however old
});

test('a hit refreshes recency so the entry survives eviction', async () => {
  await run();
  const entry = fs.readdirSync(cache)[0];
  const old = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  fs.utimesSync(path.join(cache, entry), old, old);
  await run();
  expect(fs.existsSync(path.join(cache, entry))).toBe(true);
  expect(Date.now() - fs.statSync(path.join(cache, entry)).mtimeMs).toBeLessThan(60 * 1000);
});
