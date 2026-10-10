/** Admission for the shared RSC decoder's exact live filename/kind/payload comparison. */
export function classifyResourceReport(value: unknown, snapshot: string): { status: 'parity' | 'differences' | 'incomplete' | 'invalid_report'; reason: string } {
  const invalid = { status: 'invalid_report' as const, reason: 'invalid resource comparison report' };
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return invalid;
  const report = value as Record<string, unknown>;
  if (report.schema_version !== 1 || report.snapshot_id !== snapshot || typeof report.complete !== 'boolean') return invalid;
  for (const field of ['expected_resources', 'actual_resources', 'differences', 'unknown_wrappers']) {
    if (typeof report[field] !== 'number' || !Number.isSafeInteger(report[field]) || (report[field] as number) < 0) return invalid;
  }
  if (!Array.isArray(report.examples) || report.examples.length > 20 || !report.examples.every(row => typeof row === 'string')) return invalid;
  if (report.complete !== (report.unknown_wrappers === 0)) return invalid;
  if (!report.complete) return { status: 'incomplete', reason: 'unknown archive wrappers prevent complete live-resource coverage' };
  if (report.differences !== 0) return { status: 'differences', reason: `${report.differences} filename/kind/payload resource differences` };
  if (report.expected_resources !== report.actual_resources) return invalid;
  return { status: 'parity', reason: 'exact live filename/kind/payload equality independent of archive ordering' };
}
