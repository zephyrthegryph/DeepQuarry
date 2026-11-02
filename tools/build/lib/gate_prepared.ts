import { spawnSync } from 'node:child_process';

/**
 * The gate ran its prepare step (icon repack, DME check, bindings check) on this commit and passed, and exported DQ_GATE_PREPARED=<HEAD>
 * (tools/dq_merge_gates.sh). The test job's dm-test would otherwise run the same steps again: 20-30 s of every precheck on 1 November.
 * Any other commit, or a tree with tracked changes, runs them as usual.
 */
export function gatePrepared(head: () => string = gitHead, dirty: () => boolean = gitDirty, prepared = process.env.DQ_GATE_PREPARED): boolean {
  return !!prepared && head() === prepared && !dirty();
}

function gitHead(): string {
  return spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout?.trim() ?? '';
}

// The ratchets job may shrink a baseline beside the tests; that file is no input of these steps.
function gitDirty(): boolean {
  const out = spawnSync('git', ['status', '--porcelain', '--untracked-files=no'], { encoding: 'utf8' });
  if (out.status !== 0) return true;
  return out.stdout.split('\n').some(line => line.trim() && !/^.. tools\/ci\/([a-z_]+_baseline\.txt|sys_baseline\/)/.test(line));
}
