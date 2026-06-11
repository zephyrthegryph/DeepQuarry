import { mkdirSync } from 'node:fs';
import Juke from '../juke/index.js';

// Tracks which node_modules folders we've already ensured, keyed by directory.
// A single shared boolean used to live here, so whichever of bun()/bunRoot() ran
// first marked the flag and the other skipped creating its OWN node_modules — on a
// clean build that left the root or tgui install operating without its folder
// prepared and made the parallel installs flaky. Keep the bookkeeping per-directory.
const ensuredFolders = new Set<string>();

function ensureNodeModules(dir: string) {
  if (ensuredFolders.has(dir)) {
    return;
  }
  mkdirSync(`${dir}/node_modules/`, { recursive: true });
  ensuredFolders.add(dir);
}

export function bun(...args: any[]): Promise<Juke.ExecReturn> {
  ensureNodeModules('./tgui');

  return Juke.exec('bun', [...args.filter((arg) => typeof arg === 'string')], {
    cwd: './tgui',
    shell: true,
  });
}

export function bunRoot(...args: any[]): Promise<Juke.ExecReturn> {
  ensureNodeModules('.');

  return Juke.exec('bun', [...args.filter((arg) => typeof arg === 'string')], {
    cwd: './',
    shell: true,
  });
}
