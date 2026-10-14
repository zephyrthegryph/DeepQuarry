import { expect, test } from 'bun:test';
import { classifyResourceReport } from './shadow_resources';
const report = { schema_version: 1, snapshot_id: 'fixture', complete: true, expected_resources: 2, actual_resources: 2, differences: 0, unknown_wrappers: 0, examples: [] };
test('resource admission requires exact complete matching context and payload report', () => {
  expect(classifyResourceReport(report, 'fixture').status).toBe('parity');
  expect(classifyResourceReport(report, 'other').status).toBe('invalid_report');
  expect(classifyResourceReport({ ...report, differences: 1, examples: ['payload: icon.dmi'] }, 'fixture').status).toBe('differences');
  expect(classifyResourceReport({ ...report, complete: false, unknown_wrappers: 1 }, 'fixture').status).toBe('incomplete');
  expect(classifyResourceReport({ ...report, complete: true, unknown_wrappers: 1 }, 'fixture').status).toBe('invalid_report');
  expect(classifyResourceReport({ ...report, actual_resources: 3 }, 'fixture').status).toBe('invalid_report');
});
