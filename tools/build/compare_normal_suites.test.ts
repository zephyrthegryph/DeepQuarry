import { expect, test } from 'bun:test';
import fs from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { compareEvidence } from './compare_normal_suites';

// Synthetic receipts test the admission contract, not compiler/runtime parity.
const name = '/datum/unit_test/example';
const row = { name, status: 0, runtimes: 0, runtime_errors: [] as {
  name: string | null; file: string | null; line: number | null; description: string | null;
}[], runtime_errors_truncated: false };
const runtime = { executable: 'E:/fake/dd.exe', sha256: 'a'.repeat(64), version: null, security: '-trusted' };
const sha = (bytes: string) => createHash('sha256').update(bytes).digest('hex');
function suite(backend: 'byond' | 'native', planHash: string | null) {
  const compilation = { requestedBackend: backend, actualBackend: backend,
    fallback: null as string | null, orderedDefines: ['UNIT_TESTS'],
    compiler: { executable: 'E:/fake/compiler.exe', sha256: 'b'.repeat(64),
      version: backend === 'byond' ? 516 : null, build: backend === 'byond' ? 1687 : null },
    nativePair: backend === 'native' ? { pairId: '1'.repeat(32), dmbHash: '2'.repeat(32),
      rscHash: '3'.repeat(32), dmbBytes: 1, rscBytes: 0 } : null };
  const run = () => ({ compilation, runtimeIdentity: runtime, clean: true, killedByWatchdog: false,
    results: { [name]: structuredClone(row) } });
  return { schema: 1, status: 'passed', batchSize: 1, compilation,
    inventory: { ...run(), inventory: { schema: 1, tier: 'normal', eligible: [name], excluded: [], automaticRows: [] } },
    plan: { sha256: planHash, eligibleOrder: [name], observedOrderDiffers: false },
    batches: [{ requested: [name], run: run() }] };
}
function fixture(check: (value: {
  native: ReturnType<typeof suite>; compare: () => ReturnType<typeof compareEvidence>;
  referenceFile: string; referenceHash: string; nativeFile: string; write: () => string;
}) => void) {
  const directory = `E:/dq-cache/dmb-native-v2/normal-suite-compare-test-${randomUUID()}`;
  fs.mkdirSync(directory, { recursive: true });
  try {
    const referenceFile = `${directory}/byond.json`, nativeFile = `${directory}/native.json`;
    const referenceBytes = JSON.stringify(suite('byond', null));
    fs.writeFileSync(referenceFile, referenceBytes, { flag: 'wx' });
    const referenceHash = sha(referenceBytes), native = suite('native', referenceHash);
    const write = () => { const bytes = JSON.stringify(native); fs.writeFileSync(nativeFile, bytes); return sha(bytes); };
    check({ native, referenceFile, referenceHash, nativeFile, write,
      compare: () => compareEvidence(referenceFile, referenceHash, nativeFile, write()) });
  } finally {
    // Exact freshly-created owned directory; no compiler, daemon or foreign files.
    fs.rmSync(directory, { recursive: true });
  }
}

test('authenticated synthetic matching receipts remain preliminary', () => fixture(({ compare }) => {
  const result = compare();
  expect(result.matches).toBe(true);
  expect(result.inputClosureAuthenticated).toBe(false);
  expect(result.acceptedRuntimeBaseline).toBe(false);
}));
test('preserves runtime differences even when status passes', () => fixture(({ native, compare }) => {
  native.batches[0].run.results[name].runtimes = 1;
  native.batches[0].run.results[name].runtime_errors.push({ name: 'error', file: 'probe.dm', line: 2, description: 'owned test runtime' });
  const result = compare();
  expect(result.matches).toBe(false);
  expect(result.differences[0].native.runtimes).toBe(1);
  expect(result.differences[0].native.runtime_errors?.[0].description).toBe('owned test runtime');
}));
test('rejects fallback rather than counting it as native', () => fixture(({ native, compare }) => {
  native.compilation.fallback = 'internal_error_70';
  expect(compare).toThrow('fallback present');
}));
test('requires actual receipt hash and authenticated prior plan', () => fixture(({ native, compare, referenceFile, referenceHash, nativeFile, write }) => {
  const nativeHash = write();
  expect(() => compareEvidence(referenceFile, '0'.repeat(64), nativeFile, nativeHash)).toThrow('SHA256 mismatch');
  expect(() => compareEvidence(referenceFile, referenceHash, nativeFile, '0'.repeat(64))).toThrow('SHA256 mismatch');
  native.plan.sha256 = '0'.repeat(64);
  expect(compare).toThrow('same reference plan');
}));
test('rejects truncated and missing structured runtime evidence', () => fixture(({ native, compare }) => {
  native.batches[0].run.results[name].runtime_errors_truncated = true;
  expect(compare).toThrow('truncated');
  native.batches[0].run.results[name].runtime_errors_truncated = false;
  delete (native.batches[0].run.results[name] as Partial<typeof row>).runtime_errors;
  expect(compare).toThrow('structured runtime evidence');
}));
