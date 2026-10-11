/** Explicit same-generation focused runtime replay, never current-source admission.
 * The caller pins this capture and its successful compilation evidence. Both
 * hosted artifacts are checked before DD; writable runtime copies may change.
 * Source/resource closure remains unauthenticated, including after a clean run.
 * Issue with captureFocusedCompiledOutput(existingAttempt, output, dmb, rsc),
 * write its JSON to a fresh owned file, and explicitly pin that file's SHA256.
 * Run through build.sh dm-test --focus=<test> --focused-compiled-output=<file>
 * --focused-compiled-output-sha256=<sha> with the original backend/defines.
 * Preparation is not rerun: existing generated assets, map bounds and the
 * current ABI-checked Verdigris library must already be present for runtime.
 */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { assertDirectoryChain, parseCompileResult, type CompiledOutput } from './native_pair';
import { CompilerProvenanceError, type CompilerProvenance } from './compiler_provenance';

const HEX = /^[0-9a-f]{64}$/;
type FilePin = { path: string; sha256: string; bytes: number };
export type FocusedCompiledCapture = {
  schema: 1; kind: 'explicit_focused_compiled_output'; inputClosureAuthenticated: false;
  compilationReceipt: FilePin; output: CompiledOutput;
  pair: { dmb: FilePin; rsc: FilePin };
};
function fail(message: string): never { throw new CompilerProvenanceError(message); }
function filePin(file: string): FilePin {
  if (!path.isAbsolute(file)) fail('Focused capture requires absolute paths.');
  assertDirectoryChain(path.dirname(file));
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) fail('Focused capture requires regular files.');
  const descriptor = fs.openSync(file, 'r');
  try {
    const before = fs.fstatSync(descriptor);
    if (before.size > 2 * 1024 * 1024 * 1024) fail('Focused artifact exceeds 2GiB bound.');
    const hash = createHash('sha256');
    const buffer = Buffer.allocUnsafe(1024 * 1024);
    let bytes = 0;
    for (;;) {
      const length = fs.readSync(descriptor, buffer, 0, buffer.length, null);
      if (!length) break;
      bytes += length;
      if (bytes > before.size) fail('Focused artifact grew during hashing.');
      hash.update(buffer.subarray(0, length));
    }
    const after = fs.fstatSync(descriptor);
    if (bytes !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) fail('Focused artifact changed during hashing.');
    return { path: path.resolve(file), sha256: hash.digest('hex'), bytes };
  } finally { fs.closeSync(descriptor); }
}
function verify(pin: FilePin): void {
  if (!pin || !HEX.test(pin.sha256) || !Number.isSafeInteger(pin.bytes) || pin.bytes < 0) fail('Invalid focused file pin.');
  const actual = filePin(pin.path);
  if (actual.sha256 !== pin.sha256 || actual.bytes !== pin.bytes) fail(`Focused captured file changed: ${pin.path}`);
}
function json(file: string, expected?: string): { value: any; pin: FilePin } {
  const pin = filePin(file);
  if (pin.bytes > 1024 * 1024 || expected !== undefined && (!HEX.test(expected) || pin.sha256 !== expected)) fail('Focused capture JSON hash/size differs.');
  const bytes = fs.readFileSync(file);
  if (createHash('sha256').update(bytes).digest('hex') !== pin.sha256) fail('Focused capture JSON changed while reading.');
  return { value: JSON.parse(bytes.toString('utf8')), pin };
}
function provenance(output: CompiledOutput): CompilerProvenance {
  const value = output.provenance;
  if (!value || value.fallback !== null || value.requestedBackend !== value.actualBackend
      || !['byond', 'native'].includes(value.actualBackend) || !Array.isArray(value.orderedDefines)
      || !value.orderedDefines.every(item => typeof item === 'string')
      || !value.compiler || !value.compiler.executable || !HEX.test(value.compiler.sha256 ?? '')) fail('Focused replay requires observed, non-fallback compiler provenance.');
  const executable = filePin(value.compiler.executable);
  if (executable.sha256 !== value.compiler.sha256) fail('Focused compiler executable changed.');
  if (value.actualBackend === 'byond') {
    if (output.kind !== 'conventional' || output.backend !== 'byond' || value.nativePair != null
        || !Number.isInteger(value.compiler.version) || !Number.isInteger(value.compiler.build)
        || value.compiler.version! <= 0 || value.compiler.build! <= 0) fail('Focused BYOND capture lacks compiler version or contains native output.');
  } else {
    if (output.kind !== 'native_pair' || output.compiler !== value.compiler.executable || !value.nativePair) fail('Focused native capture lacks its exact generation.');
    const parsed = parseCompileResult({ schema_version: 1, kind: 'native_pair', output_project: output.outputProject,
      store: output.store, pair_id: output.pairId, dmb_hash: output.dmbHash, rsc_hash: output.rscHash,
      dmb_bytes: output.dmbBytes, rsc_bytes: output.rscBytes, publication_proof: output.publicationProof }, output.compiler, output.outputProject);
    assertDirectoryChain(parsed.store);
    for (const field of ['pairId', 'dmbHash', 'rscHash', 'dmbBytes', 'rscBytes'] as const) {
      if (parsed[field] !== value.nativePair[field]) fail('Focused native generation differs from compilation.');
    }
    if (JSON.stringify(parsed.publicationProof) !== JSON.stringify(value.nativePublicationProof)) fail('Focused native publication proof differs.');
  }
  return value;
}
function validate(capture: FocusedCompiledCapture): CompilerProvenance {
  if (!capture || capture.schema !== 1 || capture.kind !== 'explicit_focused_compiled_output' || capture.inputClosureAuthenticated !== false) fail('Unsupported focused capture scope.');
  const compilation = provenance(capture.output);
  verify(capture.compilationReceipt);
  const receipt = json(capture.compilationReceipt.path, capture.compilationReceipt.sha256).value;
  if (receipt.schema_version !== 1 || receipt.actual_backend !== compilation.actualBackend
      || JSON.stringify(receipt.compilation) !== JSON.stringify(compilation)) fail('Focused compilation receipt disagrees with captured output.');
  const expectedPair = capture.output.kind === 'native_pair' ? compilation.nativePair : null;
  if (JSON.stringify(receipt.pair) !== JSON.stringify(expectedPair)) fail('Focused compilation receipt pair differs.');
  if (!capture.pair) fail('Focused capture lacks artifact pins.');
  verify(capture.pair.dmb); verify(capture.pair.rsc);
  if (capture.output.kind === 'conventional') {
    if (path.resolve(capture.output.dmb) !== capture.pair.dmb.path || path.resolve(capture.output.rsc) !== capture.pair.rsc.path) fail('Focused conventional output differs from pinned artifacts.');
  } else if (capture.output.dmbBytes !== capture.pair.dmb.bytes || capture.output.rscBytes !== capture.pair.rsc.bytes) fail('Focused native artifact sizes differ.');
  return compilation;
}
/** Issue only from an existing compiler-attempt receipt and preserved outputs.
 * Native paths must be copies acquired by the ordinary compiler acquire API.
 * This does not compile, acquire, or infer a backend from artifact filenames.
 */
