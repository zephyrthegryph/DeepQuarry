import { expect, test } from 'bun:test';
import { parseResourceJournalAdmission } from './resource_journal_admission';

test('core resource coverage retains native-only scope and immutable counts', () => {
  const counts = { candidate_reads: 7, source_payload_bytes: 100, resource_aliases: 2 };
  const result = parseResourceJournalAdmission({ schema_version: 1, physical_observed_demand_admitted: true,
    shared_input_closure_complete: false, coverage: counts, decline_reason: null });
  counts.candidate_reads = 900;
  expect(result?.coverage?.candidate_reads).toBe(7);
  expect(result?.shared_input_closure_complete).toBe(false);
  expect(Object.isFrozen(result)).toBe(true);
  expect(Object.isFrozen(result?.coverage)).toBe(true);
  expect(parseResourceJournalAdmission(undefined)).toBeUndefined();
});

test('declined core coverage requires its reason and rejects admission contradictions', () => {
  const declined = { schema_version: 1, physical_observed_demand_admitted: false,
    shared_input_closure_complete: false, coverage: null, decline_reason: 'provider has no recorded journal authority' };
  expect(parseResourceJournalAdmission(declined)?.decline_reason).toBe(declined.decline_reason);
  for (const mutation of [{ shared_input_closure_complete: true }, { decline_reason: null },
    { coverage: {} }, { schema_version: 2 }, { physical_observed_demand_admitted: true }]) {
    expect(() => parseResourceJournalAdmission({ ...declined, ...mutation })).toThrow();
  }
  for (const value of [-1, Number.MAX_SAFE_INTEGER + 1, 0.5, '5', null]) {
    expect(() => parseResourceJournalAdmission({ ...declined, physical_observed_demand_admitted: true,
      decline_reason: null, coverage: { candidate_reads: value, source_payload_bytes: 0, resource_aliases: 0 } })).toThrow();
  }
});
