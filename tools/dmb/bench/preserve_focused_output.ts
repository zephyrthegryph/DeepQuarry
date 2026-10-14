/** Preserve an issued focused generation; never certifies shared input closure. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { captureFocusedCompiledOutput } from '../../build/lib/focused_compiled_run';
import { assertDirectoryChain, parseAcquiredResult, type CompiledOutput } from '../../build/lib/native_pair';
import { captureShadowOutputPair } from '../../build/lib/shadow_output';

export async function preserveFocusedOutput(attempt: string, expected: string, directory: string) {
  const digest = (file: string) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  assertDirectoryChain(path.dirname(attempt));
  if (!fs.lstatSync(attempt).isFile() || fs.lstatSync(attempt).size > 65536 || !/^[0-9a-f]{64}$/.test(expected) || digest(attempt) !== expected) throw new Error('Compiler attempt pin differs.');
  const value = JSON.parse(fs.readFileSync(attempt, 'utf8'));
  const output: CompiledOutput = value.output;
  if (!output || !value.prepared_at || !value.finalized_at || output.provenance?.fallback !== null || JSON.stringify(output.provenance) !== JSON.stringify(value.compilation)) throw new Error('Missing successful issued compiled output.');
  const compiler = output.provenance!.compiler;
  if (!compiler.executable || !compiler.sha256 || digest(compiler.executable) !== compiler.sha256 || output.kind === 'native_pair' && output.compiler !== compiler.executable) throw new Error('Issued compiler identity changed.');
  const root = path.resolve('E:/dq-cache');
  const owned = path.resolve(directory);
  const relative = path.relative(root, owned);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('Capture must be below owned E cache.');
  assertDirectoryChain(path.dirname(owned));
  fs.mkdirSync(owned); // Exclusive; partial evidence remains owned on failure.
  let dmb: string, rsc: string, pairEvidence: unknown;
  if (output.kind === 'native_pair') {
    const result = path.join(owned, 'acquire.json');
    const process = Bun.spawn([output.compiler, 'acquire', '--output-store', output.store, '--pair-id', output.pairId, '--slots', owned, '--result-file', result], { stdout: 'inherit', stderr: 'inherit' });
    if (await process.exited !== 0) throw new Error('Ordinary native acquisition failed.');
    const acquired = parseAcquiredResult(JSON.parse(fs.readFileSync(result, 'utf8')), output, owned);
    dmb = acquired.dmb; rsc = acquired.rsc;
    pairEvidence = { kind: 'issued_native_acquisition', receipt: result, sha256: digest(result), pairId: acquired.pairId };
  } else {
    if (path.extname(output.dmb).toLowerCase() !== '.dmb' || output.rsc !== output.dmb.replace(/\.dmb$/i, '.rsc')) throw new Error('Conventional pair paths differ.');
    const stable = captureShadowOutputPair(output.dmb.replace(/\.dmb$/i, '.dme'), owned);
    dmb = stable.dmb; rsc = stable.rsc; pairEvidence = stable.proof;
  }
  if (digest(attempt) !== expected) throw new Error('Compiler attempt changed during preservation.');
  // Conventional replay names the preserved copies; original paths remain in the pinned attempt DTO.
  const capturedOutput: CompiledOutput = output.kind === 'conventional' ? { ...output, dmb, rsc } : output;
  const capture = captureFocusedCompiledOutput(attempt, capturedOutput, dmb, rsc);
  for (const file of [dmb, rsc]) fs.chmodSync(file, 0o444);
  const file = path.join(owned, 'capture.json');
  fs.writeFileSync(file, JSON.stringify(capture, null, 2) + '\n', { flag: 'wx' });
  return { capture: file, sha256: digest(file), pairEvidence, sharedInputClosure: false, inputClosureAuthenticated: false };
}
if (import.meta.main) {
  const [attempt, expected, directory] = process.argv.slice(2);
  if (!attempt || !expected || !directory) throw new Error('ATTEMPT SHA256 OWNED_DIRECTORY required');
  const preserved = await preserveFocusedOutput(attempt, expected, directory);
  fs.writeFileSync(path.join(directory, 'preservation.json'), JSON.stringify(preserved, null, 2) + '\n', { flag: 'wx' });
}
