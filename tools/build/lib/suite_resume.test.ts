import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { issueByondSuiteResume, issueSuiteContinuation, loadSuiteResume, loadNormalResume, type ResumeEvidence, type ResumeRun } from './normal_suite_resume';

test('all-tier checkpoint and continuation preserve actual tier, failures and authenticated prefix', () => {
  const base = process.platform === 'win32' ? 'E:/dq-cache/suite-resume-tests' : '/tmp/suite-resume-tests';
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, 'owned-'));
  const hash = (bytes: string) => createHash('sha256').update(bytes).digest('hex');
  try {
    const compiler = path.join(root, 'compiler.exe'); fs.writeFileSync(compiler, 'not executed');
    const compilation = { requestedBackend: 'byond', actualBackend: 'byond', fallback: null, nativePair: null,
      orderedDefines: ['UNIT_TESTS'], compiler: { executable: compiler, sha256: hash('not executed'), version: 516, build: 1687 } } as const;
    const runtime = { executable: 'E:/fake/dd.exe', sha256: 'a'.repeat(64), version: null, security: '-trusted' } as const;
    const names = ['/datum/unit_test/normal', '/datum/unit_test/exhaustive'];
    const run = (name: string, status: number) => ({ compilation, runtimeIdentity: runtime, clean: status === 0,
      killedByWatchdog: false, results: { [name]: { status, runtimes: 0 }, framework: { status: 0, runtimes: 0 } } });
    const evidence: ResumeEvidence<ResumeRun> = { batchSize: 1, compilation, selectionProtocol: 'suite-select-v1',
      inventory: { ...run(names[0], 0), inventory: { schema: 1, tier: 'all', eligible: names, excluded: [],
        automaticRows: ['framework'], preTierCount: 2, tierExcluded: [] } },
      batches: [{ requested: [names[0]], run: run(names[0], 1) }] };
    const evidenceFile = path.join(root, 'evidence.json'), dmb = path.join(root, 'pair.dmb'), rsc = path.join(root, 'pair.rsc');
    fs.writeFileSync(dmb, 'dmb'); fs.writeFileSync(rsc, 'rsc');
    const originalBytes = JSON.stringify(evidence); fs.writeFileSync(evidenceFile, originalBytes);
    const seed = issueByondSuiteResume(evidenceFile, hash(originalBytes), dmb, rsc, path.join(root, 'seed.json'));
    const prior = loadSuiteResume(seed.path, seed.sha256, 1);
    expect(prior.checkpoint.schema).toBe(2); expect(prior.plan.tier).toBe('all');
    expect(prior.completed[0].run.results![names[0]].status).toBe(1);
    expect(() => loadNormalResume(seed.path, seed.sha256, 1)).toThrow('normal');
    evidence.batches.push({ requested: [names[1]], run: run(names[1], 0) });
    const finalFile = path.join(root, 'final.json'), finalBytes = JSON.stringify(evidence); fs.writeFileSync(finalFile, finalBytes);
    const next = issueSuiteContinuation(seed.path, seed.sha256, finalFile, hash(finalBytes), 1, path.join(root, 'next.json'));
    expect(loadSuiteResume(next.path, next.sha256, 1).completed).toHaveLength(2);
    evidence.inventory!.inventory!.tier = 'exhaustive';
    const changed = JSON.stringify(evidence); fs.writeFileSync(finalFile, changed);
    expect(() => issueSuiteContinuation(seed.path, seed.sha256, finalFile, hash(changed), 1, path.join(root, 'bad.json'))).toThrow('tier');
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
