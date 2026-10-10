import { afterEach, expect, test } from 'bun:test';
import { classifyShadowReport, compilerCacheIdentity, compilerMode, selectedCompiler, shadowSnapshotContract } from './compiler_selection';
import Juke from '../juke/index.js';
import { observeDreamMakerIdentity, type PreparedDreamMaker } from './byond';
import fs from 'node:fs';
import { captureShadowOutputPair } from './shadow_output';
import path from 'node:path';
const originalEnvironment = { ...process.env };
afterEach(() => {
  for (const name of ['DQ_COMPILER', 'DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE', 'DQ_NATIVE_WORKERS', 'DQ_SHADOW_ROOT', 'DQ_DMB_INSPECT', 'DQ_NATIVE_RUN_ROOT']) {
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
    const receipt = args[args.indexOf('--compile-result-file') + 1];
    fs.writeFileSync(receipt, JSON.stringify({ schema_version: 1, kind: 'native_pair', store: path.resolve('E:/dq-cache/fixture-store'), pair_id: '1'.repeat(32), dmb_hash: '2'.repeat(32), rsc_hash: '3'.repeat(32), dmb_bytes: 1, rsc_bytes: 2, output_project: path.resolve('project.dme') }));
    return { code: 0, combined: '', stdout: '', stderr: '', signal: null };
  };
  let byondCalls = 0;
  const output = await selectedCompiler('project.dme', { defines: ['CITESTING=1'] }, async () => { byondCalls++; }, execute);
  expect(output.kind).toBe('native_pair');
  expect(output.provenance?.actualBackend).toBe('native');
  expect(output.provenance?.orderedDefines).toEqual(['CITESTING=1']);
  expect(output.provenance?.nativePair?.pairId).toBe('1'.repeat(32));
  expect(byondCalls).toBe(0);
  expect(recorded).toContain('-DCITESTING=1');
  expect(recorded).toContain('6');
  expect(recorded).not.toContain('--artifact-directory');
  expect(recorded).toContain('--compile-result-file');
});
test('native infrastructure status never falls back', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  const execute = async () => ({ code: 1, combined: 'diagnostic', stdout: '', stderr: 'diagnostic', signal: null });
  let byondCalls = 0;
  const failure = await selectedCompiler('project.dme', {}, async () => { byondCalls++; }, execute).then(() => null, error => error);
  expect(failure).toBeInstanceOf(Juke.ExitCode);
  expect(failure.code).toBe(1);
  expect(byondCalls).toBe(0);
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

test('successful native status without machine pair result never falls back', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  let fallback = 0;
  await expect(selectedCompiler('project.dme', {}, async () => { fallback++; }, async () => ({ code: 0, combined: '' }))).rejects.toThrow('without an authenticated pair result');
  expect(fallback).toBe(0);
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
    await expect(selectedCompiler('project.dme', options, async () => { byondCalls++; }, async () => {
      nativeCalls++;
      return { code: 0, combined: '' };
    })).rejects.toThrow('Native compiler does not support requested DreamMaker options:');
    expect(nativeCalls).toBe(0);
    expect(byondCalls).toBe(0);
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


test('native internal status 70 falls back once and propagates BYOND failure', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  let calls = 0;
  const expected = new Juke.ExitCode(37);
  const failure = await selectedCompiler('project.dme', {}, async () => {
    calls++;
    throw expected;
  }, async () => ({ code: 70, combined: 'native unsupported' })).then(() => null, error => error);
  expect(calls).toBe(1);
  expect(failure).toBe(expected);
  expect(failure.code).toBe(37);
});

test('successful internal fallback records BYOND as the actual test compiler', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  const output = await selectedCompiler('project.dme', { defines: ['DEBUG', 'X=1', 'X=2'] }, async () => ({ invocation: {
    command: ['dm', 'project.dme'], version: 516, build: 1687,
  } }), async () => ({ code: 70, combined: 'internal' }));
  expect(output.kind).toBe('conventional');
  expect(output.provenance?.requestedBackend).toBe('native');
  expect(output.provenance?.actualBackend).toBe('byond');
  expect(output.provenance?.fallback).toBe('internal_error_70');
  expect(output.provenance?.orderedDefines).toEqual(['DEBUG', 'X=1', 'X=2']);
});

