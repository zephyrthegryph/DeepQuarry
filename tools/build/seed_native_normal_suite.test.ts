import { expect, test } from 'bun:test';
import { seedArguments } from './seed_native_normal_suite';

test('native seed CLI requires separate evidence and acquisition pins', () => {
  expect(seedArguments(['evidence', 'evidence-sha', 'acquisition', 'acquisition-sha', 'destination'])).toEqual({
    evidence: 'evidence', evidenceSha256: 'evidence-sha', acquisition: 'acquisition',
    acquisitionSha256: 'acquisition-sha', destination: 'destination',
  });
  expect(() => seedArguments(['evidence', 'sha', 'destination'])).toThrow();
  expect(() => seedArguments(['e', 'h', 'a', 'h', 'd', 'extra'])).toThrow();
});
