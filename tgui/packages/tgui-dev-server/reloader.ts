/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import os from 'node:os';

import { DreamSeeker } from './dreamseeker';
import { createLogger } from './logging';
import { resolveGlob } from './util';
import { regQuery } from './winreg';

const logger = createLogger('reloader');

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

export async function reloadByondCache(_bundleDir: string): Promise<void> {
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
  // Never overwrite a running DreamSeeker cache. The game server reads the
  // completed build from bundleDir, validates it, registers a new immutable
  // content-addressed generation, and then atomically switches its windows.
  // Direct cache copying allowed the new runtime to observe old/missing chunks.
  for (const cacheDir of cacheDirs) {
    try {
      // Plant a dummy browser window file, we'll be using this to avoid world topic. For byond 515-516.
      await Bun.write(`${cacheDir}/dummy.htm`, '');
      logger.log(`prepared live-generation notification for '${cacheDir}'`);
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
