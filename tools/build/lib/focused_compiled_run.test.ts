import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { beginCompilerReceipt, type CompilerProvenance } from './compiler_provenance';
import { captureFocusedCompiledOutput, loadFocusedCompiledOutput } from './focused_compiled_run';
import type { CompiledOutput } from './native_pair';

function digest(file: string) { return createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function fixture(native = false) {
  fs.mkdirSync('E:/dq-cache', { recursive: true });
  const root = fs.mkdtempSync('E:/dq-cache/focused-capture-fixture-');
  const compiler = path.join(root, native ? 'native.exe' : 'dm.exe');
  fs.writeFileSync(compiler, 'mock executable identity');
  const dmb = path.join(root, 'preserved.dmb'), rsc = path.join(root, 'preserved.rsc');
  fs.writeFileSync(dmb, 'compiled program'); fs.writeFileSync(rsc, 'compiled resources');
  const nativePair = native ? { pairId: '1'.repeat(32), dmbHash: '2'.repeat(32), rscHash: '3'.repeat(32), dmbBytes: fs.statSync(dmb).size, rscBytes: fs.statSync(rsc).size } : null;
  const provenance: CompilerProvenance = { requestedBackend: native ? 'native' : 'byond', actualBackend: native ? 'native' : 'byond',
    compiler: { executable: compiler, sha256: digest(compiler), version: native ? null : 516, build: native ? null : 1687 },
    orderedDefines: ['CBT', 'DEBUG', 'A=1', 'A=2'], fallback: null, nativePair };
  const output: CompiledOutput = native ? { kind: 'native_pair', compiler, store: root, outputProject: path.join(root, 'source.dme'), ...nativePair!, provenance }
    : { kind: 'conventional', backend: 'byond', dmb, rsc, provenance };
  const receipt = beginCompilerReceipt(root, output);
  const capture = captureFocusedCompiledOutput(receipt.file, output, dmb, rsc);
  const file = path.join(root, 'capture.json');
  const save = () => { fs.writeFileSync(file, JSON.stringify(capture)); return digest(file); };
  return { root, compiler, dmb, rsc, output, provenance, capture, file, receipt, save,
    close() { fs.rmSync(root, { recursive: true, force: true }); } };
}

test('explicit BYOND generation checks hosted copies and retains originals after mutable RSC runtime writes', () => {
  const f = fixture();
  try {
    const admitted = loadFocusedCompiledOutput(f.file, f.save(), 'byond', f.provenance.orderedDefines);
    expect(admitted.evidence.inputClosureAuthenticated).toBe(false);
    const dmb = path.join(f.root, 'hosted.dmb'), rsc = path.join(f.root, 'hosted.rsc');
    fs.copyFileSync(f.dmb, dmb); fs.copyFileSync(f.rsc, rsc);
    admitted.verifyHosted(dmb);
    fs.appendFileSync(rsc, 'legitimate runtime archive mutation');
    admitted.verifyRetained();
    expect(() => admitted.verifyHosted(dmb)).toThrow('hosted pair differs');
    expect(fs.readFileSync(f.rsc, 'utf8')).toBe('compiled resources');
  } finally { f.close(); }
});

test('explicit generation rejects missing pin, backend mismatch and reordered duplicate defines', () => {
  const f = fixture();
  try {
    const sha = f.save();
    expect(() => loadFocusedCompiledOutput(f.file, '', 'byond', f.provenance.orderedDefines)).toThrow('hash/size');
    expect(() => loadFocusedCompiledOutput(f.file, sha, 'native', f.provenance.orderedDefines)).toThrow('backend/ordered defines');
    expect(() => loadFocusedCompiledOutput(f.file, sha, 'byond', ['CBT', 'DEBUG', 'A=2', 'A=1'])).toThrow('backend/ordered defines');
    fs.appendFileSync(f.file, ' ');
    expect(() => loadFocusedCompiledOutput(f.file, sha, 'byond', f.provenance.orderedDefines)).toThrow('hash/size');
  } finally { f.close(); }
});

test('existing conventional files do not admit unknown or fallback compilation', () => {
  const f = fixture();
  try {
    f.provenance.fallback = 'internal_error_70';
    expect(() => captureFocusedCompiledOutput(f.receipt.file, f.output, f.dmb, f.rsc)).toThrow('non-fallback');
    f.provenance.fallback = null;
    f.provenance.compiler.sha256 = null;
    expect(() => captureFocusedCompiledOutput(f.receipt.file, f.output, f.dmb, f.rsc)).toThrow('observed');
  } finally { f.close(); }
});

test('compiler, retained pair and compilation evidence mutations fail closed', () => {
  const f = fixture();
  try {
    const admitted = loadFocusedCompiledOutput(f.file, f.save(), 'byond', f.provenance.orderedDefines);
    fs.appendFileSync(f.rsc, 'changed retained input');
    expect(() => admitted.verifyRetained()).toThrow('captured file changed');
    fs.writeFileSync(f.rsc, 'compiled resources');
    fs.appendFileSync(f.compiler, 'changed executable');
    expect(() => admitted.verifyRetained()).toThrow('executable changed');
    fs.writeFileSync(f.compiler, 'mock executable identity');
    const changed = JSON.parse(fs.readFileSync(f.receipt.file, 'utf8'));
    changed.compilation.compiler.build = 1688;
    fs.writeFileSync(f.receipt.file, JSON.stringify(changed));
    f.capture.compilationReceipt.sha256 = digest(f.receipt.file);
    f.capture.compilationReceipt.bytes = fs.statSync(f.receipt.file).size;
    expect(() => loadFocusedCompiledOutput(f.file, f.save(), 'byond', f.provenance.orderedDefines)).toThrow('receipt disagrees');
  } finally { f.close(); }
});

test('native replay retains native pair identity and rejects changed acquired bytes', () => {
  const f = fixture(true);
  try {
    const admitted = loadFocusedCompiledOutput(f.file, f.save(), 'native', f.provenance.orderedDefines);
    expect(admitted.output.kind).toBe('native_pair');
    const dmb = path.join(f.root, 'acquired.dmb'), rsc = path.join(f.root, 'acquired.rsc');
    fs.copyFileSync(f.dmb, dmb); fs.copyFileSync(f.rsc, rsc);
    admitted.verifyHosted(dmb);
    fs.writeFileSync(dmb, 'wrong acquired generation');
    expect(() => admitted.verifyHosted(dmb)).toThrow('hosted pair differs');
    if (f.output.kind !== 'native_pair') throw new Error('fixture requires native output');
    f.output.pairId = '4'.repeat(32);
    expect(() => loadFocusedCompiledOutput(f.file, f.save(), 'native', f.provenance.orderedDefines)).toThrow('generation differs');
  } finally { f.close(); }
});
