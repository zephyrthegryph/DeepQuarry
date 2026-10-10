import { expect, test } from 'bun:test';
import path from 'node:path';
import { resolveDreamDaemonExecutable } from './byond_runtime';

test('hosting resolves the selected runtime version once and uses its sibling daemon', async () => {
  const versions: Array<string | null | undefined> = [];
  const dm = path.join('pinned-byond', 'bin', 'dm.exe');
  const executable = await resolveDreamDaemonExecutable('516.1687', async (version) => {
    versions.push(version);
    return dm;
  }, 'win32');
  expect(versions).toEqual(['516.1687']);
  expect(executable).toBe(path.join('pinned-byond', 'bin', 'dreamdaemon.exe'));
});

test('bare runtime lookup preserves platform executable search', async () => {
  expect(await resolveDreamDaemonExecutable(undefined, async () => 'dm.exe', 'win32')).toBe('dreamdaemon.exe');
  expect(await resolveDreamDaemonExecutable(null, async () => 'DreamMaker', 'linux')).toBe('DreamDaemon');
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
