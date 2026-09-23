// Map template bounds, computed at build time (fixes.md Q2).
//
// /datum/map_template/New() used to parse every .dmm just to learn its width and
// height. This writes those bounds to data/map_template_bounds.json so the DM side
// only parses a template when it is actually loaded. The scan mirrors
// /datum/parsed_map/New() in code/modules/maps/reader.dm; each entry also records
// the file size, and DM re-parses any template whose size no longer matches.

import fs from 'node:fs';
import path from 'node:path';

export const MAP_BOUNDS_FILE = 'data/map_template_bounds.json';

// Same pattern as dmm_regex in reader.dm.
const DMM_REGEX =
  /"([a-zA-Z]+)" = (?:\(\n|\()((?:.|\n)*?)\)\n(?!\t)|\((\d+),(\d+),(\d+)\) = \{"([a-zA-Z\n]*)"\}/g;

/** [minx, miny, minz, maxx, maxy, maxz], or null when the map has no coordinates. */
export const dmmBounds = (text: string): number[] | null => {
  const bounds = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
  let keyLen = 0;
  let lineLen = 0;
  for (const match of text.matchAll(DMM_REGEX)) {
    if (match[1]) {
      if (!keyLen) keyLen = match[1].length;
      continue;
    }
    if (!match[3] || !keyLen) continue;
    const x = Number(match[3]);
    let y = Number(match[4]);
    const z = Number(match[5]);
    bounds[0] = Math.min(bounds[0], x);
    bounds[2] = Math.min(bounds[2], z);
    bounds[5] = Math.max(bounds[5], z);
    const lines = match[6].split('\n');
    while (lines.length && lines[0] === '') lines.shift();
    if (!lines.length) continue;
    if (lines[lines.length - 1] === '') lines.pop();
    bounds[1] = Math.min(bounds[1], y);
    y += lines.length - 1;
    bounds[4] = Math.max(bounds[4], y);
    if (!lineLen) lineLen = lines[0].length;
    bounds[3] = Math.max(bounds[3], x, x + lineLen / keyLen - 1);
  }
  return bounds[0] === Infinity ? null : bounds;
};

const walk = (dir: string, out: string[]): void => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dmm')) out.push(full);
  }
};

/** Writes bounds for every .dmm under `roots`, keyed by forward-slash repo path. */
export const writeMapBounds = (roots: string[]): number => {
  const files: string[] = [];
  for (const root of roots) if (fs.existsSync(root)) walk(root, files);
  const result: Record<string, number[]> = {};
  for (const file of files.sort()) {
    const raw = fs.readFileSync(file);
    const bounds = dmmBounds(raw.toString('utf8'));
    if (bounds) result[file.split(path.sep).join('/')] = [...bounds, raw.length];
  }
  fs.mkdirSync(path.dirname(MAP_BOUNDS_FILE), { recursive: true });
  fs.writeFileSync(MAP_BOUNDS_FILE, JSON.stringify(result));
  return Object.keys(result).length;
};