test('native setup and transport failures preserve errors without fallback', async () => {
  process.env.DQ_COMPILER = 'native';
  let calls = 0;
  let executions = 0;
  delete process.env.DQ_NATIVE_COMPILER;
  delete process.env.DQ_NATIVE_ENGINE_TEMPLATE;
  await expect(selectedCompiler('project.dme', {}, async () => { calls++; }, async () => {
    executions++;
    return { code: 70, combined: '' };
  })).rejects.toThrow('requires DQ_NATIVE_COMPILER and DQ_NATIVE_ENGINE_TEMPLATE');
  expect(executions).toBe(0);
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  const transport = new Error('cannot start native compiler');
  const failure = await selectedCompiler('project.dme', {}, async () => { calls++; }, async () => {
    throw transport;
  }).then(() => null, error => error);
  expect(failure).toBe(transport);
  expect(calls).toBe(0);
});

test('typed and unknown native statuses preserve exact exit and never fall back', async () => {
  process.env.DQ_COMPILER = 'native';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  for (const code of [2, 64, 75, 3, 42, 124]) {
    let calls = 0;
    const failure = await selectedCompiler('project.dme', {}, async () => { calls++; },
      async () => ({ code, combined: 'native diagnostic' })).then(() => null, error => error);
    expect(failure).toBeInstanceOf(Juke.ExitCode);
    expect(failure.code).toBe(code);
    expect(calls).toBe(0);
  }
});

