import { expect, test } from 'bun:test';
import path from 'node:path';
import { parseNativePublicationProof } from './native_publication_proof';
import { parseCompileResult } from './native_pair';
import { nativeProvenance } from './compiler_provenance';

const pair = '1'.repeat(32);
const store = path.resolve('E:/dq-cache/proof-fixture');
const proof = { schema_version: 1, kind: 'native_publication_inputs', native_inputs_admitted: true,
  shared_input_closure_complete: false, pair_id: pair,
  document: path.join(store, 'publication-proofs', 'proof.json'),
  document_bytes: 512, document_xxh3_128: '2'.repeat(32), snapshot_bytes: 128,
  snapshot_xxh3_128: '3'.repeat(32) };

test('optional native proof retains native-only scope and exact generation', () => {
  expect(parseNativePublicationProof(undefined, pair, store)).toBeUndefined();
  expect(parseNativePublicationProof(proof, pair, store)).toEqual(proof);
  expect(() => parseNativePublicationProof({ ...proof, pair_id: '0'.repeat(32) }, pair, store)).toThrow('generation');
  expect(() => parseNativePublicationProof({ ...proof, shared_input_closure_complete: true }, pair, store)).toThrow('scope');
});

test('versioned native target configuration preserves admitted defines and rejects invented completeness', () => {
  const target = { schema_version: 1, version: 516, build: 1687, engine_template_sha256: 'a'.repeat(64),
    effective_defines: { DM_VERSION: '516', DM_BUILD: '1687', FEATURE: '1' }, implicit_predefines_complete: false };
  expect(parseNativePublicationProof({ ...proof, target_configuration: target }, pair, store)?.target_configuration).toEqual(target);
  for (const changed of [{ ...target, build: 9999 }, { ...target, implicit_predefines_complete: true },
    { ...target, effective_defines: { DM_VERSION: '516', DM_BUILD: '9999' } }]) {
    expect(() => parseNativePublicationProof({ ...proof, target_configuration: changed }, pair, store)).toThrow();
  }
});

test('proof metadata rejects malformed sizes, digests and escaped document paths', () => {
  for (const bytes of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    expect(() => parseNativePublicationProof({ ...proof, document_bytes: bytes }, pair, store)).toThrow('document_bytes');
  }
  expect(() => parseNativePublicationProof({ ...proof, snapshot_xxh3_128: 'XYZ' }, pair, store)).toThrow('snapshot_xxh3_128');
  expect(() => parseNativePublicationProof({ ...proof, document: path.join(store, 'other', 'proof.json') }, pair, store)).toThrow('escaped');
  expect(() => parseNativePublicationProof(null, pair, store)).toThrow('Invalid');
});

test('compile receipt carries the same native admission reference into test provenance', () => {
  const project = path.resolve('proof-fixture.dme');
  const output = parseCompileResult({ schema_version: 1, kind: 'native_pair', store,
    output_project: project, pair_id: pair, dmb_hash: '4'.repeat(32), rsc_hash: '5'.repeat(32),
    dmb_bytes: 10, rsc_bytes: 20, publication_proof: proof }, 'compiler.exe', project);
  const provenance = nativeProvenance(output, ['UNIT_TESTS'], { executable: 'compiler.exe', sha256: null });
  expect(provenance.nativePublicationProof).toEqual(proof);
  expect(provenance.nativePublicationProof?.shared_input_closure_complete).toBe(false);
  expect(provenance.compiler.version).toBeNull();
});
