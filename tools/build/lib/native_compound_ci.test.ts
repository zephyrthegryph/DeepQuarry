import { expect, test } from 'bun:test';
import path from 'node:path';
import { fullCiCompoundRequest, requireFullCiReceipt } from './native_compound_ci';
import { nativeRequestRoot } from './native_pair';

test('compound request scratch follows the cache policy on Windows and Linux', () => {
  expect(nativeRequestRoot(undefined, 'win32', 'C:\\Users\\ci')).toBe('E:\\dq-cache\\dmb-build-integration');
  expect(() => nativeRequestRoot('C:\\scratch', 'win32', 'C:\\Users\\ci')).toThrow('must be on E:');
  expect(nativeRequestRoot(undefined, 'linux', '/home/ci')).toBe('/home/ci/.cache/dq/dmb-build-integration');
  expect(nativeRequestRoot('/var/cache/dq', 'linux', '/home/ci')).toBe('/var/cache/dq');
  expect(() => nativeRequestRoot('local', 'linux', '/home/ci')).toThrow('absolute cache path');
});

test('full CI request leaves Original defines empty and selects the closed CBT profile', () => {
  const root = path.resolve('fixture-project');
  const cache = path.resolve('fixture-cache');
  const request = fullCiCompoundRequest(root, cache, 2);
  expect(request.analyze_registry).toBe('full');
  expect(request.analyze_judgment).toBe('ci');
  expect(request.strict_profile).toBe('cbt');
  expect(request.selected.build.defines).toEqual({});
  expect(request.selected.build.policy_inputs.workspace.recursive_roots.map((dir) => path.relative(root, dir).replaceAll('\\', '/')))
    .toEqual(['code', 'doc/rewrite', 'interface', 'maps', 'modular_chomp', 'tgui']);
  expect(() => fullCiCompoundRequest(root, cache, 9)).toThrow('one to eight');
});

test('full CI receipt distinguishes a dirty completed verdict from a wrong mode or truncated delivery', () => {
  const hash = 'a'.repeat(32);
  const data = {
    schema: 'native-compiled-full-registry-ci-cbt-v1',
    native_pair: { version: 1, dmb_bytes: 19 },
    selected: {
      schema: 'native-checker-analyze-full-registry-ci-cbt-v1',
      clean: false,
      diagnostics: { length: 3, hash },
      checker: { length: 7, hash },
      report: { length: 12, hash },
    },
  };
  const prefix = Buffer.from(JSON.stringify(data) + '\n');
  expect(() => requireFullCiReceipt(prefix, prefix.length + 19, 3, 1)).not.toThrow();
  expect(() => requireFullCiReceipt(prefix, prefix.length + 19, 3, 0)).toThrow('Strict CBT');
  expect(() => requireFullCiReceipt(prefix, prefix.length + 18, 3, 1)).toThrow('exact report bytes');
  data.schema = 'native-compiled-full-registry-ci-v1';
  const foreign = Buffer.from(JSON.stringify(data) + '\n');
  expect(() => requireFullCiReceipt(foreign, foreign.length + 19, 3, 1)).toThrow('Strict CBT');
});