test('shadow inspects acquired generation through both children and still rejects unproven closure', async () => {
  fs.mkdirSync('E:/dq-cache', { recursive: true });
  const ownedRoot = fs.mkdtempSync('E:/dq-cache/shadow-pair-fixture-');
  process.env.DQ_COMPILER = 'shadow';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  process.env.DQ_DMB_INSPECT = 'fixture-inspector';
  process.env.DQ_SHADOW_ROOT = path.join(ownedRoot, 'shadow');
  process.env.DQ_NATIVE_RUN_ROOT = path.join(ownedRoot, 'run');
  const project = path.join(ownedRoot, 'probe.dme');
  fs.writeFileSync(project, '// fixture');
  const order: string[] = [];
  const prepared: PreparedDreamMaker = { executable: 'dm.exe',
    identity: { status: 'unknown', executable: 'dm.exe', reason: 'test PATH fallback' },
    version: 516, build: 1687, defines: [], namedDmVersion: null };
  let slot = '';
  let inspected = 0;
  let acquisition = 0;
  const execute = async (_executable: string, args: string[]) => {
    if (args[0] === 'compile') {
      order.push('native');
      const artifacts = args[args.indexOf('--artifact-directory') + 1];
      // These mutable conventional files deliberately differ from the acquired pair.
      fs.writeFileSync(path.join(artifacts, 'probe.dmb'), 'mutable');
      fs.writeFileSync(path.join(artifacts, 'probe.rsc'), 'mutable');
      fs.writeFileSync(args[args.indexOf('--compile-result-file') + 1], JSON.stringify({
        schema_version: 1, kind: 'native_pair', store: path.join(artifacts, 'store'),
        pair_id: '1'.repeat(32), dmb_hash: '2'.repeat(32), rsc_hash: '3'.repeat(32),
        dmb_bytes: 1, rsc_bytes: 2, output_project: path.join(artifacts, 'probe.dme'),
      }));
    } else if (args[0] === 'acquire') {
      acquisition++;
      slot = path.join(args[args.indexOf('--slots') + 1], 'owned-slot');
      fs.mkdirSync(slot);
      fs.writeFileSync(path.join(slot, 'deepquarry.dmb'), 'D');
      fs.writeFileSync(path.join(slot, 'deepquarry.rsc'), 'RS');
      fs.writeFileSync(path.join(slot, 'slot-complete'), '1'.repeat(32));
      fs.writeFileSync(args[args.indexOf('--result-file') + 1], JSON.stringify({
        schema_version: 1, kind: 'acquired_pair', store: args[args.indexOf('--output-store') + 1],
        pair_id: '1'.repeat(32), dmb_hash: '2'.repeat(32), rsc_hash: '3'.repeat(32),
        dmb_bytes: 1, rsc_bytes: 2, slot, dmb: path.join(slot, 'deepquarry.dmb'),
        rsc: path.join(slot, 'deepquarry.rsc'),
      }));
    } else {
      inspected++;
      const resource = args[0] === 'rsc-diff';
      expect(args[2]).toBe(path.join(slot, resource ? 'deepquarry.rsc' : 'deepquarry.dmb'));
      expect(fs.readFileSync(args[2], 'utf8')).toBe(resource ? 'RS' : 'D');
      expect(fs.existsSync(path.join(slot, 'deepquarry.dmb'))).toBe(true);
      const report = resource ? {
        schema_version: 1, snapshot_id: args[4], complete: true,
        expected_resources: 1, actual_resources: 1, differences: 0, unknown_wrappers: 0, examples: [],
      } : { ...structuralReport(), snapshot_id: args[4] };
      fs.writeFileSync(args[3], JSON.stringify(report));
    }
    return { code: 0, combined: '' };
  };
  try {
    await expect(selectedCompiler(project, {}, async (_captured, compiler) => {
      order.push('byond');
      expect(compiler).toBe(prepared);
      fs.writeFileSync(project.replace(/\.dme$/, '.dmb'), 'D');
      fs.writeFileSync(project.replace(/\.dme$/, '.rsc'), 'RS');
    }, execute, async () => { order.push('prepare'); return prepared; })).rejects.toBeInstanceOf(Juke.ExitCode);
    expect(order).toEqual(['prepare', 'native', 'byond']);
    expect(acquisition).toBe(1);
    expect(inspected).toBe(2);
    expect(fs.existsSync(slot)).toBe(false);
    const artifact = path.join(process.env.DQ_SHADOW_ROOT!, fs.readdirSync(process.env.DQ_SHADOW_ROOT!)[0]);
    const admission = JSON.parse(fs.readFileSync(path.join(artifact, 'structural-admission.json'), 'utf8'));
    expect(admission.structuralAdmission.status).toBe('parity');
    expect(admission.resourceAdmission.status).toBe('parity');
    expect(admission.status).toBe('incomplete');
  } finally {
    fs.rmSync(ownedRoot, { recursive: true, force: true });
  }
});

test('DreamMaker identity hashes only an explicit resolved executable and marks PATH lookup unknown', () => {
  fs.mkdirSync('E:/dq-cache', { recursive: true });
  const owned = fs.mkdtempSync('E:/dq-cache/byond-identity-fixture-');
  try {
    const executable = path.join(owned, 'dm.exe');
    fs.writeFileSync(executable, 'actual binary bytes');
    const first = observeDreamMakerIdentity(executable);
    expect(first.status).toBe('observed');
    if (first.status !== 'observed') throw new Error('expected observed explicit path');
    expect(first.executable).toBe(fs.realpathSync.native(executable));
    expect(first.sha256).toMatch(/^[a-f0-9]{64}$/);
    fs.writeFileSync(executable, 'replaced binary');
    const changed = observeDreamMakerIdentity(executable);
    expect(changed.status).toBe('observed');
    if (changed.status === 'observed') expect(changed.sha256).not.toBe(first.sha256);
    const unresolved = observeDreamMakerIdentity('dm.exe');
    expect(unresolved.status).toBe('unknown');
    expect('sha256' in unresolved).toBe(false);
    expect(() => observeDreamMakerIdentity(path.join(owned, 'missing.exe'))).toThrow();
  } finally { fs.rmSync(owned, { recursive: true, force: true }); }
});

