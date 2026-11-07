import { expect, test } from 'bun:test';
import path from 'node:path';
import { nativeGenerationRequest, nativeGenerationWrittenCount } from './native_generation';

test('native build generation requests the complete Original roster and fixed inputs', () => {
  const root = path.resolve('test-workspace');
  const cache = path.resolve('test-cache');
  const request = nativeGenerationRequest(root, cache, 2);
  expect(request.check).toBe(false);
  expect(request.build.project).toBe(path.join(root, 'deepquarry.dme'));
  expect(request.build.cache_root).toBe(cache);
  expect(request.build.workers).toBe(2);
  expect(request.build.defines).toEqual({});
  const policy = request.build.policy_inputs;
  expect(policy.analysis_context).toBe('original_analyze0290');
  expect(policy.workspace.recursive_roots).toEqual([path.join(root, 'code')]);
  expect(policy.workspace.configuration).toBe(path.join(root, 'tools/ci/lint_scopes.toml'));
  expect(new Set(policy.workspace_generators).size).toBe(12);
  expect(policy.workspace_generators).not.toContain('sparse_slots');
});

test('native build generation counts final changed paths and refuses partial delivery', () => {
  const header = { schema: 'native-generation-batch-v1', row: 'generation_batch',
    status: 'completed', clean: true, committed: true, cleanup_warnings: 0 };
  const report = { schema: 'native-generation-v1', clean: true, committed: true,
    changed: [path.resolve('generated.dm')] };
  const encode = (value: object) => [header, value].map((row) => JSON.stringify(row)).join('\n');
  expect(nativeGenerationWrittenCount(encode(report))).toBe(1);
  expect(() => nativeGenerationWrittenCount(JSON.stringify(header))).toThrow();
  expect(() => nativeGenerationWrittenCount(encode({ ...report, clean: false }))).toThrow();
  expect(() => nativeGenerationWrittenCount(encode({ ...report, changed: [] }))).toThrow();
});
