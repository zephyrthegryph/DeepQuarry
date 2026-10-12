import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { withRuntimeIdentityChecks, removePrivateHostedLeaves, archiveHostedDaemonLog } from './byond';
import { CompilerProvenanceError } from './compiler_provenance';
import { NativeAcquisitionError } from './native_pair';
import { observeRuntimeLibrary, stageRuntimeLibrary, verifyObservedRuntimeLibrary } from './runtime_library';

function fixture() {
  const parent = path.resolve('E:/dq-cache/dmb-protocol-checks');
  fs.mkdirSync(parent, { recursive: true });
  const root = fs.mkdtempSync(path.join(parent, 'runtime-identity-'));
  const library = path.join(root, 'verdigris.dll');
  fs.writeFileSync(library, 'mock runtime library');
  return { root, library, remove() {
    const slot = path.join(root, 'slot');
    if (fs.existsSync(slot)) {
      fs.unlinkSync(path.join(slot, 'verdigris.dll'));
      fs.rmdirSync(slot);
    }
    fs.unlinkSync(library);
    fs.rmdirSync(root);
  } };
}
async function failure(run: () => Promise<unknown>): Promise<any> {
  try { await run(); } catch (error) { return error; }
  throw new Error('Expected runtime identity admission to fail');
}

test('pre-spawn rejection cleans partial owned pair and preserves typed primary failure', async () => {
  const files = fixture();
  const slot = path.join(files.root, 'partial'); fs.mkdirSync(slot);
  fs.writeFileSync(path.join(slot, 'world.dmb'), 'partial copy');
  const primary = new CompilerProvenanceError('prepared pair rejected before spawn');
  try {
    expect(await failure(() => withRuntimeIdentityChecks(async () => { throw primary; },
      () => removePrivateHostedLeaves(slot)))).toBe(primary);
    expect(fs.existsSync(slot)).toBe(false);
  } finally { files.remove(); }
});

test('failed archival preserves exact daemon log while releasing private pair leaves', () => {
  const files = fixture();
  const slot = path.join(files.root, 'log-slot'); fs.mkdirSync(slot);
  const log = path.join(slot, 'world.log'); fs.writeFileSync(log, 'actual mock evidence');
  fs.writeFileSync(path.join(slot, 'world.dmb'), 'private world');
  try {
    const preserved = archiveHostedDaemonLog(log, files.root); // Directory cannot be overwritten by a file.
    expect(preserved).toBe(log);
    removePrivateHostedLeaves(slot, preserved);
    expect(fs.readFileSync(log, 'utf8')).toBe('actual mock evidence');
    expect(fs.existsSync(path.join(slot, 'world.dmb'))).toBe(false);
  } finally { fs.unlinkSync(log); fs.rmdirSync(slot); files.remove(); }
});

test('private cleanup failure cannot mask typed pre-spawn provenance failure', async () => {
  const files = fixture();
  const missing = path.join(files.root, 'never-created');
  const primary = new CompilerProvenanceError('current pair proof rejected');
  try {
    const caught = await failure(() => withRuntimeIdentityChecks(async () => { throw primary; },
      () => removePrivateHostedLeaves(missing)));
    expect(caught).toBe(primary);
    expect(caught.runtimeIdentityCleanup.runtimeIdentityError).toBeDefined();
  } finally { files.remove(); }
});

test('passing world rows cannot admit a changed observed runtime library', async () => {
  const files = fixture();
  try {
    const identity = observeRuntimeLibrary(files.library);
    const caught = await failure(() => withRuntimeIdentityChecks(async () => {
      fs.writeFileSync(files.library, 'changed during mocked world');
      return { clean: true, results: { selected: { status: 'passed' } } };
    }, () => verifyObservedRuntimeLibrary(identity)));
    expect(caught).toBeInstanceOf(CompilerProvenanceError);
    expect(caught.runtimeIdentityCleanup.runtimeError).toBeNull();
    expect(String(caught.runtimeIdentityCleanup.runtimeIdentityError)).toContain('changed');
  } finally { files.remove(); }
});

test('expected nonzero world exit cannot hide identity failure and is retained as evidence', async () => {
  const files = fixture();
  const exit = new Error('mock DreamDaemon nonzero exit after results');
  try {
    const identity = observeRuntimeLibrary(files.library);
    const caught = await failure(() => withRuntimeIdentityChecks(async () => {
      fs.writeFileSync(files.library, 'changed during mocked world');
      throw exit;
    }, () => verifyObservedRuntimeLibrary(identity)));
    expect(caught).toBeInstanceOf(CompilerProvenanceError);
    expect(caught.runtimeIdentityCleanup.runtimeError).toBe(exit);
  } finally { files.remove(); }
});

test('changed native staged library rejects successful rows and preserves changed evidence', async () => {
  const files = fixture();
  try {
    const slot = path.join(files.root, 'slot');
    fs.mkdirSync(slot);
    const staged = stageRuntimeLibrary(files.library, slot);
    const caught = await failure(() => withRuntimeIdentityChecks(async () => {
      fs.writeFileSync(staged.identity.hosted, 'changed hosted library');
      return { clean: true };
    }, staged.remove));
    expect(caught).toBeInstanceOf(CompilerProvenanceError);
    expect(fs.readFileSync(staged.identity.hosted, 'utf8')).toBe('changed hosted library');
    expect(fs.readFileSync(files.library, 'utf8')).toBe('mock runtime library');
  } finally { files.remove(); }
});

test('already failclosed errors preserve identity with cleanup evidence', async () => {
  const primary = new NativeAcquisitionError('mock original acquisition failure');
  const cleanup = new Error('mock cleanup failure');
  const caught = await failure(() => withRuntimeIdentityChecks(async () => { throw primary; }, () => { throw cleanup; }));
  expect(caught).toBe(primary);
  expect(caught.runtimeIdentityCleanup.runtimeIdentityError).toBe(cleanup);
});

test('successful verification preserves ordinary result and original world failure', async () => {
  const result = { clean: true };
  expect(await withRuntimeIdentityChecks(async () => result, () => {})).toBe(result);
  const primary = new Error('mock ordinary world exit');
  let verified = 0;
  expect(await failure(() => withRuntimeIdentityChecks(async () => { throw primary; }, () => { verified++; }))).toBe(primary);
  expect(verified).toBe(1);
});
