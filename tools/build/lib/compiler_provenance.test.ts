import { expect, test } from 'bun:test';
import { beginCompilerReceipt, byondProvenance, nativeProvenance } from './compiler_provenance';
import fs from 'node:fs';
import path from 'node:path';

function receiptDirectory() {
  const root = 'E:/dq-cache/build-provenance-tests';
  fs.mkdirSync(root, { recursive: true });
  return fs.mkdtempSync(path.join(root, 'compiler-receipt-'));
}
import { testRunRecord } from './bench';

test('record retains actual fallback compiler and complete ordered defines', () => {
  const defines = ['CBT', 'CIBUILDING', 'CITESTING', 'DEBUG', 'VALUE=1', 'VALUE=2'];
  const compilation = byondProvenance('native', defines, { invocation: {
    command: ['pinned-dm', '-DVALUE=2', 'project.dme'], version: 516, build: 1687,
    compilerIdentity: { status: 'observed', executable: 'pinned-dm', sha256: 'a'.repeat(64) },
  } }, 'internal_error_70');
  const record = testRunRecord({ id: 'fixture', timestamp: '', commit: '', branch: '', dirty_files: 0, host: '', platform: '' },
    'native-request', ['VALUE=2'], true, 1, { probe: { status: 0, name: 'probe' } }, compilation);
  expect(record.defines).toEqual(defines);
  expect(record.compilation?.requestedBackend).toBe('native');
  expect(record.compilation?.actualBackend).toBe('byond');
  expect(record.compilation?.fallback).toBe('internal_error_70');
  expect(record.compilation?.compiler).toEqual({ executable: 'pinned-dm', sha256: 'a'.repeat(64), version: 516, build: 1687 });
  expect(record.compilation?.nativePair).toBeNull();
});

test('native pair identity is recorded without fabricating executable version', () => {
  const output = { kind: 'native_pair' as const, compiler: 'native', store: 'store', outputProject: 'project',
    pairId: '1'.repeat(32), dmbHash: '2'.repeat(32), rscHash: '3'.repeat(32), dmbBytes: 4, rscBytes: 5 };
  const receipt = nativeProvenance(output, ['DEBUG', 'DEBUG=0'], { executable: 'native', sha256: 'b'.repeat(64) });
  expect(receipt.nativePair).toEqual({ pairId: output.pairId, dmbHash: output.dmbHash, rscHash: output.rscHash, dmbBytes: 4, rscBytes: 5 });
  expect(receipt.orderedDefines).toEqual(['DEBUG', 'DEBUG=0']);
  expect(receipt.compiler.version).toBeNull();
  expect(receipt.compiler.build).toBeNull();
  expect(byondProvenance('byond', [], undefined).compiler.sha256).toBeNull();
});

test('attempt identity persists before boot and survives missing timed-out results', () => {
  const directory = receiptDirectory();
  try {
    const output = { kind: 'native_pair' as const, compiler: 'native', store: 'store', outputProject: 'project',
      pairId: '1'.repeat(32), dmbHash: '2'.repeat(32), rscHash: '3'.repeat(32), dmbBytes: 4, rscBytes: 5 };
    const compilation = nativeProvenance(output, ['DEBUG'], { executable: 'native', sha256: 'b'.repeat(64) });
    const receipt = beginCompilerReceipt(directory, { ...output, provenance: compilation });
    const read = () => JSON.parse(fs.readFileSync(receipt.file, 'utf8'));
    expect(read().actual_backend).toBe('native');
    expect(read().prepared_at).toBeNull();
    receipt.prepared(path.join(directory, 'acquired.dmb'));
    expect(read().prepared_at).not.toBeNull();
    receipt.finalize({ resultsAvailable: false, killedByWatchdog: true, error: null });
    expect(read().runtime).toEqual({ resultsAvailable: false, killedByWatchdog: true, error: null });
    expect(read().compilation.nativePair).toEqual(compilation.nativePair);
    expect(fs.readdirSync(directory)).toEqual([path.basename(receipt.file)]);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('fallback receipt never counts as native and rejects contradictory pair authority', () => {
  const directory = receiptDirectory();
  try {
    const compilation = byondProvenance('native', ['DEBUG'], undefined, 'internal_error_70');
    const output = { kind: 'conventional' as const, backend: 'byond' as const,
      dmb: path.join(directory, 'world.dmb'), rsc: path.join(directory, 'world.rsc'), provenance: compilation };
    const receipt = beginCompilerReceipt(directory, output);
    expect(JSON.parse(fs.readFileSync(receipt.file, 'utf8')).actual_backend).toBe('byond');
    expect(() => beginCompilerReceipt(directory, { ...output,
      provenance: { ...compilation, actualBackend: 'native' } })).toThrow();
    const pair = { kind: 'native_pair' as const, compiler: 'native', store: 'store', outputProject: 'project',
      pairId: '1'.repeat(32), dmbHash: '2'.repeat(32), rscHash: '3'.repeat(32), dmbBytes: 4, rscBytes: 5 };
    const provenance = nativeProvenance(pair, [], { executable: 'native', sha256: null });
    expect(() => beginCompilerReceipt(directory, { ...pair, provenance: {
      ...provenance, nativePair: { ...provenance.nativePair!, dmbBytes: 9 },
    } })).toThrow();
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
