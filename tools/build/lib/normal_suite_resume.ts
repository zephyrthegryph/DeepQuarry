/** Historical same-generation continuation. This never authenticates current source closure. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import type { CompilerProvenance } from './compiler_provenance';
import { assertDirectoryChain, parseAcquiredResult, parseCompileResult, type NativePairOutput, type CompiledOutput } from './native_pair';
import { bindSuitePlan, exactSuiteUnion, suiteBatches, sameSuiteRuntime, suiteRowSucceeded, type IssuedSuiteInventory, type SuiteTier, type RuntimeIdentity } from './normal_suite_plan';

export type ResumeRun = { compilation: CompilerProvenance | null; results: Record<string, { status: number; runtimes?: number }> | null;
  killedByWatchdog: boolean; clean: boolean; runtimeIdentity?: RuntimeIdentity };
export type ResumeEvidence<R extends ResumeRun> = { batchSize: number; compilation: CompilerProvenance | null;
  selectionProtocol?: string;
  nativeOutput?: NativePairOutput; status?: string;
  inventory?: R & { inventory?: IssuedSuiteInventory }; plan?: { path?: string | null; sha256?: string | null; eligibleOrder: string[] };
  batches: { requested: string[]; run: R }[] };
export type NormalResumeCheckpoint = { schema: 1; kind: 'historical_normal_suite_resume'; inputClosureAuthenticated: false;
  evidence: { path: string; sha256: string }; pair: { dmb: string; rsc: string; dmbSha256: string; rscSha256: string; dmbBytes: number; rscBytes: number };
  compilation: CompilerProvenance; runtimeIdentity: RuntimeIdentity; nativeOutput?: NativePairOutput };
export type SuiteResumeCheckpoint = Omit<NormalResumeCheckpoint, 'schema' | 'kind'> & {
  schema: 2; kind: 'historical_suite_resume'; tier: SuiteTier;
};
export type ResumeCheckpoint = NormalResumeCheckpoint | SuiteResumeCheckpoint;
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
function resumeOutput(checkpoint: ResumeCheckpoint): CompiledOutput {
  const provenance = checkpoint.compilation;
  if (provenance.actualBackend === 'byond') {
    if (checkpoint.nativeOutput || provenance.nativePair) throw new Error('BYOND checkpoint contains native output');
    return { kind: 'conventional', backend: 'byond', dmb: checkpoint.pair.dmb, rsc: checkpoint.pair.rsc, provenance };
  }
  const output = checkpoint.nativeOutput;
  if (provenance.requestedBackend !== 'native' || provenance.fallback !== null || !output || output.kind !== 'native_pair'
    || output.compiler !== provenance.compiler.executable || !provenance.nativePair
    || !HEX.test(provenance.compiler.sha256 ?? '') || hashFile(output.compiler) !== provenance.compiler.sha256) {
    throw new Error('native resume requires its pinned native compiler and generation');
  }
  const parsed = parseCompileResult({ schema_version: 1, kind: 'native_pair', output_project: output.outputProject,
    store: output.store, pair_id: output.pairId, dmb_hash: output.dmbHash, rsc_hash: output.rscHash,
    dmb_bytes: output.dmbBytes, rsc_bytes: output.rscBytes, publication_proof: output.publicationProof }, output.compiler, output.outputProject);
  assertDirectoryChain(parsed.store);
  for (const field of ['pairId', 'dmbHash', 'rscHash', 'dmbBytes', 'rscBytes'] as const) {
    if (parsed[field] !== provenance.nativePair[field]) throw new Error('native checkpoint generation differs from compilation');
  }
  if (parsed.dmbBytes !== checkpoint.pair.dmbBytes || parsed.rscBytes !== checkpoint.pair.rscBytes) throw new Error('native preserved pair sizes differ');
  if (JSON.stringify(parsed.publicationProof) !== JSON.stringify(provenance.nativePublicationProof)) throw new Error('native publication proof differs');
  return { ...parsed, provenance };
}
/** Called after the existing native acquire validator and before DreamDaemon.
 * SHA256 binds these independent acquired copies to the preserved checkpoint pair. */
