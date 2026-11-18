import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export type WindowGeometryManifestEntry = {
  width: number;
  height: number;
  exact: boolean;
};

const FALLBACK_WIDTH = 400;
const FALLBACK_HEIGHT = 600;
/** NtosWindow's default size (packages/tgui/layouts/NtosWindow.tsx). */
const NTOS_WIDTH = 575;
const NTOS_HEIGHT = 700;

function numericProp(tag: string, prop: string): number | undefined {
  const expression = tag.match(
    new RegExp(`\\b${prop}\\s*=\\s*\\{\\s*(\\d+(?:\\.\\d+)?)\\s*\\}`),
  );
  const quoted = tag.match(new RegExp(`\\b${prop}\\s*=\\s*["'](\\d+)["']`));
  const value = expression?.[1] ?? quoted?.[1];
  return value ? Number(value) : undefined;
}

function geometryFromSource(source: string): WindowGeometryManifestEntry {
  // <NtosWindow> opens at its own defaults (layouts/NtosWindow.tsx) unless it names a size.
  for (const match of source.matchAll(/<(Ntos)?Window\b([\s\S]*?)>/g)) {
    const ntos = Boolean(match[1]);
    const width = numericProp(match[2], 'width');
    const height = numericProp(match[2], 'height');
    if (width || height || ntos) {
      return {
        width: width ?? (ntos ? NTOS_WIDTH : FALLBACK_WIDTH),
        height: height ?? (ntos ? NTOS_HEIGHT : FALLBACK_HEIGHT),
        exact: ntos || Boolean(width && height),
      };
    }
  }
  return { width: FALLBACK_WIDTH, height: FALLBACK_HEIGHT, exact: false };
}

function entryFile(directory: string, name: string): string | undefined {
  const isFile = (filename: string) =>
    existsSync(filename) && statSync(filename).isFile();
  for (const extension of ['tsx', 'jsx', 'ts', 'js']) {
    const direct = path.join(directory, `${name}.${extension}`);
    if (isFile(direct)) return direct;
    const index = path.join(directory, name, `index.${extension}`);
    if (isFile(index)) return index;
    for (const containerExtension of ['tsx', 'jsx', 'ts', 'js']) {
      const disguisedDirectoryIndex = path.join(
        directory,
        `${name}.${containerExtension}`,
        `index.${extension}`,
      );
      if (isFile(disguisedDirectoryIndex)) return disguisedDirectoryIndex;
    }
  }
}

function namesIn(directory: string): string[] {
  if (!existsSync(directory)) return [];
  const names = new Set<string>();
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.includes('.test.')) continue;
    if (entry.isDirectory()) {
      if (entryFile(directory, entry.name)) {
        names.add(entry.name.replace(/\.(?:tsx?|jsx?)$/, ''));
      }
      continue;
    }
    const match = entry.name.match(/^([^./]+)\.(?:tsx?|jsx?)$/);
    if (match) names.add(match[1]);
  }
  return [...names];
}

/** Mirrors routes.tsx precedence and produces one entry for every routable UI. */
export function buildWindowGeometryManifest(
  interfacesDirectory: string,
): Record<string, WindowGeometryManifestEntry> {
  const rootNames = namesIn(interfacesDirectory);
  const forkDirectory = path.join(interfacesDirectory, 'chompstation');
  const names = new Set([...rootNames, ...namesIn(forkDirectory)]);
  const manifest: Record<string, WindowGeometryManifestEntry> = {};
  for (const name of [...names].sort()) {
    const sourceFile =
      entryFile(forkDirectory, name) ?? entryFile(interfacesDirectory, name);
    if (!sourceFile) continue;
    manifest[name] = geometryFromSource(readFileSync(sourceFile, 'utf8'));
  }
  return manifest;
}