test('shadow unsupported policy rejects before prepared DreamMaker callback', async () => {
  process.env.DQ_COMPILER = 'shadow';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  let prepared = 0;
  let executed = 0;
  await expect(selectedCompiler('project.dme', { warningsAsErrors: true }, async () => {
    throw new Error('must not compile BYOND');
  }, async () => { executed++; return { code: 0, combined: '' }; }, async () => {
    prepared++;
    throw new Error('must not prepare BYOND');
  })).rejects.toThrow('Native compiler does not support requested DreamMaker options:');
  expect(prepared).toBe(0);
  expect(executed).toBe(0);
});


test('shadow cancellation preserves status and evidence without BYOND or inspector', async () => {
  process.env.DQ_COMPILER = 'shadow';
  process.env.DQ_NATIVE_COMPILER = 'native-compiler';
  process.env.DQ_NATIVE_ENGINE_TEMPLATE = 'engine-template';
  process.env.DQ_DMB_INSPECT = 'fixture-inspector';
  fs.mkdirSync('E:/dq-cache', { recursive: true });
  const ownedRoot = fs.mkdtempSync('E:/dq-cache/shadow-cancel-fixture-');
  process.env.DQ_SHADOW_ROOT = ownedRoot;
  let byondCalls = 0;
  const children: string[] = [];
  try {
    const failure = await selectedCompiler('project.dme', {}, async () => { byondCalls++; },
      async executable => {
        children.push(executable);
        return { code: 75, combined: 'native request cancelled by newer request' };
      }).then(() => null, error => error);
    expect(failure).toBeInstanceOf(Juke.ExitCode);
    expect(failure.code).toBe(75);
    expect(byondCalls).toBe(0);
    expect(children).toEqual(['native-compiler']);
    const artifacts = fs.readdirSync(ownedRoot).filter(name => name.startsWith('shadow-'));
    expect(artifacts).toHaveLength(1);
    expect(fs.readFileSync(path.join(ownedRoot, artifacts[0], 'native.log'), 'utf8'))
      .toBe('native request cancelled by newer request');
  } finally {
    fs.rmSync(ownedRoot, { recursive: true, force: true });
  }
});


test('shadow output capture freezes stable bytes without invocation authority and rejects races', () => {
  const directory = fs.mkdtempSync('E:/dq-cache/shadow-output-fixture-');
  const project = path.join(directory, 'probe.dme');
  const copies = path.join(directory, 'captured');
  fs.mkdirSync(copies);
  fs.writeFileSync(project.replace('.dme', '.dmb'), 'original DMB');
  fs.writeFileSync(project.replace('.dme', '.rsc'), 'original RSC');
  try {
    const captured = captureShadowOutputPair(project, copies);
    expect(captured.proof.stable_output_pair).toBe(true);
    expect(captured.proof.invocation_generation_complete).toBe(false);
    fs.writeFileSync(project.replace('.dme', '.dmb'), 'later DMB');
    expect(fs.readFileSync(captured.dmb, 'utf8')).toBe('original DMB');
    expect(() => captureShadowOutputPair(project, copies)).toThrow();
    const raced = path.join(directory, 'raced');
    fs.mkdirSync(raced);
    expect(() => captureShadowOutputPair(project, raced, () => {
      fs.writeFileSync(project.replace('.dme', '.rsc'), 'changed RSC');
    })).toThrow('changed during capture');
    expect(fs.existsSync(path.join(raced, 'byond-captured.dmb'))).toBe(false);
  } finally {
    for (const file of ['byond-captured.dmb', 'byond-captured.rsc']) {
      const copy = path.join(copies, file);
      if (fs.existsSync(copy)) fs.chmodSync(copy, 0o666);
    }
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
