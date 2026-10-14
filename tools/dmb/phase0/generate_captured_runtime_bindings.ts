/** Run the ordinary bindings producer only in an explicitly new private root. */
import fs from 'node:fs';
import path from 'node:path';
import { generateVerdigrisBindings } from '../../build/lib/verdigris_bindings';
const [directory] = process.argv.slice(2);
if (!directory) throw new Error('private staged source root required');
const root = path.resolve(directory);
if (!root.toLowerCase().startsWith('e:\\dq-cache\\') ||
    root.toLowerCase().includes('recovered-baseline-20261010')) {
  throw new Error('requires a NEW E: private source root, never original baseline');
}
for (let current = root; ; current = path.dirname(current)) {
  const stat = fs.lstatSync(current);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('staged root has an unsafe directory');
  if (current === path.dirname(current)) break;
}
const written = generateVerdigrisBindings(root, false);
if (generateVerdigrisBindings(root, true).length) throw new Error('ordinary binding check remains stale');
console.log(JSON.stringify({ producer: 'generateVerdigrisBindings', sourceRoot: root,
  written, historicalSnapshotEquivalent: false, inputClosureAuthenticated: false }));
