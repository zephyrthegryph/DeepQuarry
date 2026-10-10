import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { issueNormalContinuation, loadNormalResume, verifyResumeAcquiredPair, validateCompletedPrefix, type NormalResumeCheckpoint, type ResumeEvidence, type ResumeRun } from './normal_suite_resume';
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
      nativeEvidence.plan = { path: path.join(root, 'plan.final.json'), sha256: 'f'.repeat(64), eligibleOrder: nativeEvidence.inventory!.inventory!.eligible };
      const evidenceBytes = Buffer.from(JSON.stringify(nativeEvidence)); const evidencePath = write('evidence.json', evidenceBytes);
      const doc: NormalResumeCheckpoint = { ...checkpoint, compilation: nativeCompilation,
        evidence: { path: evidencePath, sha256: hash(evidenceBytes) },
        pair: { dmb, rsc, dmbSha256: hash(dmbBytes), rscSha256: hash(rscBytes), dmbBytes: dmbBytes.length, rscBytes: rscBytes.length },
        nativeOutput: { kind: 'native_pair', compiler: executable, store: root, outputProject: path.join(root, 'absent.dme'), ...pair } };
      const save = (value: NormalResumeCheckpoint, name: string) => { const bytes = Buffer.from(JSON.stringify(value)); return [write(name, bytes), hash(bytes)] as const; };
      const [file, digest] = save(doc, 'checkpoint.json');
      const admitted = loadNormalResume(file, digest, 1);
      expect(admitted.output.kind).toBe('native_pair'); expect(admitted.originalPlan?.sha256).toBe('f'.repeat(64));
      const next = issueNormalContinuation(file, digest, evidencePath, hash(evidenceBytes), 1, path.join(root, 'next.json'));
      expect(loadNormalResume(next.path, next.sha256, 1).output.kind).toBe('native_pair');
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