export function verifyResumeAcquiredPair(checkpoint: ResumeCheckpoint, dmb: string): void {
  const rsc = dmb.replace(/\.dmb$/i, '.rsc');
  if (rsc === dmb || hashFile(dmb) !== checkpoint.pair.dmbSha256 || hashFile(rsc) !== checkpoint.pair.rscSha256) {
    throw new Error('resumed hosted pair differs from preserved generation');
  }
}
export function validateCompletedPrefix<R extends ResumeRun>(evidence: ResumeEvidence<R>, checkpoint: ResumeCheckpoint, batchSize: number) {
  if (evidence.batchSize !== batchSize || JSON.stringify(evidence.compilation) !== JSON.stringify(checkpoint.compilation)) throw new Error('resume compilation/configuration differs');
  if (evidence.batches.length && !['normal-select-v1', 'suite-select-v1'].includes(evidence.selectionProtocol ?? '')) throw new Error('resume completed batches used another selection protocol');
  const issued = evidence.inventory;
  if (!issued?.inventory || !issued.clean || issued.killedByWatchdog || !sameSuiteRuntime(issued.runtimeIdentity, checkpoint.runtimeIdentity)) throw new Error('resume inventory/runtime unavailable');
  if (JSON.stringify(issued.compilation) !== JSON.stringify(checkpoint.compilation)) throw new Error('resume inventory compilation differs');
  const plan = { ...issued.inventory, eligible: evidence.plan?.eligibleOrder ?? issued.inventory.eligible };
  if (plan.tier !== 'normal' && evidence.selectionProtocol !== 'suite-select-v1') throw new Error('suite resume selection protocol differs');
  if (plan.tier !== (checkpoint.schema === 1 ? 'normal' : checkpoint.tier)) throw new Error('resume suite tier differs');
  suiteBatches(plan, batchSize);
  if (plan.eligible.length !== issued.inventory.eligible.length || plan.eligible.some(name => !issued.inventory!.eligible.includes(name))) throw new Error('resume plan differs from issued inventory');
  const batches = suiteBatches(plan, batchSize);
  if (!Array.isArray(evidence.batches) || evidence.batches.length > batches.length) throw new Error('resume prefix invalid');
  evidence.batches.forEach((batch, index) => {
    if (JSON.stringify(batch.requested) !== JSON.stringify(batches[index]) || !sameSuiteRuntime(batch.run.runtimeIdentity, checkpoint.runtimeIdentity)
      || JSON.stringify(batch.run.compilation) !== JSON.stringify(checkpoint.compilation) || batch.run.killedByWatchdog || !batch.run.results) throw new Error('resume batch identity/completion invalid');
    // The full inventory was validated above; this view validates only this
    // exact batch's rows and therefore has its own subset count.
    exactSuiteUnion({ ...plan, eligible: batch.requested, excluded: [], preTierCount: batch.requested.length, tierExcluded: [] },
      [{ requested: batch.requested, results: batch.run.results }]);
    Object.values(batch.run.results).forEach(row => { suiteRowSucceeded(row); });
  });
  return { plan, batches, completed: evidence.batches };
}
export function loadNormalResume<R extends ResumeRun>(file: string, sha256: string, batchSize: number) {
  const result = loadSuiteResume<R>(file, sha256, batchSize);
  if (result.plan.tier !== 'normal' || result.checkpoint.schema !== 1) throw new Error('normal resume requires historical normal checkpoint');
  return result;
}
export function loadSuiteResume<R extends ResumeRun>(file: string, sha256: string, batchSize: number) {
  const checkpoint = authenticatedJson(file, sha256) as ResumeCheckpoint;
  const kindValid = checkpoint.schema === 1 ? checkpoint.kind === 'historical_normal_suite_resume'
    : checkpoint.schema === 2 && checkpoint.kind === 'historical_suite_resume' && ['normal', 'all', 'exhaustive'].includes(checkpoint.tier);
  if (!kindValid || checkpoint.inputClosureAuthenticated !== false
    || !['byond', 'native'].includes(checkpoint.compilation?.actualBackend) || !checkpoint.compilation.compiler.sha256 || !checkpoint.runtimeIdentity?.sha256) throw new Error('unsupported/unpinned historical checkpoint');
  for (const kind of ['dmb', 'rsc'] as const) {
    if (process.platform === 'win32' && !/^e:[\\/]/i.test(checkpoint.pair[kind])) throw new Error('resume copies must be owned E: files');
    const expected = checkpoint.pair[`${kind}Sha256`];
    const bytes = checkpoint.pair[`${kind}Bytes`];
    if (!HEX.test(expected) || !Number.isSafeInteger(bytes) || bytes < 0 || fs.statSync(checkpoint.pair[kind]).size !== bytes
      || hashFile(checkpoint.pair[kind]) !== expected) throw new Error('resume output pair identity differs');
  }
  const evidence = authenticatedJson(checkpoint.evidence.path, checkpoint.evidence.sha256) as ResumeEvidence<R>;
  const admitted = validateCompletedPrefix(evidence, checkpoint, batchSize);
  const output = resumeOutput(checkpoint);
  return { ...admitted, output, originalPlan: evidence.plan, inventory: evidence.inventory!, checkpoint, checkpointPath: path.resolve(file), checkpointSha256: sha256 };
}

