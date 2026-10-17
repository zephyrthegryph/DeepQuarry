import path from 'node:path';
import { DreamMaker } from './lib/byond';
const worktree = path.resolve(process.argv[2]);
process.env.DQ_BUILD_ROOT = worktree;
process.chdir(worktree);
const started = Date.now();
const output = await DreamMaker(path.join(worktree, 'deepquarry.dme'), { defines: ['CBT'], warningsAsErrors: false, ignoreWarningCodes: [], namedDmVersion: null });
console.log('RESULT', JSON.stringify({ worktree, seconds: (Date.now() - started) / 1000, kind: output.kind, pair: (output as any).pairId, project: (output as any).outputProject }));
