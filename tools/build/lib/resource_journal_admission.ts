/** Transport validation of the Rust core's observed-demand receipt only.
 * This does not issue filesystem authority or prove DreamMaker read coverage.
 */
export type ResourceJournalAdmission = Readonly<{
  schema_version: 1;
  physical_observed_demand_admitted: boolean;
  shared_input_closure_complete: false;
  coverage: Readonly<{ candidate_reads: number; source_payload_bytes: number; resource_aliases: number }> | null;
  decline_reason: string | null;
}>;

export function parseResourceJournalAdmission(value: unknown): ResourceJournalAdmission | undefined {
  if (value === undefined) return undefined;
  const fail = (): never => { throw new Error('Invalid native resource journal admission receipt.'); };
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail();
  const receipt = value as Record<string, unknown>;
  if (receipt.schema_version !== 1 || typeof receipt.physical_observed_demand_admitted !== 'boolean'
    || receipt.shared_input_closure_complete !== false) return fail();
  let coverage: ResourceJournalAdmission['coverage'] = null;
  if (receipt.physical_observed_demand_admitted) {
    if (!receipt.coverage || typeof receipt.coverage !== 'object' || Array.isArray(receipt.coverage)
      || receipt.decline_reason !== null) return fail();
    const counts = receipt.coverage as Record<string, unknown>;
    for (const field of ['candidate_reads', 'source_payload_bytes', 'resource_aliases']) {
      if (typeof counts[field] !== 'number' || !Number.isSafeInteger(counts[field]) || (counts[field] as number) < 0) return fail();
    }
    coverage = Object.freeze({ candidate_reads: counts.candidate_reads as number,
      source_payload_bytes: counts.source_payload_bytes as number, resource_aliases: counts.resource_aliases as number });
  } else if (receipt.coverage !== null || typeof receipt.decline_reason !== 'string' || !receipt.decline_reason.trim()) return fail();
  return Object.freeze({ schema_version: 1, physical_observed_demand_admitted: receipt.physical_observed_demand_admitted,
    shared_input_closure_complete: false, coverage, decline_reason: receipt.decline_reason as string | null });
}
