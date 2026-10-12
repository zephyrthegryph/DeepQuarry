import { expect, test } from 'bun:test';
import path from 'node:path';
import { acquiredWorldArguments, resolveDreamDaemonExecutable } from './byond_runtime';

test('acquiring output preserves original world directory and explicit caller choice', () => {
  const args = ['1234', '-trusted', '-params', 'test-focus=data/focus.txt'];
  expect(acquiredWorldArguments(args, 'deepquarry.test.run1.dmb', true))
    .toEqual([...args, '-cd', process.cwd()]);
  expect(acquiredWorldArguments(args, 'deepquarry.test.run1.dmb', false)).toBe(args);
  const explicit = [...args, '-cd', 'chosen'];
  expect(acquiredWorldArguments(explicit, 'ignored.dmb', true)).toBe(explicit);
});

test('hosting resolves the selected runtime version once and uses its sibling daemon', async () => {
  const versions: Array<string | null | undefined> = [];
  const dm = path.join('pinned-byond', 'bin', 'dm.exe');
  const executable = await resolveDreamDaemonExecutable('516.1687', async (version) => {
    versions.push(version);
    return dm;
  }, 'win32');
  expect(versions).toEqual(['516.1687']);
  expect(executable).toBe(path.join('pinned-byond', 'bin', 'dd.exe'));
});

test('bare runtime lookup preserves platform executable search', async () => {
  expect(await resolveDreamDaemonExecutable(undefined, async () => 'dm.exe', 'win32', undefined)).toBe('dd.exe');
  expect(await resolveDreamDaemonExecutable(null, async () => 'DreamMaker', 'linux')).toBe('DreamDaemon');
});

test('explicit runtime accepts only selected console sibling and never GUI fallback', async () => {
  const dm = path.resolve('pinned-byond/bin/dm.exe');
  const dd = path.join(path.dirname(dm), 'dd.exe');
  expect(await resolveDreamDaemonExecutable(null, async () => dm, 'win32', dd)).toBe(dd);
  for (const invalid of [path.join(path.dirname(dm), 'dreamdaemon.exe'), path.resolve('other/dd.exe'), 'dd.exe']) {
    await expect(resolveDreamDaemonExecutable(null, async () => dm, 'win32', invalid)).rejects.toThrow('console sibling');
  }
});

test('runtime lookup failure preserves the original error', async () => {
  const failure = new Error('Selected BYOND installation is unavailable');
  let caught: unknown;
  try {
    await resolveDreamDaemonExecutable('missing', async () => { throw failure; });
  } catch (error) {
    caught = error;
  }
  expect(caught).toBe(failure);
});
