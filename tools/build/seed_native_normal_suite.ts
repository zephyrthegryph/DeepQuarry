/** Seed only after the native runner and acquisition commands have fully reaped.
 * Usage: bun tools/build/seed_native_normal_suite.ts EVIDENCE EVIDENCE_SHA ACQUISITION ACQUISITION_SHA DESTINATION
 * This CLI does not certify cleanup, current source closure, or test success. */
import { issueNativeNormalResume } from './lib/normal_suite_resume';

export function seedArguments(args: string[]) {
  if (args.length !== 5) throw new Error('Expected EVIDENCE EVIDENCE_SHA ACQUISITION ACQUISITION_SHA DESTINATION');
  return { evidence: args[0], evidenceSha256: args[1], acquisition: args[2], acquisitionSha256: args[3], destination: args[4] };
}
if (import.meta.main) {
  try {
    const args = seedArguments(process.argv.slice(2));
    console.log(JSON.stringify(issueNativeNormalResume(args.evidence, args.evidenceSha256,
      args.acquisition, args.acquisitionSha256, args.destination)));
  } catch (error) { console.error(String(error)); process.exitCode = 1; }
}
