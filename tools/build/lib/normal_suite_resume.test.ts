import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { issueNativeNormalResume, issueNativeSuiteResume, issueNormalContinuation, loadNormalResume, loadSuiteResume, verifyResumeAcquiredPair, validateCompletedPrefix, type NormalResumeCheckpoint, type ResumeEvidence, type ResumeRun } from './normal_suite_resume';
const runtime = { executable: 'E:/dd.exe', sha256: 'a'.repeat(64), version: null, security: 'trusted' } as const;
const compilation = { requestedBackend: 'byond', actualBackend: 'byond', compiler: { executable: 'E:/dm.exe', sha256: 'b'.repeat(64), version: 516, build: 1687 }, orderedDefines: ['UNIT_TESTS'], fallback: null, nativePair: null } as const;
const checkpoint = { schema: 1, kind: 'historical_normal_suite_resume', inputClosureAuthenticated: false, compilation, runtimeIdentity: runtime } as unknown as NormalResumeCheckpoint;
function evidence(): ResumeEvidence<ResumeRun> {
  return { batchSize: 1, compilation, selectionProtocol: 'normal-select-v1', inventory: { compilation, clean: true, killedByWatchdog: false, runtimeIdentity: runtime, results: {},
    inventory: { schema: 1, tier: 'normal', eligible: ['/datum/unit_test/a', '/datum/unit_test/b'], excluded: [], automaticRows: ['framework'] } },
    batches: [{ requested: ['/datum/unit_test/a'], run: { compilation, clean: false, killedByWatchdog: false, runtimeIdentity: runtime,
      results: { '/datum/unit_test/a': { status: 1, runtimes: 2 }, framework: { status: 0 } } } }] };
}
describe('historical normal continuation', () => {
  test('native generation stays native, pins its compiler and original reference plan, and checks acquired bytes', () => {
    const base = process.platform === 'win32' ? 'E:/dq-cache/normal-resume-tests' : '/tmp/normal-resume-tests';
    fs.mkdirSync(base, { recursive: true });
    const root = fs.mkdtempSync(path.join(base, 'native-'));
    const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
    const write = (name: string, bytes: Buffer) => { const file = path.join(root, name); fs.writeFileSync(file, bytes); return file; };
    try {
      const compilerBytes = Buffer.from('synthetic compiler identity, never executed');
      const executable = write('compiler.exe', compilerBytes);
      const dmbBytes = Buffer.from('native-dmb'), rscBytes = Buffer.from('native-rsc');
      const dmb = write('pair.dmb', dmbBytes), rsc = write('pair.rsc', rscBytes);
      const pair = { pairId: '1'.repeat(32), dmbHash: '2'.repeat(32), rscHash: '3'.repeat(32), dmbBytes: dmbBytes.length, rscBytes: rscBytes.length };
      const nativeCompilation = { ...compilation, requestedBackend: 'native', actualBackend: 'native',
        compiler: { executable, sha256: hash(compilerBytes), version: null, build: null }, nativePair: pair } as const;
      const nativeEvidence = evidence(); nativeEvidence.compilation = nativeCompilation;
      nativeEvidence.inventory!.compilation = nativeCompilation;
      nativeEvidence.batches[0].run.compilation = nativeCompilation;
      const reference = evidence(); reference.status = 'failed';
      reference.batches.push({ requested: ['/datum/unit_test/b'], run: { ...reference.batches[0].run,
        results: { '/datum/unit_test/b': { status: 0 }, framework: { status: 0 } } } });
      const referenceBytes = Buffer.from(JSON.stringify(reference));
      const referencePath = write('plan.final.json', referenceBytes);
      nativeEvidence.plan = { path: referencePath, sha256: hash(referenceBytes), eligibleOrder: nativeEvidence.inventory!.inventory!.eligible };
      nativeEvidence.nativeOutput = { kind: 'native_pair', compiler: executable, store: root, outputProject: path.join(root, 'absent.dme'), ...pair };
      const evidenceBytes = Buffer.from(JSON.stringify(nativeEvidence)); const evidencePath = write('evidence.json', evidenceBytes);
      const doc: NormalResumeCheckpoint = { ...checkpoint, compilation: nativeCompilation,
        evidence: { path: evidencePath, sha256: hash(evidenceBytes) },
        pair: { dmb, rsc, dmbSha256: hash(dmbBytes), rscSha256: hash(rscBytes), dmbBytes: dmbBytes.length, rscBytes: rscBytes.length },
        nativeOutput: { kind: 'native_pair', compiler: executable, store: root, outputProject: path.join(root, 'absent.dme'), ...pair } };
      const save = (value: NormalResumeCheckpoint, name: string) => { const bytes = Buffer.from(JSON.stringify(value)); return [write(name, bytes), hash(bytes)] as const; };
      const [file, digest] = save(doc, 'checkpoint.json');
      const admitted = loadNormalResume(file, digest, 1);
      expect(admitted.output.kind).toBe('native_pair'); expect(admitted.originalPlan?.sha256).toBe(hash(referenceBytes));
      const next = issueNormalContinuation(file, digest, evidencePath, hash(evidenceBytes), 1, path.join(root, 'next.json'));
      expect(loadNormalResume(next.path, next.sha256, 1).output.kind).toBe('native_pair');
      const slot = path.join(root, 'slot'); fs.mkdirSync(slot);
      const acquiredDmb = path.join(slot, 'deepquarry.dmb'), acquiredRsc = path.join(slot, 'deepquarry.rsc');
      fs.writeFileSync(acquiredDmb, dmbBytes); fs.writeFileSync(acquiredRsc, rscBytes);
      fs.writeFileSync(path.join(slot, 'slot-complete'), pair.pairId);
      const acquisition = { schema_version: 1, kind: 'acquired_pair', store: root, slot, dmb: acquiredDmb, rsc: acquiredRsc,
        pair_id: pair.pairId, dmb_hash: pair.dmbHash, rsc_hash: pair.rscHash, dmb_bytes: pair.dmbBytes, rsc_bytes: pair.rscBytes };
      const acquisitionBytes = Buffer.from(JSON.stringify(acquisition)); const acquisitionPath = write('acquisition.json', acquisitionBytes);
      const seeded = issueNativeNormalResume(evidencePath, hash(evidenceBytes), acquisitionPath, hash(acquisitionBytes), path.join(root, 'seed.json'));
      expect(loadNormalResume(seeded.path, seeded.sha256, 1).originalPlan?.sha256).toBe(hash(referenceBytes));
      // A fresh captured generation issues its own inventory before any paired
      // baseline exists. Continue that exact generation without inventing one.
      const independent = structuredClone(nativeEvidence);
      independent.plan = { path: null, sha256: null, eligibleOrder: independent.inventory!.inventory!.eligible };
      const independentBytes = Buffer.from(JSON.stringify(independent));
      const independentPath = write('independent-native.json', independentBytes);
      const independentSeed = issueNativeNormalResume(independentPath, hash(independentBytes), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'independent-seed.json'));
      const own = loadNormalResume(independentSeed.path, independentSeed.sha256, 1);
      expect(own.completed).toHaveLength(1);
      expect(own.completed[0].run.results!['/datum/unit_test/a'].status).toBe(1);
      expect(own.originalPlan?.path).toBeNull();
      expect(own.checkpoint.inputClosureAuthenticated).toBe(false);
      const independentNext = issueNormalContinuation(independentSeed.path, independentSeed.sha256,
        independentPath, hash(independentBytes), 1, path.join(root, 'independent-next.json'));
      expect(loadNormalResume(independentNext.path, independentNext.sha256, 1).completed).toHaveLength(1);
      const rejectIndependent = (change: (value: typeof independent) => void, name: string) => {
        const altered = structuredClone(independent); change(altered);
        const bytes = Buffer.from(JSON.stringify(altered)); const file = write(`${name}.json`, bytes);
        expect(() => issueNativeNormalResume(file, hash(bytes), acquisitionPath, hash(acquisitionBytes),
          path.join(root, `${name}-seed.json`))).toThrow();
      };
      rejectIndependent(value => { value.plan!.eligibleOrder = [...value.plan!.eligibleOrder].reverse(); }, 'own-order');
      rejectIndependent(value => { value.plan!.sha256 = hash(referenceBytes); }, 'half-reference');
      rejectIndependent(value => { value.batches[0].run.runtimeIdentity = { ...runtime, security: 'safe' }; }, 'own-runtime');
      rejectIndependent(value => { value.batches[0].run.compilation = compilation; }, 'own-config');
      rejectIndependent(value => { value.nativeOutput!.pairId = '4'.repeat(32); }, 'own-pair');
      expect(() => issueNativeNormalResume(independentPath, '0'.repeat(64), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'own-bad-sha.json'))).toThrow();
      expect(() => issueNativeNormalResume(independentPath, hash(independentBytes), acquisitionPath,
        '0'.repeat(64), path.join(root, 'own-bad-acquisition-sha.json'))).toThrow();
      const allReference = structuredClone(reference); allReference.inventory!.inventory!.tier = 'all';
      Object.assign(allReference.inventory!.inventory!, { preTierCount: 2, tierExcluded: [] });
      allReference.selectionProtocol = 'suite-select-v1';
      const allReferenceBytes = Buffer.from(JSON.stringify(allReference)); const allReferencePath = write('all-reference.json', allReferenceBytes);
      const allNative = structuredClone(nativeEvidence); allNative.inventory!.inventory!.tier = 'all';
      Object.assign(allNative.inventory!.inventory!, { preTierCount: 2, tierExcluded: [] });
      allNative.selectionProtocol = 'suite-select-v1'; allNative.plan!.path = allReferencePath; allNative.plan!.sha256 = hash(allReferenceBytes);
      const allNativeBytes = Buffer.from(JSON.stringify(allNative)); const allNativePath = write('all-native.json', allNativeBytes);
      const allSeed = issueNativeSuiteResume(allNativePath, hash(allNativeBytes), acquisitionPath, hash(acquisitionBytes), path.join(root, 'all-seed.json'));
      const partialReference = structuredClone(allReference);
      partialReference.status = 'running'; partialReference.batches.pop();
      const partialBytes = Buffer.from(JSON.stringify(partialReference));
      const partialPath = write('partial-reference.json', partialBytes);
      const partialNative = structuredClone(allNative);
      partialNative.plan = { ...allNative.plan!, path: partialPath, sha256: hash(partialBytes) };
      const partialNativeBytes = Buffer.from(JSON.stringify(partialNative));
      const partialNativePath = write('partial-native.json', partialNativeBytes);
      const partialSeed = issueNativeSuiteResume(partialNativePath, hash(partialNativeBytes), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'partial-seed.json'));
      expect(loadSuiteResume(partialSeed.path, partialSeed.sha256, 1).completed).toHaveLength(1);
      expect(() => issueNativeSuiteResume(partialNativePath, '0'.repeat(64), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'wrong-evidence-sha.json'))).toThrow();
      const badOrder = structuredClone(partialNative);
      badOrder.plan!.eligibleOrder = [...badOrder.plan!.eligibleOrder].reverse();
      const badOrderBytes = Buffer.from(JSON.stringify(badOrder)); const badOrderPath = write('wrong-order.json', badOrderBytes);
      expect(() => issueNativeSuiteResume(badOrderPath, hash(badOrderBytes), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'bad-order-seed.json'))).toThrow('reference order');
      const badPlan = structuredClone(partialNative); badPlan.plan!.sha256 = '0'.repeat(64);
      const badPlanBytes = Buffer.from(JSON.stringify(badPlan)); const badPlanPath = write('wrong-plan-sha.json', badPlanBytes);
      expect(() => issueNativeSuiteResume(badPlanPath, hash(badPlanBytes), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'bad-plan-seed.json'))).toThrow();

      expect(loadSuiteResume(allSeed.path, allSeed.sha256, 1).plan.tier).toBe('all');
      expect(loadSuiteResume(allSeed.path, allSeed.sha256, 1).originalPlan?.sha256).toBe(hash(allReferenceBytes));
      expect(() => issueNativeNormalResume(allNativePath, hash(allNativeBytes), acquisitionPath, hash(acquisitionBytes), path.join(root, 'not-normal.json'))).toThrow('normal');
      expect(() => issueNativeNormalResume(evidencePath, '0'.repeat(64), acquisitionPath, hash(acquisitionBytes), path.join(root, 'bad-seed.json'))).toThrow();
      const fallbackEvidence = Buffer.from(JSON.stringify({ ...nativeEvidence,
        compilation: { ...nativeCompilation, fallback: 'internal_error_70' } }));
      const fallbackEvidencePath = write('fallback-evidence.json', fallbackEvidence);
      expect(() => issueNativeNormalResume(fallbackEvidencePath, hash(fallbackEvidence), acquisitionPath,
        hash(acquisitionBytes), path.join(root, 'fallback-seed.json'))).toThrow('actual native');
      fs.writeFileSync(path.join(slot, 'slot-complete'), '4'.repeat(32));
      expect(() => issueNativeNormalResume(evidencePath, hash(evidenceBytes), acquisitionPath, hash(acquisitionBytes), path.join(root, 'bad-slot.json'))).toThrow();
      verifyResumeAcquiredPair(doc, dmb);
      fs.writeFileSync(rsc, 'changed'); expect(() => verifyResumeAcquiredPair(doc, dmb)).toThrow(); fs.writeFileSync(rsc, rscBytes);
      const [badFile, badHash] = save({ ...doc, nativeOutput: { ...doc.nativeOutput!, pairId: '4'.repeat(32) } }, 'bad-pair.json');
      expect(() => loadNormalResume(badFile, badHash, 1)).toThrow();
      const [fallbackFile, fallbackHash] = save({ ...doc, compilation: { ...nativeCompilation, fallback: 'internal_error_70' } }, 'fallback.json');
      expect(() => loadNormalResume(fallbackFile, fallbackHash, 1)).toThrow();
      fs.writeFileSync(executable, 'other compiler'); expect(() => loadNormalResume(file, digest, 1)).toThrow();
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
  });
  test('file-backed admission authenticates checkpoint evidence and both preserved files', () => {
    const base = process.platform === 'win32' ? 'E:/dq-cache/normal-resume-tests' : '/tmp/normal-resume-tests';
    fs.mkdirSync(base, { recursive: true });
    const root = fs.mkdtempSync(path.join(base, 'owned-'));
    const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
    const dmb = path.join(root, 'pair.dmb'); const rsc = path.join(root, 'pair.rsc');
    const evidencePath = path.join(root, 'evidence.json'); const checkpointPath = path.join(root, 'checkpoint.json');
    const dmbBytes = Buffer.from('dmb'); const rscBytes = Buffer.from('rsc');
    const evidenceBytes = Buffer.from(JSON.stringify(evidence()));
    const doc = { ...checkpoint, evidence: { path: evidencePath, sha256: hash(evidenceBytes) }, pair: {
      dmb, rsc, dmbSha256: hash(dmbBytes), rscSha256: hash(rscBytes), dmbBytes: dmbBytes.length, rscBytes: rscBytes.length } };
    const checkpointBytes = Buffer.from(JSON.stringify(doc)); const checkpointHash = hash(checkpointBytes);
    const restore = () => { fs.writeFileSync(dmb, dmbBytes); fs.writeFileSync(rsc, rscBytes);
      fs.writeFileSync(evidencePath, evidenceBytes); fs.writeFileSync(checkpointPath, checkpointBytes); };
    const load = () => loadNormalResume<ResumeRun>(checkpointPath, checkpointHash, 1);
    try {
      restore(); expect(load().completed.length).toBe(1); expect(load().output.kind).toBe('conventional');
      const next = path.join(root, 'next-checkpoint.json');
      const issued = issueNormalContinuation<ResumeRun>(checkpointPath, checkpointHash, evidencePath, hash(evidenceBytes), 1, next);
      expect(loadNormalResume<ResumeRun>(issued.path, issued.sha256, 1).completed).toEqual(evidence().batches);
      expect(() => issueNormalContinuation(checkpointPath, checkpointHash, evidencePath, hash(evidenceBytes), 1, next)).toThrow();
      const rewritten = evidence(); rewritten.batches[0].run.results!['/datum/unit_test/a'].status = 0;
      const rewrittenBytes = Buffer.from(JSON.stringify(rewritten)); fs.writeFileSync(evidencePath, rewrittenBytes);
      expect(() => issueNormalContinuation(next, issued.sha256, evidencePath, hash(rewrittenBytes), 1, path.join(root, 'bad.json'))).toThrow();
      restore();
      for (const file of [checkpointPath, evidencePath, dmb, rsc]) {
        fs.writeFileSync(file, 'tampered'); expect(load).toThrow(); restore();
      }
      // The path itself is part of authenticated checkpoint bytes: swapping an
      // otherwise identical foreign copy without issuing a new checkpoint fails.
      const foreign = path.join(root, 'foreign.dmb'); fs.writeFileSync(foreign, dmbBytes);
      fs.writeFileSync(checkpointPath, JSON.stringify({ ...doc, pair: { ...doc.pair, dmb: foreign } }));
      expect(load).toThrow(); restore();
      fs.unlinkSync(dmb);
      try {
        fs.symlinkSync(foreign, dmb, 'file');
        expect(load).toThrow();
      } catch (error) {
        // Windows accounts without symlink privilege still exercise the foreign
        // path and byte-tamper cases above; do not turn that into a link claim.
        if ((error as NodeJS.ErrnoException).code !== 'EPERM') throw error;
      }
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
  });
  test('preserves completed failures and resumes only suffix', () => {
    const original = evidence(); const admitted = validateCompletedPrefix(original, checkpoint, 1);
    expect(admitted.completed[0].run.results?.['/datum/unit_test/a'].status).toBe(1);
    expect(admitted.batches.slice(admitted.completed.length)).toEqual([['/datum/unit_test/b']]);
  });
  test('rejects wrong generation, runtime, non-prefix and missing rows', () => {
    const changed = evidence(); changed.compilation = { ...compilation, orderedDefines: ['CHANGED'] };
    expect(() => validateCompletedPrefix(changed, checkpoint, 1)).toThrow();
    const inventoryGeneration = evidence(); inventoryGeneration.inventory!.compilation = { ...compilation, orderedDefines: ['OTHER_GENERATION'] };
    expect(() => validateCompletedPrefix(inventoryGeneration, checkpoint, 1)).toThrow('inventory compilation');
    const wrong = evidence(); wrong.batches[0].run.runtimeIdentity = { ...runtime, sha256: 'c'.repeat(64) };
    expect(() => validateCompletedPrefix(wrong, checkpoint, 1)).toThrow();
    const nonprefix = evidence(); nonprefix.batches[0].requested = ['/datum/unit_test/b'];
    expect(() => validateCompletedPrefix(nonprefix, checkpoint, 1)).toThrow();
    const missing = evidence(); delete missing.batches[0].run.results!.framework;
    expect(() => validateCompletedPrefix(missing, checkpoint, 1)).toThrow();
    const focused = evidence(); delete focused.selectionProtocol;
    expect(() => validateCompletedPrefix(focused, checkpoint, 1)).toThrow('selection protocol');
  });
});
