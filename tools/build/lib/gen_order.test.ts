// Run with `bun test tools/build/lib/gen_order.test.ts`.
// `analyze gen` reads the gitignored code/__defines/verdigris/_bindings.dm; with the bindings missing or stale it writes a different
// code/_generated/reads.dm (three `nameof(vg_entity)` reads absent). The build must therefore order gen after the bindings target.
import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';

test('GenTarget depends on VerdigrisBindingsCheckTarget', () => {
  const src = fs.readFileSync(path.join(import.meta.dir, '..', 'build.ts'), 'utf-8');
  const m = /export const GenTarget = new Juke\.Target\(\{\s*dependsOn: \[([^\]]*)\]/.exec(src);
  expect(m).not.toBeNull();
  const deps = (m?.[1] ?? '').split(',').map((d) => d.trim());
  expect(deps).toContain('VerdigrisBindingsCheckTarget');
});
