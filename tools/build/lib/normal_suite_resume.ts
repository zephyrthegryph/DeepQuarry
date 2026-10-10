/** Historical same-generation continuation. This never authenticates current source closure. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import type { CompilerProvenance } from './compiler_provenance';
import { assertDirectoryChain, type CompiledOutput } from './native_pair';
import { exactNormalUnion, normalSuiteBatches, sameSuiteRuntime, suiteRowSucceeded, type IssuedNormalInventory, type RuntimeIdentity } from './normal_suite_plan';

export type ResumeRun = { compilation: CompilerProvenance | null; results: Record<string, { status: number; runtimes?: number }> | null;
  killedByWatchdog: boolean; clean: boolean; runtimeIdentity?: RuntimeIdentity };
export type ResumeEvidence<R extends ResumeRun> = { batchSize: number; compilation: CompilerProvenance | null;
  inventory?: R & { inventory?: IssuedNormalInventory }; plan?: { eligibleOrder: string[] };
  batches: { requested: string[]; run: R }[] };
export type NormalResumeCheckpoint = { schema: 1; kind: 'historical_normal_suite_resume'; inputClosureAuthenticated: false;
  evidence: { path: string; sha256: string }; pair: { dmb: string; rsc: string; dmbSha256: string; rscSha256: string; dmbBytes: number; rscBytes: number };
  compilation: CompilerProvenance; runtimeIdentity: RuntimeIdentity };
const HEX = /^[0-9a-f]{64}$/;
function regular(file: string): void {
  if (!path.isAbsolute(file)) throw new Error('resume paths must be absolute');
  assertDirectoryChain(path.dirname(file));
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('resume requires regular files');
}
function hashFile(file: string): string {
  regular(file);
  const descriptor = fs.openSync(file, 'r');
  try { const hash = createHash('sha256'); const buffer = Buffer.allocUnsafe(1024 * 1024);
    for (;;) { const length = fs.readSync(descriptor, buffer, 0, buffer.length, null); if (!length) break; hash.update(buffer.subarray(0, length)); }
    return hash.digest('hex');
  } finally { fs.closeSync(descriptor); }
}
function authenticatedJson(file: string, sha256: string): unknown {
  regular(file);
  if (!HEX.test(sha256) || fs.statSync(file).size > 32 * 1024 * 1024) throw new Error('resume JSON hash/size invalid');
  const bytes = fs.readFileSync(file);
  if (createHash('sha256').update(bytes).digest('hex') !== sha256) throw new Error('resume JSON identity differs');
  return JSON.parse(bytes.toString('utf8'));
}
export function validateCompletedPrefix<R extends ResumeRun>(evidence: ResumeEvidence<R>, checkpoint: NormalResumeCheckpoint, batchSize: number) {
  if (evidence.batchSize !== batchSize || JSON.stringify(evidence.compilation) !== JSON.stringify(checkpoint.compilation)) throw new Error('resume compilation/configuration differs');
  const issued = evidence.inventory;
  if (!issued?.inventory || !issued.clean || issued.killedByWatchdog || !sameSuiteRuntime(issued.runtimeIdentity, checkpoint.runtimeIdentity)) throw new Error('resume inventory/runtime unavailable');
  const plan = { ...issued.inventory, eligible: evidence.plan?.eligibleOrder ?? issued.inventory.eligible };
  normalSuiteBatches(plan, batchSize);
  if (plan.eligible.length !== issued.inventory.eligible.length || plan.eligible.some(name => !issued.inventory!.eligible.includes(name))) throw new Error('resume plan differs from issued inventory');
  const batches = normalSuiteBatches(plan, batchSize);
  if (!Array.isArray(evidence.batches) || evidence.batches.length > batches.length) throw new Error('resume prefix invalid');
  evidence.batches.forEach((batch, index) => {
    if (JSON.stringify(batch.requested) !== JSON.stringify(batches[index]) || !sameSuiteRuntime(batch.run.runtimeIdentity, checkpoint.runtimeIdentity)
      || JSON.stringify(batch.run.compilation) !== JSON.stringify(checkpoint.compilation) || batch.run.killedByWatchdog || !batch.run.results) throw new Error('resume batch identity/completion invalid');
    exactNormalUnion({ ...plan, eligible: batch.requested, excluded: [] }, [{ requested: batch.requested, results: batch.run.results }]);
    Object.values(batch.run.results).forEach(row => { suiteRowSucceeded(row); });
  });
  return { plan, batches, completed: evidence.batches };
}
export function loadNormalResume<R extends ResumeRun>(file: string, sha256: string, batchSize: number) {
  const checkpoint = authenticatedJson(file, sha256) as NormalResumeCheckpoint;
  if (checkpoint.schema !== 1 || checkpoint.kind !== 'historical_normal_suite_resume' || checkpoint.inputClosureAuthenticated !== false
    || checkpoint.compilation?.actualBackend !== 'byond' || !checkpoint.compilation.compiler.sha256 || !checkpoint.runtimeIdentity?.sha256) throw new Error('unsupported/unpinned historical checkpoint');
  for (const kind of ['dmb', 'rsc'] as const) {
    if (process.platform === 'win32' && !/^e:[\\/]/i.test(checkpoint.pair[kind])) throw new Error('resume copies must be owned E: files');
    const expected = checkpoint.pair[`${kind}Sha256`];
    const bytes = checkpoint.pair[`${kind}Bytes`];
    if (!HEX.test(expected) || !Number.isSafeInteger(bytes) || bytes < 0 || fs.statSync(checkpoint.pair[kind]).size !== bytes
      || hashFile(checkpoint.pair[kind]) !== expected) throw new Error('resume output pair identity differs');
  }
  const evidence = authenticatedJson(checkpoint.evidence.path, checkpoint.evidence.sha256) as ResumeEvidence<R>;
  const admitted = validateCompletedPrefix(evidence, checkpoint, batchSize);
  const output: CompiledOutput = { kind: 'conventional', backend: 'byond', dmb: checkpoint.pair.dmb, rsc: checkpoint.pair.rsc, provenance: checkpoint.compilation };
  return { ...admitted, output, inventory: evidence.inventory!, checkpoint, checkpointPath: path.resolve(file), checkpointSha256: sha256 };
}