/** Extend an authenticated historical prefix after its owning runner has stopped.
 * The caller pins final evidence bytes; this function cannot prove process cleanup.
 * Each destination is new, so earlier checkpoints remain immutable evidence. */
export function issueNormalContinuation<R extends ResumeRun>(priorPath: string, priorSha256: string,
  evidencePath: string, evidenceSha256: string, batchSize: number, destination: string) {
  loadNormalResume<R>(priorPath, priorSha256, batchSize);
  return issueSuiteContinuation<R>(priorPath, priorSha256, evidencePath, evidenceSha256, batchSize, destination);
}
export function issueSuiteContinuation<R extends ResumeRun>(priorPath: string, priorSha256: string,
  evidencePath: string, evidenceSha256: string, batchSize: number, destination: string) {
  const prior = loadSuiteResume<R>(priorPath, priorSha256, batchSize);
  const evidence = authenticatedJson(evidencePath, evidenceSha256) as ResumeEvidence<R>;
  const admitted = validateCompletedPrefix(evidence, prior.checkpoint, batchSize);
  if (admitted.completed.length < prior.completed.length
    || prior.completed.some((batch, index) => JSON.stringify(batch) !== JSON.stringify(admitted.completed[index]))) {
    throw new Error('continuation rewrote or removed an admitted completed batch');
  }
  if (JSON.stringify(admitted.plan) !== JSON.stringify(prior.plan)) throw new Error('continuation changed the issued plan');
  if (evidence.plan?.sha256 !== prior.originalPlan?.sha256 || evidence.plan?.path !== prior.originalPlan?.path) {
    throw new Error('continuation changed the original reference plan pin');
  }
  if (!path.isAbsolute(destination) || process.platform === 'win32' && !/^e:[\\/]/i.test(destination)) {
    throw new Error('continuation destination must be an owned absolute E: path');
  }
  assertDirectoryChain(path.dirname(destination));
  // Authenticate again before writing: a live evidence writer must never be
  // silently accepted when its bytes differ from the caller's explicit pin.
  authenticatedJson(evidencePath, evidenceSha256);
  const checkpoint: ResumeCheckpoint = { ...prior.checkpoint,
    evidence: { path: path.resolve(evidencePath), sha256: evidenceSha256 } };
  const bytes = Buffer.from(`${JSON.stringify(checkpoint, null, 2)}\n`);
  fs.writeFileSync(destination, bytes, { flag: 'wx' });
  return { path: path.resolve(destination), sha256: createHash('sha256').update(bytes).digest('hex'),
    completedBatches: admitted.completed.length, totalBatches: admitted.batches.length };
}

