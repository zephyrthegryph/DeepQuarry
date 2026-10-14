import { test, expect } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { preserveFocusedOutput } from './preserve_focused_output';
const sha = (file: string) => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
test('issued conventional outputs preserve exact receipt and stable bytes without closure claim', async () => {
  const root = path.join('E:/dq-cache', 'focused-preservation-test-' + randomUUID());
  fs.mkdirSync(root);
  try {
    const compiler = path.join(root, 'compiler.exe'); fs.writeFileSync(compiler, 'pinned compiler');
    const dmb = path.join(root, 'probe.dmb'), rsc = path.join(root, 'probe.rsc');
    fs.writeFileSync(dmb, 'dmb'); fs.writeFileSync(rsc, 'rsc');
    const compilation = { requestedBackend: 'byond', actualBackend: 'byond', compiler: { executable: compiler, sha256: sha(compiler), version: 516, build: 1687 }, orderedDefines: ['UNIT_TESTS', 'A=1', 'A=2'], fallback: null, nativePair: null };
    const output = { kind: 'conventional', backend: 'byond', dmb, rsc, provenance: compilation };
    const attempt = path.join(root, 'attempt.json');
    fs.writeFileSync(attempt, JSON.stringify({ schema_version: 1, actual_backend: 'byond', pair: null, compilation, output, prepared_at: 'issued', finalized_at: 'finished' }));
    const preserved = await preserveFocusedOutput(attempt, sha(attempt), path.join(root, 'capture'));
    expect(preserved.sharedInputClosure).toBe(false);
    const capture = JSON.parse(fs.readFileSync(preserved.capture, 'utf8'));
    expect(capture.output.provenance).toEqual(compilation);
    expect(capture.output.dmb).toBe(capture.pair.dmb.path);
    expect(JSON.parse(fs.readFileSync(attempt, 'utf8')).output).toEqual(output);
    expect(capture.compilationReceipt.sha256).toBe(sha(attempt));
    expect(capture.pair.dmb.sha256).toBe(sha(dmb));
    expect(capture.pair.rsc.sha256).toBe(sha(rsc));
    expect((preserved.pairEvidence as any).invocation_generation_complete).toBe(false);
    await expect(preserveFocusedOutput(attempt, '0'.repeat(64), path.join(root, 'bad'))).rejects.toThrow('pin differs');
  } finally {
    for (const file of [path.join(root, 'capture/byond-captured.dmb'), path.join(root, 'capture/byond-captured.rsc')]) if (fs.existsSync(file)) fs.chmodSync(file, 0o666);
    fs.rmSync(root, { recursive: true });
  }
});
