/** Issue an immutable continuation only after the owning runtime guardian exited.
 * Usage: bun tools/build/checkpoint_normal_suite.ts PRIOR PRIOR_SHA EVIDENCE EVIDENCE_SHA BATCH_SIZE DESTINATION
 * SHA pins must come from the stopped run's final files. This does not certify
 * process cleanup, current source closure, or passing test results. */
import { issueNormalContinuation } from './lib/normal_suite_resume';

export function checkpointArguments(args: string[]) {
  if (args.length !== 6 || !/^[1-9][0-9]*$/.test(args[4])) {
    throw new Error('Expected PRIOR PRIOR_SHA EVIDENCE EVIDENCE_SHA BATCH_SIZE DESTINATION');
  }
  const batchSize = Number(args[4]);
  if (!Number.isSafeInteger(batchSize)) throw new Error('Batch size must be a positive safe integer');
  return { prior: args[0], priorSha256: args[1], evidence: args[2], evidenceSha256: args[3], batchSize, destination: args[5] };
}

if (import.meta.main) {
  try {
    const args = checkpointArguments(process.argv.slice(2));
    console.log(JSON.stringify(issueNormalContinuation(args.prior, args.priorSha256,
      args.evidence, args.evidenceSha256, args.batchSize, args.destination)));
  } catch (error) {
    console.error(String(error)); process.exitCode = 1;
  }
}
