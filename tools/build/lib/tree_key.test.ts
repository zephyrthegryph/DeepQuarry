import { afterAll, describe, expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { gitTreeKey, readKeyRecord, runCaptured, writeKeyRecord } from './tree_key';

// Scratch on E: when present (caches and scratch never on C:), removed after the run.
const SCRATCH = fs.mkdtempSync(path.join(fs.existsSync('E:/dq-cache') ? 'E:/dq-cache/test-scratch' : os.tmpdir(), `tree-key-${process.pid}-`));
afterAll(() => fs.rmSync(SCRATCH, { recursive: true, force: true }));
const repo = (): string => {
  const dir = fs.mkdtempSync(path.join(SCRATCH, 'r-'));
  const git = (...args: string[]) => execFileSync('git', ['-C', dir, ...args], { stdio: 'ignore' });
  git('init', '-q');
  git('config', 'user.email', 't@t');
  git('config', 'user.name', 't');
  fs.mkdirSync(`${dir}/code`);
  fs.writeFileSync(`${dir}/code/a.dm`, 'a');
  fs.writeFileSync(`${dir}/.gitignore`, 'code/gen/\n');
  git('add', '.');
  git('commit', '-qm', 'x');
  return dir;
};

describe('gitTreeKey', () => {
  test('stable when nothing changed; a touch with the same content keeps it', async () => {
    const dir = repo();
    const k = await gitTreeKey(dir, 't', ['code']);
    expect(k).not.toBeNull();
    const t = new Date(Date.now() + 5000);
    fs.utimesSync(`${dir}/code/a.dm`, t, t);
    expect(await gitTreeKey(dir, 't', ['code'])).toBe(k);
  });
  test('an edit, a new file and a second edit of a modified file all change it', async () => {
    const dir = repo();
    const k0 = await gitTreeKey(dir, 't', ['code']);
    fs.writeFileSync(`${dir}/code/a.dm`, 'b');
    const k1 = await gitTreeKey(dir, 't', ['code']);
    expect(k1).not.toBe(k0);
    fs.writeFileSync(`${dir}/code/a.dm`, 'bc');
    const k2 = await gitTreeKey(dir, 't', ['code']);
    expect(k2).not.toBe(k1);
    fs.writeFileSync(`${dir}/code/b.dm`, 'x');
    expect(await gitTreeKey(dir, 't', ['code'])).not.toBe(k2);
  });
  test('ignored files: stat-ed by default, presence only with statIgnored=false', async () => {
    const dir = repo();
    fs.mkdirSync(`${dir}/code/gen`);
    fs.writeFileSync(`${dir}/code/gen/g.dm`, '1');
    const a = await gitTreeKey(dir, 't', ['code']);
    const p = await gitTreeKey(dir, 't', ['code'], [], false);
    fs.writeFileSync(`${dir}/code/gen/g.dm`, '22');
    expect(await gitTreeKey(dir, 't', ['code'])).not.toBe(a);
    expect(await gitTreeKey(dir, 't', ['code'], [], false)).toBe(p);
    fs.rmSync(`${dir}/code/gen/g.dm`);
    expect(await gitTreeKey(dir, 't', ['code'], [], false)).not.toBe(p);
  });
  test('null outside git; records round-trip; runCaptured reports status', async () => {
    const dir = fs.mkdtempSync(path.join(SCRATCH, 'nogit-'));
    expect(await gitTreeKey(dir, 't', ['code'])).toBeNull();
    writeKeyRecord(`${dir}/data/r.json`, 'abc');
    expect(readKeyRecord(`${dir}/data/r.json`)).toBe('abc');
    expect(readKeyRecord(`${dir}/none.json`)).toBeNull();
    expect((await runCaptured('git', ['--version'])).status).toBe(0);
    expect((await runCaptured('git', ['no-such-command'])).status).not.toBe(0);
    expect((await runCaptured('no-such-binary-xyz', [])).error).toBeDefined();
  });
});
