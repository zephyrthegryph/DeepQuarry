import { afterEach, expect, test } from 'bun:test';
import { classifyShadowReport, compilerCacheIdentity, compilerMode, selectedCompiler, shadowSnapshotContract } from './compiler_selection';
import Juke from '../juke/index.js';
import fs from 'node:fs';
const originalEnvironment = { ...process.env };
afterEach(() => {
  for (const name of ['DQ_COMPILER', 'DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE', 'DQ_NATIVE_WORKERS', 'DQ_SHADOW_ROOT']) {
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

test('native cannot silently discard requested compiler version or warning policy', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  for (const options of [
    { namedDmVersion: 'pinned-reference' },
    { warningsAsErrors: true },
    { ignoreWarningCodes: ['unused_var'] },
  ]) {
    let nativeCalls = 0;
    let byondCalls = 0;
    await selectedCompiler('project.dme', options, async () => { byondCalls++; }, async () => {
      nativeCalls++;
      return { code: 0, combined: '' };
    });
    expect(nativeCalls).toBe(0);
    expect(byondCalls).toBe(1);
  }
});

test('shadow rejects unsupported configuration before either compiler executes', async () => {
  process.env.DQ_COMPILER = 'shadow';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  fs.mkdirSync('E:/dq-cache', { recursive: true });
  const ownedRoot = fs.mkdtempSync('E:/dq-cache/shadow-policy-fixture-');
  process.env.DQ_SHADOW_ROOT = ownedRoot;
  let nativeCalls = 0;
  let byondCalls = 0;
  try {
    await expect(selectedCompiler('project.dme', { warningsAsErrors: true }, async () => {
      byondCalls++;
    }, async () => {
      nativeCalls++;
      return { code: 0, combined: '' };
    })).rejects.toThrow('Native compiler does not support requested DreamMaker options: warningsAsErrors');
    expect(nativeCalls).toBe(0);
    expect(byondCalls).toBe(0);
  } finally {
    fs.rmSync(ownedRoot, { recursive: true, force: true });
  }
});

function structuralReport() {
  return {
    schema_version: 1, snapshot_id: 'current', traversal_complete: true,
    tool_complete: true, semantic_coverage: 'complete', complete: true,
    total_discrepancies: 0, unexplained_discrepancies: 0, uncovered: {},
    categories: Object.fromEntries(['type_set', 'type_headers', 'variable_defaults', 'procedure_table', 'procedure_flags', 'globals', 'strings_by_use', 'bytecode', 'other'].map(name => [name, { discrepancy_count: 0 }])),
  };
}
test('zero structural differences do not authenticate DreamMaker input closure', () => {
  expect(classifyShadowReport(structuralReport(), 'current').status).toBe('parity');
  const contract = shadowSnapshotContract();
  expect(contract.status).toBe('incomplete');
  expect(contract.reason).toContain('source/resource closure');
  expect(contract.reason).toContain('configuration receipt');
});
test('shadow requires full comparison coverage and zero discrepancies', () => {
  expect(classifyShadowReport(structuralReport(), 'current').status).toBe('parity');
  const differences = structuralReport();
  differences.categories.bytecode.discrepancy_count = 1;
  differences.total_discrepancies = 1;
  differences.unexplained_discrepancies = 1;
  expect(classifyShadowReport(differences, 'current').status).toBe('differences');
  differences.unexplained_discrepancies = 0;
  expect(classifyShadowReport(differences, 'current').status).toBe('differences');
  const incomplete = { ...structuralReport(), complete: false, semantic_coverage: 'incomplete', uncovered: { opaque_value: { occurrence_count: 1 } } };
  expect(classifyShadowReport(incomplete, 'current').status).toBe('incomplete');
  expect(classifyShadowReport({ ...structuralReport(), tool_complete: false }, 'current').status).toBe('incomplete');
});
test('shadow rejects malformed, contradictory and unrelated receipts', () => {
  expect(classifyShadowReport(structuralReport(), 'other').status).toBe('invalid_report');
  expect(classifyShadowReport({ schema_version: 1, snapshot_id: 'current' }, 'current').status).toBe('invalid_report');
  const missing = structuralReport();
  delete missing.categories.bytecode;
  expect(classifyShadowReport(missing, 'current').status).toBe('invalid_report');
  expect(classifyShadowReport({ ...structuralReport(), total_discrepancies: 1 }, 'current').status).toBe('invalid_report');
  expect(classifyShadowReport({ ...structuralReport(), total_discrepancies: -1 }, 'current').status).toBe('invalid_report');
  expect(classifyShadowReport({ ...structuralReport(), complete: false }, 'current').status).toBe('invalid_report');
  expect(classifyShadowReport({ ...structuralReport(), uncovered: { opaque_value: { occurrence_count: 1 } } }, 'current').status).toBe('invalid_report');
});
