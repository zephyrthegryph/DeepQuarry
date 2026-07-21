/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { rename } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { DreamSeeker } from './dreamseeker';
import { createLogger } from './logging';
import { resolveGlob, resolvePath } from './util';
import { regQuery } from './winreg';

const logger = createLogger('reloader');

// Basic glob pattern for bundle files
const bundleGlob = '*.{bundle,chunk,hot-update}.*';

const HOME = os.homedir();
const SEARCH_LOCATIONS = [
  // Custom location
  process.env.BYOND_CACHE,
  // Windows
  `${HOME}/*/BYOND/cache`,
  // Wine
  `${HOME}/.wine/drive_c/users/*/*/BYOND/cache`,
  // Lutris
  `${HOME}/Games/byond/drive_c/users/*/*/BYOND/cache`,
  // WSL
  `/mnt/c/Users/*/*/BYOND/cache`,
];

let cacheRoot: string;

export async function findCacheRoot(): Promise<string | undefined> {
  if (cacheRoot) {
    return cacheRoot;
  }
  logger.log('looking for byond cache');
  // Find BYOND cache folders

  for (const pattern of SEARCH_LOCATIONS) {
    if (!pattern) {
      continue;
    }

    const paths = await resolveGlob(pattern);
    if (paths.length > 0) {
      cacheRoot = paths[0];
      onCacheRootFound(cacheRoot);
      return cacheRoot;
    }
  }

  // Query the Windows Registry
  if (process.platform === 'win32') {
    logger.log('querying windows registry');
    const userpath = await regQuery(
      'HKCU\\Software\\Dantom\\BYOND',
      'userpath',
    );
    if (userpath) {
      cacheRoot = `${userpath.replace(/\\$/, '').replace(/\\/g, '/')}/cache`;
      await onCacheRootFound(cacheRoot);
      return cacheRoot;
    }
  }
  logger.log('found no cache directories');
}

async function onCacheRootFound(cacheRoot: string): Promise<void> {
  logger.log(`found cache at '${cacheRoot}'`);
  // Plant a dummy browser window file, we'll be using this to avoid world topic. For byond 514.
  await Bun.write(`${cacheRoot}/dummy.htm`, '');
}

export async function reloadByondCache(bundleDir: string): Promise<void> {
  const cacheRoot = await findCacheRoot();
  if (!cacheRoot) return;

  // Find tmp folders in cache
  const cacheDirs = await resolveGlob(cacheRoot, 'tmp*');
  if (cacheDirs.length === 0) {
    logger.log('found no tmp folder in cache');
    return;
  }

  const pids = cacheDirs.map((cacheDir) => {
    return parseInt(cacheDir.split('\\cache\\tmp')[1], 10);
  });

  const dssPromise = DreamSeeker.getInstancesByPids(pids);
  // Copy assets
  const assets = await resolveGlob(bundleDir, bundleGlob);
  // Publish runtime/entry bundles last. A running browser may request an async
  // chunk as soon as it observes the new runtime, so every dependency must
  // already be present by the time an entry bundle becomes visible.
  assets.sort((left, right) => {
    const isEntry = (file: string) =>
      /(?:^|[/\\])tgui(?:-panel|-say)?\.bundle\.(?:js|css|map)$/.test(file);
    return Number(isEntry(left)) - Number(isEntry(right));
  });

  for (const cacheDir of cacheDirs) {
    try {
      // Plant a dummy browser window file, we'll be using this to avoid world topic. For byond 515-516.
      await Bun.write(`${cacheDir}/dummy.htm`, '');

      // Copy assets
      for (const [index, asset] of assets.entries()) {
        const destination = resolvePath(cacheDir, path.basename(asset));
        const staged = `${destination}.tgui-stage-${process.pid}-${index}`;
        const input = Bun.file(asset);
        const output = Bun.file(staged);

        await Bun.write(output, input);
        // Same-volume rename is atomic: browsers see either the complete old file
        // or the complete new file, never a missing or partially-written chunk.
        await rename(staged, destination);
      }
      logger.log(`copied ${assets.length} files to '${cacheDir}'`);
    } catch (err) {
      logger.error(`failed copying to '${cacheDir}'`);
      logger.error(err);
    }
  }
  // Notify dreamseeker
  const dss = await dssPromise;
  if (dss.length > 0) {
    logger.log(`notifying dreamseeker`);
    for (const dreamseeker of dss) {
      dreamseeker.topic({
        tgui: 1,
        type: 'cacheReloaded',
      });
    }
  }
}
