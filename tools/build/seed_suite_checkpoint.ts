/** Stopped-run checkpoint only; never source closure or passing-test certification.
 * byond EVIDENCE SHA DMB RSC DESTINATION
 * native EVIDENCE SHA ACQUISITION ACQUISITION_SHA DESTINATION */
import { issueByondSuiteResume, issueNativeSuiteResume } from './lib/normal_suite_resume';

export function issueSuiteSeed(args: string[]) {
  if (args.length !== 6 || !['byond', 'native'].includes(args[0])) throw new Error('Expected BACKEND EVIDENCE SHA PAIR_OR_ACQUISITION PAIR_OR_SHA DESTINATION');
  return args[0] === 'byond' ? issueByondSuiteResume(args[1], args[2], args[3], args[4], args[5])
    : issueNativeSuiteResume(args[1], args[2], args[3], args[4], args[5]);
}
if (import.meta.main) {
  try { console.log(JSON.stringify(issueSuiteSeed(process.argv.slice(2)))); }
  catch (error) { console.error(String(error)); process.exitCode = 1; }
}
