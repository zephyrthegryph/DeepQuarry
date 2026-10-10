import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { loadNormalResume, validateCompletedPrefix, type NormalResumeCheckpoint, type ResumeEvidence, type ResumeRun } from './normal_suite_resume';
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
