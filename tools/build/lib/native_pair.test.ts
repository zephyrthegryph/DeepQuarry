import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { conventionalOutput, createNativeRequestDirectory, parseAcquiredResult, parseCompileResult, withCompiledOutput, type NativePairOutput } from './native_pair';
import { stageRuntimeLibrary } from './runtime_library';

const native: NativePairOutput = { kind: 'native_pair', compiler: 'mock-dmbc', store: path.resolve('E:/dq-cache/fixture-store'), outputProject: path.resolve('project.dme'), pairId: '1'.repeat(32), dmbHash: '2'.repeat(32), rscHash: '3'.repeat(32), dmbBytes: 1, rscBytes: 2 };
function fields() {
  return { schema_version: 1, store: native.store, pair_id: native.pairId, dmb_hash: native.dmbHash, rsc_hash: native.rscHash, dmb_bytes: native.dmbBytes, rsc_bytes: native.rscBytes };
}
function acquired(root: string) {
  const slot = path.join(root, 'slot-mock');
  fs.mkdirSync(slot);
  const dmb = path.join(slot, 'deepquarry.dmb');
  const rsc = path.join(slot, 'deepquarry.rsc');
  fs.writeFileSync(dmb, 'd');
  fs.writeFileSync(rsc, 'rs');
  fs.writeFileSync(path.join(slot, 'slot-complete'), native.pairId);
  return { ...fields(), kind: 'acquired_pair', slot, dmb, rsc };
}
test('machine pair identity uses exact strings and authenticates requested output project', () => {
  const report = { ...fields(), kind: 'native_pair', output_project: native.outputProject };
  expect(parseCompileResult(report, native.compiler, 'project.dme')).toEqual(native);
  expect(() => parseCompileResult({ ...report, pair_id: 1 }, native.compiler, 'project.dme')).toThrow('hex');
  expect(() => parseCompileResult({ ...report, output_project: path.resolve('other.dme') }, native.compiler, 'project.dme')).toThrow('another output project');
});
test('acquisition rejects generation changes, escaped paths and shared writable inodes', () => {
  const root = createNativeRequestDirectory('pair-check');
  try {
    const report = acquired(root);
    expect(parseAcquiredResult(report, native, root).pairId).toBe(native.pairId);
    expect(() => parseAcquiredResult({ ...report, rsc_hash: '0'.repeat(32) }, native, root)).toThrow('generation differs');
    expect(() => parseAcquiredResult({ ...report, slot: path.dirname(root) }, native, root)).toThrow('escaped');
    fs.linkSync(report.rsc, path.join(root, 'shared.rsc'));
    expect(() => parseAcquiredResult(report, native, root)).toThrow('independent copies');
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
test('acquired copies remain owned through child lifetime and cleanup on failure', async () => {
  let acquiredRoot = '';
  let runFile = '';
  let entered!: () => void;
  let exited!: () => void;
  const started = new Promise<void>(resolve => { entered = resolve; });
  const childExit = new Promise<void>(resolve => { exited = resolve; });
  const running = withCompiledOutput(native, async (_exe, args) => {
    expect(args[0]).toBe('acquire');
    expect(args[args.indexOf('--pair-id') + 1]).toBe(native.pairId);
    acquiredRoot = args[args.indexOf('--slots') + 1];
    fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify(acquired(acquiredRoot)));
    return { code: 0, combined: '' };
  }, async dmb => {
    runFile = dmb;
    entered();
    await childExit;
    expect(fs.existsSync(runFile)).toBe(true);
    throw new Error('hosted child failed after exiting');
  });
  const outcome = running.catch(error => error);
  await started;
  expect(fs.existsSync(runFile)).toBe(true);
  exited();
  const error = await outcome;
  expect(error).toBeInstanceOf(Error);
  expect(error.message).toContain('hosted child failed');
  expect(fs.existsSync(acquiredRoot)).toBe(false);
});
test('failed acquisition cannot invoke child or conventional fallback; BYOND stays conventional', async () => {
  let calls = 0;
  await expect(withCompiledOutput(native, async () => ({ code: 1, combined: 'missing generation' }), async () => { calls++; })).rejects.toThrow('Cannot host');
  expect(calls).toBe(0);
  const conventional = conventionalOutput('project.dme');
  await withCompiledOutput(conventional, async () => { throw new Error('must not acquire'); }, async file => { expect(file).toBe(path.resolve('project.dmb')); calls++; });
  expect(calls).toBe(1);
});
test('parallel hosted children acquire the same generation with distinct writable copies', async () => {
  const identities: string[] = [];
  const execute = async (_exe: string, args: string[]) => {
    expect(args[args.indexOf('--pair-id') + 1]).toBe(native.pairId);
    const root = args[args.indexOf('--slots') + 1];
    fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify(acquired(root)));
    return { code: 0, combined: '' };
  };
  await Promise.all([1, 2].map(() => withCompiledOutput(native, execute, async file => {
    const stat = fs.statSync(file);
    identities.push(`${stat.dev}:${stat.ino}`);
    const handle = fs.openSync(file, 'r+');
    fs.closeSync(handle);
  })));
  expect(new Set(identities).size).toBe(2);
});
test('cleanup failure preserves typed child cancellation and its evidence', async () => {
  let root = '';
  const cancellation = Object.assign(new Error('hosted child cancelled'), { code: 75 });
  try {
    const failure = await withCompiledOutput(native, async (_exe, args) => {
      root = args[args.indexOf('--slots') + 1];
      fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify(acquired(root)));
      return { code: 0, combined: '' };
    }, async file => {
      // Portable cleanup failure: an expected removable file is a directory.
      fs.mkdirSync(path.join(path.dirname(file), 'deepquarry.dyn.rsc'));
      throw cancellation;
    }).then(() => null, error => error);
    expect(failure).toBe(cancellation);
    expect(failure.code).toBe(75);
    expect(fs.existsSync(path.join(root, 'slot-mock', 'deepquarry.dyn.rsc'))).toBe(true);
  } finally { if (root) fs.rmSync(root, { recursive: true, force: true }); }
});