/** Seed an actual native continuation from pinned final evidence and the existing
 * acquire receipt. The retained independent files remain owned by the caller.
 * This issues generation identity only, never current input closure or passing tests. */
export function issueNativeNormalResume<R extends ResumeRun>(evidencePath: string, evidenceSha256: string,
  acquisitionPath: string, acquisitionSha256: string, destination: string) {
  const evidence = authenticatedJson(evidencePath, evidenceSha256) as ResumeEvidence<R>;
  if (evidence.inventory?.inventory?.tier !== 'normal') throw new Error('normal seed requires normal inventory');
  return issueNativeSuiteResume<R>(evidencePath, evidenceSha256, acquisitionPath, acquisitionSha256, destination);
}
export function issueNativeSuiteResume<R extends ResumeRun>(evidencePath: string, evidenceSha256: string,
  acquisitionPath: string, acquisitionSha256: string, destination: string) {
  const evidence = authenticatedJson(evidencePath, evidenceSha256) as ResumeEvidence<R>;
  const compilation = evidence.compilation;
  if (!compilation || compilation.actualBackend !== 'native' || compilation.requestedBackend !== 'native'
    || compilation.fallback !== null || !evidence.nativeOutput || !evidence.inventory?.runtimeIdentity
    || !evidence.plan?.path || !evidence.plan.sha256) throw new Error('native seed lacks actual native output/reference plan/runtime');
  const reference = authenticatedJson(evidence.plan.path, evidence.plan.sha256) as ResumeEvidence<R>;
  if (reference.compilation?.actualBackend !== 'byond' || reference.compilation.requestedBackend !== 'byond'
    || reference.compilation.fallback !== null || !reference.inventory?.inventory
    || !['passed', 'failed'].includes(reference.status ?? '') || reference.batchSize !== evidence.batchSize
    || JSON.stringify(reference.compilation.orderedDefines) !== JSON.stringify(compilation.orderedDefines)) {
    throw new Error('native seed reference is not the completed matching BYOND plan');
  }
  const referencePlan = { ...reference.inventory.inventory, eligible: reference.plan?.eligibleOrder ?? reference.inventory.inventory.eligible };
  const referenceBatches = suiteBatches(referencePlan, reference.batchSize);
  if (reference.batches.length !== referenceBatches.length || !evidence.inventory.inventory
    || JSON.stringify(bindSuitePlan(evidence.inventory.inventory, referencePlan).eligible) !== JSON.stringify(evidence.plan.eligibleOrder)) {
    throw new Error('native seed changed reference order or reference is incomplete');
  }
  const acquired = authenticatedJson(acquisitionPath, acquisitionSha256) as { slot?: unknown };
  if (!acquired || typeof acquired.slot !== 'string' || !path.isAbsolute(acquired.slot)) throw new Error('native seed acquisition slot unavailable');
  const pair = parseAcquiredResult(acquired, evidence.nativeOutput, path.dirname(acquired.slot));
  const tier = evidence.inventory.inventory.tier;
  const checkpoint: ResumeCheckpoint = { ...(tier === 'normal' ? { schema: 1, kind: 'historical_normal_suite_resume' } as const
    : { schema: 2, kind: 'historical_suite_resume', tier } as const), inputClosureAuthenticated: false,
    evidence: { path: path.resolve(evidencePath), sha256: evidenceSha256 }, compilation,
    runtimeIdentity: evidence.inventory.runtimeIdentity, nativeOutput: evidence.nativeOutput,
    pair: { dmb: pair.dmb, rsc: pair.rsc, dmbBytes: evidence.nativeOutput.dmbBytes, rscBytes: evidence.nativeOutput.rscBytes,
      dmbSha256: hashFile(pair.dmb), rscSha256: hashFile(pair.rsc) } };
  resumeOutput(checkpoint);
  const admitted = validateCompletedPrefix(evidence, checkpoint, evidence.batchSize);
  const referenceAdmission = validateCompletedPrefix(reference, { ...checkpoint,
    compilation: reference.compilation!, runtimeIdentity: reference.inventory.runtimeIdentity! }, reference.batchSize);
  const boundReference = bindSuitePlan(admitted.plan, referenceAdmission.plan);
  if (!sameSuiteRuntime(checkpoint.runtimeIdentity, reference.inventory.runtimeIdentity)
    || JSON.stringify(boundReference.eligible) !== JSON.stringify(admitted.plan.eligible)
    || JSON.stringify(boundReference.automaticRows) !== JSON.stringify(admitted.plan.automaticRows)) {
    throw new Error('native seed runtime/reference plan differs');
  }
  if (!path.isAbsolute(destination) || process.platform === 'win32' && !/^e:[\\/]/i.test(destination)) throw new Error('seed destination must be an owned absolute E: path');
  assertDirectoryChain(path.dirname(destination));
  authenticatedJson(evidencePath, evidenceSha256);
  authenticatedJson(acquisitionPath, acquisitionSha256);
  authenticatedJson(evidence.plan.path, evidence.plan.sha256);
  verifyResumeAcquiredPair(checkpoint, pair.dmb);
  const bytes = Buffer.from(`${JSON.stringify(checkpoint, null, 2)}\n`);
  fs.writeFileSync(destination, bytes, { flag: 'wx' });
  return { path: path.resolve(destination), sha256: createHash('sha256').update(bytes).digest('hex'),
    completedBatches: admitted.completed.length, totalBatches: admitted.batches.length };
}

