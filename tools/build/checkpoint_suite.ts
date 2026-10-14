/** Extend a stopped suite prefix through the same authenticated checkpoint core. */
import { checkpointArguments } from './checkpoint_normal_suite';
import { issueSuiteContinuation } from './lib/normal_suite_resume';
if (import.meta.main) {
  try {
    const args = checkpointArguments(process.argv.slice(2));
    console.log(JSON.stringify(issueSuiteContinuation(args.prior, args.priorSha256,
      args.evidence, args.evidenceSha256, args.batchSize, args.destination)));
  } catch (error) { console.error(String(error)); process.exitCode = 1; }
}