export function captureFocusedCompiledOutput(compilationReceipt: string, output: CompiledOutput, dmb: string, rsc: string): FocusedCompiledCapture {
  const capture: FocusedCompiledCapture = { schema: 1, kind: 'explicit_focused_compiled_output', inputClosureAuthenticated: false,
    compilationReceipt: filePin(compilationReceipt), output, pair: { dmb: filePin(dmb), rsc: filePin(rsc) } };
  validate(capture);
  return capture;
}
/** External expected SHA is mandatory: existence of conventional files is never admission. */
export function loadFocusedCompiledOutput(file: string, expectedSha256: string, backend: 'byond' | 'native' | 'shadow', defines: readonly string[]) {
  const admitted = json(path.resolve(file), expectedSha256);
  const capture = admitted.value as FocusedCompiledCapture;
  const compilation = validate(capture);
  if (backend !== compilation.requestedBackend || JSON.stringify(defines) !== JSON.stringify(compilation.orderedDefines)) fail('Focused replay backend/ordered defines differ.');
  return { output: capture.output,
    evidence: { kind: capture.kind, receipt: admitted.pin, inputClosureAuthenticated: false as const },
    verifyHosted(dmb: string) {
      validate(capture);
      const rsc = dmb.replace(/\.dmb$/i, '.rsc');
      if (rsc === dmb) fail('Focused hosted artifact is not a DMB.');
      const actualDmb = filePin(path.resolve(dmb)), actualRsc = filePin(path.resolve(rsc));
      if (actualDmb.sha256 !== capture.pair.dmb.sha256 || actualDmb.bytes !== capture.pair.dmb.bytes
          || actualRsc.sha256 !== capture.pair.rsc.sha256 || actualRsc.bytes !== capture.pair.rsc.bytes) fail('Focused hosted pair differs from captured compilation.');
      validate(capture);
    },
    verifyRetained() { validate(capture); },
  };
}
