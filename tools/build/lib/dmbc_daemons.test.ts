import { afterEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { effectiveNamespace, enterDaemonScope, worktreeNamespace } from './dmbc_daemons';

const saved = { ...process.env };
afterEach(() => { process.env = { ...saved }; });

describe('dmbc daemon namespaces', () => {
  test('default namespace is per worktree and valid for dmbc', () => {
    delete process.env.DMB_DAEMON_NAMESPACE;
    const a = worktreeNamespace('E:/projects/dq-wt/a');
    expect(a).toMatch(/^wt-[0-9a-f]{16}$/);
    expect(a).toBe(worktreeNamespace(['e:', 'projects', 'dq-wt', 'a'].join(String.fromCharCode(92)) + String.fromCharCode(92)));
    expect(a).not.toBe(worktreeNamespace('E:/projects/dq-wt/b'));
  });
  test('explicit DMB_DAEMON_NAMESPACE wins', () => {
    process.env.DMB_DAEMON_NAMESPACE = 'mine';
    expect(effectiveNamespace('E:/x')).toBe('mine');
  });
  test('evicts least recently used idle namespaces, never a leased one', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dmbd-'));
    process.env.DQ_DMBC_DAEMON_DIR = dir;
    process.env.DQ_DMBC_MAX_DAEMONS = '2';
    delete process.env.DMB_DAEMON_NAMESPACE;
    const entry = (ns: string, lastUsed: number) => fs.writeFileSync(path.join(dir, `${ns}.json`), JSON.stringify({ namespace: ns, root: ns, lastUsed }));
    entry('wt-old', 1); entry('wt-busy', 2); entry('wt-new', 3);
    fs.writeFileSync(path.join(dir, `wt-busy.lease.${process.pid}`), '1');
    const scope = enterDaemonScope('E:/projects/dq-wt/self', 'no-such-dmbc');
    const left = fs.readdirSync(dir).filter((n) => n.endsWith('.json')).sort();
    expect(left).toContain('wt-busy.json');
    expect(left).toContain(`${scope.namespace}.json`);
    expect(left).toContain('wt-old.json'); // retire failed (no dmbc): stays registered
    scope.release();
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
