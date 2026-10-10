import { exactNormalUnion, bindNormalPlan, sameSuiteRuntime, suiteRowSucceeded, type IssuedNormalInventory, type RuntimeIdentity, type BatchRows } from './normal_suite_plan';
import type { UnitTestEntry } from './bench';

export type ComparableNormalSuite = {
  inventory: IssuedNormalInventory;
  runtime: RuntimeIdentity;
  batches: BatchRows<UnitTestEntry>[];
};

/** Result comparison only. Callers must independently authenticate source and compiler inputs.
 * Descriptions are compared exactly and remain in the original rows.
 * Timings and tick statistics are excluded from semantic comparison.
 */
export function compareNormalSuiteResults(reference: ComparableNormalSuite, native: ComparableNormalSuite) {
  bindNormalPlan(reference.inventory, native.inventory);
  if (!sameSuiteRuntime(reference.runtime, native.runtime)) throw new Error('suite runtime inputs differ');
  const left = exactNormalUnion(reference.inventory, reference.batches);
  const right = exactNormalUnion(native.inventory, native.batches);
  if (JSON.stringify(reference.batches.map(batch => batch.requested)) !== JSON.stringify(native.batches.map(batch => batch.requested))) {
    throw new Error('suite batch boundaries/order differ');
  }
  const signature = (row: UnitTestEntry) => {
    if (![0, 1, 2].includes(row.status) || !Number.isInteger(row.runtimes) || row.runtimes! < 0
        || !Array.isArray(row.runtime_errors) || ![false, true, 0, 1].includes(row.runtime_errors_truncated!)) {
      throw new Error('result lacks complete structured runtime evidence');
    }
    if (row.runtime_errors_truncated) throw new Error('runtime evidence was truncated');
    for (const error of row.runtime_errors) {
      if (!error || ![error.name, error.file, error.description].every(value => value === null || typeof value === 'string')
          || !(error.line === null || Number.isInteger(error.line))) throw new Error('malformed structured runtime error');
    }
    return JSON.stringify({ status: row.status, message: row.message ?? '', runtimes: row.runtimes,
      errors: row.runtime_errors.map(error => ({ name: error.name, file: error.file, line: error.line, description: error.description })) });
  };
  const differences = reference.inventory.eligible.flatMap(name => {
    const baseline = left.tests[name], translated = right.tests[name];
    return signature(baseline) === signature(translated) ? [] : [{ name, reference: baseline, native: translated }];
  });
  if (left.frameworkFindings.length !== right.frameworkFindings.length) throw new Error('framework batch coverage differs');
  const frameworkDifferences = reference.batches.flatMap((batch, batchIndex) => reference.inventory.automaticRows.flatMap(name => {
    const baseline = batch.results![name], translated = native.batches[batchIndex]?.results?.[name];
    if (!translated) throw new Error('framework batch coverage differs');
    return signature(baseline) === signature(translated) ? [] : [{ batchIndex, name, requested: batch.requested,
      reference: baseline, native: translated }];
  }));
  const counts = (rows: Record<string, UnitTestEntry>) => {
    const result = { passed: 0, failed: 0, skipped: 0 };
    for (const row of Object.values(rows)) {
      signature(row);
      if (row.status === 0) result.passed++;
      else if (row.status === 1) result.failed++;
      else result.skipped++;
    }
    return result;
  };
  const referenceSelectedCounts = counts(left.tests), nativeSelectedCounts = counts(right.tests);
  const allNonSkippedPassed = (tests: Record<string, UnitTestEntry>, framework: UnitTestEntry[]) =>
    [...Object.values(tests), ...framework].every(suiteRowSucceeded);
  const allPassed = (tests: Record<string, UnitTestEntry>, framework: UnitTestEntry[]) =>
    [...Object.values(tests), ...framework].every(row => row.status === 0 && suiteRowSucceeded(row));
  return { matches: differences.length === 0 && frameworkDifferences.length === 0, differences, frameworkDifferences,
    referenceSelectedCounts, nativeSelectedCounts,
    referenceAllNonSkippedTestsPassed: allNonSkippedPassed(left.tests, left.frameworkFindings),
    nativeAllNonSkippedTestsPassed: allNonSkippedPassed(right.tests, right.frameworkFindings),
    referenceAllTestsPassed: allPassed(left.tests, left.frameworkFindings),
    nativeAllTestsPassed: allPassed(right.tests, right.frameworkFindings),
    referenceFramework: left.frameworkFindings, nativeFramework: right.frameworkFindings };
}
