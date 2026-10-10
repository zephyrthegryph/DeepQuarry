import { exactNormalUnion, bindNormalPlan, sameSuiteRuntime, type IssuedNormalInventory, type RuntimeIdentity, type BatchRows } from './normal_suite_plan';
import type { UnitTestEntry } from './bench';

export type ComparableNormalSuite = {
  inventory: IssuedNormalInventory;
  runtime: RuntimeIdentity;
  batches: BatchRows<UnitTestEntry>[];
};

/** Result comparison only. Callers must independently authenticate source and compiler inputs.
 * Descriptions remain in the original rows; signatures exclude volatile object references
 * inside descriptions, timings and tick statistics.
 */
export function compareNormalSuiteResults(reference: ComparableNormalSuite, native: ComparableNormalSuite) {
  bindNormalPlan(reference.inventory, native.inventory);
  if (!sameSuiteRuntime(reference.runtime, native.runtime)) throw new Error('suite runtime inputs differ');
  const left = exactNormalUnion(reference.inventory, reference.batches);
  const right = exactNormalUnion(native.inventory, native.batches);
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
      errors: row.runtime_errors.map(error => ({ name: error.name, file: error.file, line: error.line })) });
  };
  const differences = reference.inventory.eligible.flatMap(name => {
    const baseline = left.tests[name], translated = right.tests[name];
    return signature(baseline) === signature(translated) ? [] : [{ name, reference: baseline, native: translated }];
  });
  if (left.frameworkFindings.length !== right.frameworkFindings.length) throw new Error('framework batch coverage differs');
  const frameworkDifferences = left.frameworkFindings.flatMap((baseline, index) => {
    const translated = right.frameworkFindings[index];
    return signature(baseline) === signature(translated) ? [] : [{ index, reference: baseline, native: translated }];
  });
  return { matches: differences.length === 0 && frameworkDifferences.length === 0, differences, frameworkDifferences,
    referenceFramework: left.frameworkFindings, nativeFramework: right.frameworkFindings };
}