/** Preserve actual BYOND generation bytes after its runner has stopped. */
export function issueByondSuiteResume<R extends ResumeRun>(evidencePath: string, evidenceSha256: string,
  dmb: string, rsc: string, destination: string) {
  const evidence = authenticatedJson(evidencePath, evidenceSha256) as ResumeEvidence<R>;
  const compilation = evidence.compilation;
  const tier = evidence.inventory?.inventory?.tier;
  if (!compilation || compilation.actualBackend !== 'byond' || compilation.requestedBackend !== 'byond'
    || compilation.fallback !== null || compilation.nativePair !== null || evidence.nativeOutput
    || !compilation.compiler.executable || !compilation.compiler.sha256
    || hashFile(compilation.compiler.executable) !== compilation.compiler.sha256
    || !evidence.inventory?.runtimeIdentity || !tier) throw new Error('BYOND seed lacks pinned actual compiler/runtime');
  for (const file of [dmb, rsc, destination]) {
    if (!path.isAbsolute(file) || process.platform === 'win32' && !/^e:[\\/]/i.test(file)) throw new Error('suite checkpoint files must be owned absolute E: paths');
  }
  if (!/\.dmb$/i.test(dmb) || path.resolve(rsc) !== path.resolve(dmb.replace(/\.dmb$/i, '.rsc'))) throw new Error('BYOND checkpoint pair paths differ');
  const checkpoint: ResumeCheckpoint = { ...(tier === 'normal' ? { schema: 1, kind: 'historical_normal_suite_resume' } as const
    : { schema: 2, kind: 'historical_suite_resume', tier } as const), inputClosureAuthenticated: false,
    evidence: { path: path.resolve(evidencePath), sha256: evidenceSha256 }, compilation, runtimeIdentity: evidence.inventory.runtimeIdentity,
    pair: { dmb, rsc, dmbSha256: hashFile(dmb), rscSha256: hashFile(rsc), dmbBytes: fs.statSync(dmb).size, rscBytes: fs.statSync(rsc).size } };
  const admitted = validateCompletedPrefix(evidence, checkpoint, evidence.batchSize);
  assertDirectoryChain(path.dirname(destination));
  authenticatedJson(evidencePath, evidenceSha256);
  verifyResumeAcquiredPair(checkpoint, dmb);
  const bytes = Buffer.from(`${JSON.stringify(checkpoint, null, 2)}\n`);
  fs.writeFileSync(destination, bytes, { flag: 'wx' });
  return { path: path.resolve(destination), sha256: createHash('sha256').update(bytes).digest('hex'),
    completedBatches: admitted.completed.length, totalBatches: admitted.batches.length };
}

