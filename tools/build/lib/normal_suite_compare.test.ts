import { expect, test } from 'bun:test';
import { compareNormalSuiteResults, type ComparableNormalSuite } from './normal_suite_compare';
const name = '/datum/unit_test/example';
const row = { name, status: 0, runtimes: 0, runtime_errors: [], runtime_errors_truncated: false };
const suite: ComparableNormalSuite = { inventory: { schema: 1, tier: 'normal', eligible: [name], automaticRows: [], excluded: [] },
  runtime: { executable: 'dd.exe', sha256: 'pinned', version: null, security: '-trusted' },
  batches: [{ requested: [name], results: { [name]: row } }] };
test('fewer runtimes is a behavioral difference even when both tests pass', () => {
  const baseline = { ...suite, batches: [{ requested: [name], results: { [name]: { ...row, runtimes: 1,
    runtime_errors: [{ name: 'list index out of bounds', file: 'power_bridge.dm', line: 154, description: 'stack' }] } } }] };
  const result = compareNormalSuiteResults(baseline, suite);
  expect(result.matches).toBe(false);
  expect(result.differences[0].reference.runtimes).toBe(1);
});
test('requires actual runtime evidence and preserves all original rows', () => {
  expect(compareNormalSuiteResults(suite, suite).matches).toBe(true);
  const numericFalse: ComparableNormalSuite = { ...suite, batches: [{ requested: [name], results: { [name]: { ...row, runtime_errors_truncated: 0 } } }] };
  expect(compareNormalSuiteResults(suite, numericFalse).matches).toBe(true);
  const truncated = { ...suite, batches: [{ requested: [name], results: { [name]: { ...row, runtime_errors_truncated: true } } }] };
  expect(() => compareNormalSuiteResults(suite, truncated)).toThrow('truncated');
  const missing = { ...suite, batches: [{ requested: [name], results: { [name]: { name, status: 0, runtimes: 0 } } }] };
  expect(() => compareNormalSuiteResults(suite, missing)).toThrow('structured');
});
test('framework failures cannot be hidden by identical test results', () => {
  const withFramework: ComparableNormalSuite = { ...suite, inventory: { ...suite.inventory, automaticRows: ['ownership_framework_checks'] },
    batches: [{ requested: [name], results: { [name]: row, ownership_framework_checks: { ...row, name: 'ownership_framework_checks' } } }] };
  const failed: ComparableNormalSuite = { ...withFramework, batches: [{ requested: [name], results: {
    [name]: row, ownership_framework_checks: { ...row, name: 'ownership_framework_checks', status: 1, message: 'orphaned owner' },
  } }] };
  const result = compareNormalSuiteResults(withFramework, failed);
  expect(result.matches).toBe(false);
  expect(result.differences).toHaveLength(0);
  expect(result.frameworkDifferences).toHaveLength(1);
});
