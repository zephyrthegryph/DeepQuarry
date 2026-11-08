/**
 * Tests only: webpack's `require.context` (routes.tsx finds interfaces with
 * it, the PDA its screens) under Bun. A loader plugin rewrites the call in the
 * modules that make it into `__requireContext(import.meta.dir, ...)`, backed by
 * the file system: lazy mode returns `import()` promises (as the bundle's
 * on-demand chunks do), eager mode `require()`s. Import this module before
 * anything that loads those modules, and load them with `await import()`.
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { plugin } from 'bun';

type Context = ((key: string) => any) & {
  keys: () => string[];
  resolve: (key: string) => string;
  id: string;
};

function listFiles(root: string, deep: boolean): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      if (statSync(full).isDirectory()) {
        if (deep) walk(full);
      } else {
        out.push(`./${relative(root, full).split(sep).join('/')}`);
      }
    }
  };
  walk(root);
  return out;
}

(globalThis as any).__requireContext = (
  base: string,
  dir: string,
  deep = true,
  filter: RegExp = /^\.\/.*$/,
  mode: 'sync' | 'lazy' = 'sync',
): Context => {
  const root = resolve(base, dir);
  const keys = listFiles(root, deep).filter((key) => filter.test(key));
  const pathOf = (key: string) => {
    if (!keys.includes(key)) {
      const error: any = new Error(`Cannot find module '${key}'`);
      error.code = 'MODULE_NOT_FOUND';
      throw error;
    }
    return join(root, key);
  };
  const context = ((key: string) =>
    mode === 'lazy' ? import(pathOf(key)) : require(pathOf(key))) as Context;
  context.keys = () => keys;
  context.resolve = pathOf;
  context.id = root;
  return context;
};

plugin({
  name: 'require-context',
  setup(build) {
    build.onLoad(
      { filter: /[\\/]tgui[\\/](routes\.tsx|interfaces[\\/].*\.tsx)$/ },
      // Synchronous: a module an async loader returns is async to Bun, and the PDA require()s its screens synchronously.
      (args) => {
        const text = readFileSync(args.path, 'utf8');
        if (!text.includes('require.context(')) {
          return { contents: text, loader: 'tsx' };
        }
        return {
          contents: text.replaceAll(
            'require.context(',
            '__requireContext(import.meta.dir, ',
          ),
          loader: 'tsx',
        };
      },
    );
  },
});