test('cleanup failure after a successful child remains an acquisition error', async () => {
  let root = '';
  try {
    await expect(withCompiledOutput(native, async (_exe, args) => {
      root = args[args.indexOf('--slots') + 1];
      fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify(acquired(root)));
      return { code: 0, combined: '' };
    }, async file => {
      fs.mkdirSync(path.join(path.dirname(file), 'deepquarry.dyn.rsc'));
    })).rejects.toThrow('Native owned run cleanup failed');
  } finally { if (root) fs.rmSync(root, { recursive: true, force: true }); }
});

test('cleanup removes bulky copies while preserving runtime diagnostic leaves', async () => {
  let root = '';
  let log = '';
  await withCompiledOutput(native, async (_exe, args) => {
    root = args[args.indexOf('--slots') + 1];
    fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify(acquired(root)));
    return { code: 0, combined: '' };
  }, async file => {
    log = file.replace(/\.dmb$/, '.log');
    fs.writeFileSync(log, 'existing debug evidence');
  });
  try {
    expect(fs.readFileSync(log, 'utf8')).toBe('existing debug evidence');
    expect(fs.existsSync(log.replace(/\.log$/, '.dmb'))).toBe(false);
    expect(fs.existsSync(log.replace(/\.log$/, '.rsc'))).toBe(false);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

for (const fails of [false, true]) {
  test(`hosted mutable RSC and staged library preserve compiled inputs on ${fails ? 'failure' : 'success'}`, async () => {
    const inputs = createNativeRequestDirectory('immutable-runtime-inputs');
    const compiledRsc = path.join(inputs, 'compiled.rsc');
    const sourceLibrary = path.join(inputs, 'verdigris.dll');
    fs.writeFileSync(compiledRsc, 'rs');
    fs.writeFileSync(sourceLibrary, 'current exact DLL');
    let hostedRoot = '';
    let hostedRsc = '';
    let hostedLibrary = '';
    const childFailure = new Error('simulated reaped child failure');
    try {
      const outcome = await withCompiledOutput(native, async (_exe, args) => {
        hostedRoot = args[args.indexOf('--slots') + 1];
        const report = acquired(hostedRoot);
        // The real Rust acquire producer uses authenticated independent copies.
        fs.copyFileSync(compiledRsc, report.rsc);
        fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify(report));
        return { code: 0, combined: '' };
      }, async dmb => {
        hostedRsc = dmb.replace(/\.dmb$/, '.rsc');
        const staged = stageRuntimeLibrary(sourceLibrary, path.dirname(dmb));
        hostedLibrary = staged.identity.hosted;
        try {
          fs.writeFileSync(hostedRsc, 'DD rewrote its writable resource archive');
          expect(fs.readFileSync(compiledRsc, 'utf8')).toBe('rs');
          expect(fs.readFileSync(hostedLibrary, 'utf8')).toBe('current exact DLL');
          expect(fs.statSync(hostedRsc).nlink).toBe(1);
          if (fails) throw childFailure;
          return 'completed';
        } finally { staged.remove(); }
      }).then(value => value, error => error);
      expect(outcome).toBe(fails ? childFailure : 'completed');
      expect(fs.readFileSync(compiledRsc, 'utf8')).toBe('rs');
      expect(fs.readFileSync(sourceLibrary, 'utf8')).toBe('current exact DLL');
      expect(fs.existsSync(hostedRsc)).toBe(false);
      expect(fs.existsSync(hostedLibrary)).toBe(false);
      expect(fs.existsSync(hostedRoot)).toBe(false);
    } finally { fs.rmSync(inputs, { recursive: true, force: true }); }
  });
}
