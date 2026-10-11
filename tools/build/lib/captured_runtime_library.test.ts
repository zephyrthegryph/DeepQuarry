import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { verifyCapturedRuntimeLibrary } from './captured_runtime_library';

test('captured library requires complete current source/build/pair-independent ABI evidence', () => {
  fs.mkdirSync('E:/dq-cache', { recursive: true });
  const root = fs.mkdtempSync('E:/dq-cache/captured-library-test-');
  const pin = (file: string) => ({ path: file, bytes: fs.statSync(file).size,
    sha256: createHash('sha256').update(fs.readFileSync(file)).digest('hex') });
  const write = (name: string, value: string) => {
    const file = path.join(root, name); fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, value); return pin(file);
  };
  try {
    const sourceRoot = path.join(root, 'source'), target = path.join(root, 'target');
    const bindings = write('source/code/__defines/verdigris/_bindings.dm', '#define VERDIGRIS_ABI "abcd"\n');
    const rustAbi = write('source/verdigris/ffi/src/abi.rs', 'pub const ABI: &str = "abcd";');
    const files = { 'code/__defines/verdigris/_bindings.dm': bindings.sha256, 'verdigris/ffi/src/abi.rs': rustAbi.sha256 };
    const snapshot = write('snapshot.json', JSON.stringify({ files }));
    const closure = write('closure.json', JSON.stringify(Object.entries(files).map(([file, sha256]) => ({ tree: 'source', path: file, sha256 }))));
    const configuration = write('configuration.json', JSON.stringify(['byond', 'native'].map(producer => ({ producer, cwd: sourceRoot }))));
    const version = write('version.json', '{}');
    const sourcePin = write('source-pin.json', JSON.stringify({ snapshot_id: snapshot.sha256,
      source_closure_manifest_sha256: closure.sha256, configuration_evidence: [configuration], byond_version_evidence: version }));
    const cargo = write('cargo.exe', 'mock explicit tool');
    const library = write('target/i686-pc-windows-msvc/release/verdigris.dll', 'mock DLL abcd');
    const receipt: any = { schema: 'captured-verdigris-build-v1', exit: 0, timeout: false,
      owned_job_cleanup: { reaped: true }, workers: 1, snapshot, closure, cargo, bindings, rustAbi,
      child_watchdog_seconds: 300, job_memory_bytes: 4_000_000_000,
      sourceSnapshotSha256: snapshot.sha256, sourceClosureSha256: closure.sha256,
      inputsBefore: files, inputsAfter: files, library, abi: 'abcd', sourceRoot,
      cwd: path.join(sourceRoot, 'verdigris'), targetDirectory: target,
      command: [cargo.path, 'build', '--locked', '-j1', '--release', '--target', 'i686-pc-windows-msvc', '--package', 'verdigris', '--lib'] };
    const receiptFile = path.join(root, 'build.json');
    const proof = () => {
      fs.writeFileSync(receiptFile, JSON.stringify(receipt));
      return { buildReceipt: pin(receiptFile), sourcePin, library, pair: { dmb: library, rsc: library } };
    };
    expect(verifyCapturedRuntimeLibrary(proof())).toBe(library.path);
    receipt.inputsAfter = {};
    expect(() => verifyCapturedRuntimeLibrary(proof())).toThrow();
    receipt.inputsAfter = files; receipt.abi = 'beef';
    expect(() => verifyCapturedRuntimeLibrary(proof())).toThrow();
    receipt.abi = 'abcd'; receipt.command[3] = '-j2';
    expect(() => verifyCapturedRuntimeLibrary(proof())).toThrow();
    receipt.command[3] = '-j1'; receipt.inputsBefore = {}; receipt.inputsAfter = {};
    expect(() => verifyCapturedRuntimeLibrary(proof())).toThrow();
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
