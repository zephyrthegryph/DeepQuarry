/** Adapt the actual captured-root compiler pair through ordinary runtime issuers. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import Juke from '../../build/juke/index.js';
import { parseCompileResult, conventionalOutput, withCompiledOutput } from '../../build/lib/native_pair';
import { beginCompilerReceipt, byondProvenance, nativeProvenance, observedExecutable } from '../../build/lib/compiler_provenance';
import { captureFocusedCompiledOutput } from '../../build/lib/focused_compiled_run';

const [directory, expected] = process.argv.slice(2);
if (!directory || !/^[0-9a-f]{64}$/.test(expected ?? '')) throw new Error('capture directory and receipt SHA256 required');
const root = path.resolve(directory);
const hash = (file: string) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const receiptFile = path.join(root, 'focused-pair-receipt.json');
if (hash(receiptFile) !== expected) throw new Error('focused pair receipt changed');
const receipt = JSON.parse(fs.readFileSync(receiptFile, 'utf8'));
if (receipt.status !== 'passed' || receipt.kind !== 'focused_same_captured_roster_pair'
    || receipt.owned_child_cleanup?.reaped !== true) throw new Error('captured compiler children were not successfully reaped');
const sourcePin = JSON.parse(fs.readFileSync(receipt.pin, 'utf8'));
for (const pin of [...sourcePin.configuration_evidence, sourcePin.byond_version_evidence]) {
  if (hash(pin.path) !== pin.sha256) throw new Error('captured configuration evidence changed');
}
const version = JSON.parse(fs.readFileSync(sourcePin.byond_version_evidence.path, 'utf8'));
if (version.file_version !== '5.0.516.1687') throw new Error('unsupported captured BYOND version');
const evidence = JSON.parse(fs.readFileSync(path.join(root, 'configuration-evidence.json'), 'utf8'));
const defines: string[] = receipt.orderedDefines;
if (!Array.isArray(defines) || defines.some(value => typeof value !== 'string')) throw new Error('ordered defines missing');
for (const backend of ['byond', 'native'] as const) {
  const result = evidence.find((row: any) => row.producer === backend);
  if (!result || result.exit_code !== 0 || result.timeout !== false || result.reaped !== true) throw new Error('unsuccessful captured compiler');
  const identity = observedExecutable(result.command[0]);
  if (identity.sha256 !== result.compiler_sha256) throw new Error('captured compiler executable changed');
  const owned = path.join(root, backend + '-runtime-capture');
  fs.mkdirSync(owned);
  let output;
  if (backend === 'byond') {
    for (const suffix of ['.dmb', '.rsc']) {
      if (hash(path.join(root, 'byond', 'world' + suffix)) !== result[suffix + '_sha256']) throw new Error('captured BYOND output changed');
    }
    output = conventionalOutput(path.join(root, 'byond', 'world.dme'));
    output.provenance = byondProvenance('byond', defines, { invocation: {
      command: result.command, version: 516, build: 1687,
      compilerIdentity: { status: 'observed', executable: identity.executable, sha256: identity.sha256! },
    } });
  } else {
    const currentResult = JSON.parse(fs.readFileSync(path.join(root, 'native-result.json'), 'utf8'));
    output = parseCompileResult(currentResult, identity.executable, path.join(root, 'native', 'comparison.dme'));
    output.provenance = nativeProvenance(output, defines, identity);
  }
  await withCompiledOutput(output, Juke.exec, async acquired => {
    const dmb = backend === 'byond' ? acquired : path.join(owned, 'world.dmb');
    const rsc = dmb.replace(/\.dmb$/i, '.rsc');
    if (backend === 'native') {
      fs.copyFileSync(acquired, dmb, fs.constants.COPYFILE_EXCL);
      fs.copyFileSync(acquired.replace(/\.dmb$/i, '.rsc'), rsc, fs.constants.COPYFILE_EXCL);
    }
    const attempt = beginCompilerReceipt(owned, output);
    const capture = captureFocusedCompiledOutput(attempt.file, output, dmb, rsc);
    const file = path.join(owned, 'capture.json');
    fs.writeFileSync(file, JSON.stringify(capture, null, 2), { flag: 'wx' });
    console.log(JSON.stringify({ backend, capture: file, sha256: hash(file) }));
  });
}
if (hash(receiptFile) !== expected) throw new Error('focused pair receipt changed during adaptation');
