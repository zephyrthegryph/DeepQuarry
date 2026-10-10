import { expect, test } from 'bun:test';
import path from 'node:path';
import { compilerInvocation, bindCompilerInvocation } from './compiler_invocation';
import { selectedCompiler } from './compiler_selection';
test('captured backend invocation preserves cwd, relative spelling and ordered duplicate defines', async () => {
  const previous = { ...process.env };
  try {
    const defines = ['A=1', 'A=2'];
    const invocation = compilerInvocation('E:/dq-cache/invocation-fixture', 'nested/probe.dme', defines);
    defines.push('B=3');
    process.env.DQ_COMPILER = 'byond';
    let byond = false;
    await selectedCompiler('original.dme', { defines: ['A=1', 'A=2'] }, async (manifest, _, bound) => {
      byond = true;
      expect(manifest).toBe('nested/probe.dme');
      expect(bound?.root).toBe(path.resolve('E:/dq-cache/invocation-fixture'));
      expect(bound?.orderedDefines).toEqual(['A=1', 'A=2']);
    }, undefined, undefined, invocation);
    expect(byond).toBe(true);
    process.env.DQ_COMPILER = 'native';
    process.env.DQ_NATIVE_COMPILER = 'native';
    process.env.DQ_NATIVE_ENGINE_TEMPLATE = path.resolve('template.bin');
    let native = false;
    await expect(selectedCompiler('original.dme', { defines: ['A=1', 'A=2'] }, async () => { throw new Error('unexpected fallback'); }, async (_, args, options) => {
      native = true;
      expect(args[1]).toBe('nested/probe.dme');
      expect(options?.cwd).toBe(invocation.root);
      expect(args.filter(arg => arg.startsWith('-D'))).toEqual(['-DA=1', '-DA=2']);
      return { code: 2, combined: '' };
    }, undefined, invocation)).rejects.toBeDefined();
    expect(native).toBe(true);
    process.env.DQ_COMPILER = 'shadow';
    await expect(selectedCompiler('original.dme', { defines: ['A=1', 'A=2'] }, async () => { throw new Error('unexpected child'); }, undefined, undefined, invocation)).rejects.toThrow('output namespace authority');
    expect(() => bindCompilerInvocation(invocation, ['A=2', 'A=1'])).toThrow('ordered defines');
    for (const invalid of ['../probe.dme', '/probe.dme', 'C:probe.dme']) expect(() => compilerInvocation(invocation.root, invalid, [])).toThrow();
  } finally {
    for (const key of ['DQ_COMPILER', 'DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE']) {
      if (previous[key] === undefined) delete process.env[key]; else process.env[key] = previous[key];
    }
  }
});
