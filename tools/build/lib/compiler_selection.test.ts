import { afterEach, expect, test } from 'bun:test';
import { compilerCacheIdentity, compilerMode, selectedCompiler } from './compiler_selection';
import Juke from '../juke/index.js';
const originalEnvironment = { ...process.env };
afterEach(() => {
  for (const name of ['DQ_COMPILER', 'DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE', 'DQ_NATIVE_WORKERS']) {
    if (originalEnvironment[name] === undefined) delete process.env[name];
    else process.env[name] = originalEnvironment[name];
  }
});
test('default dispatch retains one BYOND call and rejects unknown modes', async () => {
  delete process.env.DQ_COMPILER;
  let calls = 0;
  await selectedCompiler('project.dme', {}, async () => { calls++; });
  expect(calls).toBe(1);
  expect(compilerCacheIdentity()).toBe('byond');
  process.env.DQ_COMPILER = 'typo';
  expect(() => compilerMode()).toThrow('Unknown DQ_COMPILER');
});
test('native uses current manifest/defines and successful compilation does not run BYOND', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  process.env.DQ_NATIVE_WORKERS = '6';
  let recorded: string[] = [];
  const execute = async (_executable: string, args: string[]) => {
    recorded = args;
    return { code: 0, combined: '', stdout: '', stderr: '', signal: null };
  };
  let byondCalls = 0;
  await selectedCompiler('project.dme', { defines: ['CITESTING=1'] }, async () => { byondCalls++; }, execute);
  expect(byondCalls).toBe(0);
  expect(recorded).toContain('-DCITESTING=1');
  expect(recorded).toContain('6');
  expect(recorded).not.toContain('--artifact-directory');
});
test('transitional native nonzero status explicitly falls back exactly once', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  const execute = async () => ({ code: 1, combined: 'diagnostic', stdout: '', stderr: 'diagnostic', signal: null });
  let byondCalls = 0;
  await selectedCompiler('project.dme', {}, async () => { byondCalls++; }, execute);
  expect(byondCalls).toBe(1);
});

test('typed source and cancellation statuses never fall back', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  for (const code of [2, 75]) {
    const execute = async () => ({ code, combined: 'diagnostic', stdout: '', stderr: 'diagnostic', signal: null });
    let byondCalls = 0;
    await expect(selectedCompiler('project.dme', {}, async () => { byondCalls++; }, execute)).rejects.toBeInstanceOf(Juke.ExitCode);
    expect(byondCalls).toBe(0);
  }
});
