import { afterEach, describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { effectiveNamespace, enterDaemonScope, memoryShortfallBytes } from './dmbc_daemons';

const saved = { ...process.env };
afterEach(() => { process.env = { ...saved }; });

describe('dmbc daemon namespaces', () => {
  test('default is the one machine-wide daemon: no namespace, no registry', () => {
    delete process.env.DMB_DAEMON_NAMESPACE;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dmbd-'));
    process.env.DQ_DMBC_DAEMON_DIR = dir;
    expect(effectiveNamespace()).toBeUndefined();
    const scope = enterDaemonScope('E:/projects/dq-wt/a', 'no-such-dmbc');
    expect(scope.namespace).toBeUndefined();
    expect(process.env.DMB_DAEMON_NAMESPACE).toBeUndefined();
    scope.release();
    expect(fs.readdirSync(dir)).toEqual([]);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  test('explicit DMB_DAEMON_NAMESPACE wins', () => {
    process.env.DMB_DAEMON_NAMESPACE = 'mine';
    expect(effectiveNamespace()).toBe('mine');
  });
  test('evicts least recently used idle namespaces, never a leased one', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dmbd-'));
    process.env.DQ_DMBC_DAEMON_DIR = dir;
    process.env.DQ_DMBC_MAX_DAEMONS = '2';
    process.env.DMB_DAEMON_NAMESPACE = 'wt-self';
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
  test('memory shortfall is reserve plus a cold compile minus free memory', () => {
    process.env.DMB_DAEMON_FREE_RESERVE_GB = '12';
    expect(memoryShortfallBytes(30e9)).toBe(0);
    expect(memoryShortfallBytes(20e9)).toBe(4e9);
    process.env.DMB_DAEMON_FREE_RESERVE_GB = '0';
    expect(memoryShortfallBytes(12e9)).toBe(0);
  });
});
