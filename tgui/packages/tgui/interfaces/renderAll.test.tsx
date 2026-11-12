/**
 * Renders every routable tgui interface (the same entries routes.tsx resolves: `./Name.tsx`, `./Name/index.tsx` and the
 * `./chompstation/` fallbacks) with empty data and, where one was captured, with real ui_data from the game
 * (`__fixtures__/ui_data.json`, written by the DM unit test `/datum/unit_test/dq_tgui_ui_data_fixtures`; regenerate with
 * `bash tools/dq_focused_test.sh /datum/unit_test/dq_tgui_ui_data_fixtures` and copy `data/tgui_fixtures/ui_data.json`
 * here). A window fails when rendering throws, an error boundary trips, or anything is logged with console.error.
 */
import { afterAll, afterEach, describe, expect, it } from 'bun:test';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { act, cleanup, render } from '@testing-library/react';
import { Component, type ComponentType, type ReactNode } from 'react';
import {
  configAtom,
  gameDataAtom,
  gameStaticDataAtom,
  store,
  suspendedAtom,
} from '../events/store';

const ROOT = import.meta.dir;
const FIXTURES = join(ROOT, '__fixtures__', 'ui_data.json');
const EXTS = ['tsx', 'jsx'];

/** name -> module path, chompstation/ first, as routes.tsx searches. */
function routableInterfaces(): Map<string, string> {
  const found = new Map<string, string>();
  for (const sub of ['chompstation', '']) {
    const dir = join(ROOT, sub);
    for (const entry of readdirSync(dir)) {
      if (entry.startsWith('__') || entry.includes('.test.')) continue;
      const full = join(dir, entry);
      let name: string | undefined;
      let path: string | undefined;
      if (statSync(full).isDirectory()) {
        for (const ext of EXTS) {
          if (existsSync(join(full, `index.${ext}`))) {
            name = entry;
            path = join(full, `index.${ext}`);
            break;
          }
        }
      } else {
        const m = entry.match(/^([^.]+)\.(tsx|jsx)$/);
        if (m) {
          name = m[1];
          path = full;
        }
      }
      if (name && path && !found.has(name)) found.set(name, path);
    }
  }
  return found;
}

const fixtures: Record<string, Record<string, unknown>> = existsSync(FIXTURES)
  ? JSON.parse(readFileSync(FIXTURES, 'utf8'))
  : {};

/** Hand-written fixtures, one per window (`__fixtures__/windows/<Window>.json`): realistic rows, every ui_shape key set. */
const WINDOW_FIXTURES = join(ROOT, '__fixtures__', 'windows');
const windowFixtures: Record<string, Record<string, unknown>> = {};
if (existsSync(WINDOW_FIXTURES)) {
  for (const entry of readdirSync(WINDOW_FIXTURES)) {
    const m = entry.match(/^(.+)\.json$/);
    if (m)
      windowFixtures[m[1]] = JSON.parse(
        readFileSync(join(WINDOW_FIXTURES, entry), 'utf8'),
      );
  }
}

/** The top-level field names of `<Window>Data` in the generated types (`analyze gen ui_types`), or null when the window has no ui_shape. */
function shapeFields(name: string): string[] | null {
  const file = join(ROOT, 'generated', `${name}.d.ts`);
  if (!existsSync(file)) return null;
  const text = readFileSync(file, 'utf8');
  const start = text.indexOf(`export type ${name}Data = {`);
  if (start < 0) return null;
  const body = text.slice(start, text.indexOf('\n};', start));
  const fields = [
    ...body.matchAll(/^ {2}(?:'([^']+)'|([A-Za-z_$][\w$]*)):/gm),
  ].map((m) => m[1] ?? m[2]);
  return fields.length ? fields : null;
}

class Boundary extends Component<
  { onError: (e: unknown) => void; children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error: unknown) {
    this.props.onError(error);
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

const realError = console.error;
afterEach(() => {
  cleanup();
  console.error = realError;
});

const started = Date.now();
afterAll(() => {
  realError.call(
    console,
    `[renderAll] ${interfaces.size} interfaces, ${Object.keys(fixtures).length} fixtures, ${Date.now() - started} ms; not windows (no export of their name): ${helpers.join(', ') || 'none'}`,
  );
});

function renderWith(
  name: string,
  Routed: ComponentType,
  data: Record<string, unknown>,
): string[] {
  const errors: string[] = [];
  console.error = (...args: unknown[]) => {
    errors.push(
      args.map((a) => (a instanceof Error ? a.stack : String(a))).join(' '),
    );
  };
  store.set(suspendedAtom, false);
  store.set(configAtom, {
    title: name,
    status: 2,
    interface: { name, layout: 'default' },
    window: { key: 'test', size: [400, 600], fancy: false, locked: false },
    user: { name: 'tester', observer: 0 },
  } as any);
  store.set(gameStaticDataAtom, {});
  store.set(gameDataAtom, data);
  try {
    act(() => {
      render(
        <Boundary
          onError={(e) => errors.push(`boundary: ${(e as Error)?.stack ?? e}`)}
        >
          <Routed />
        </Boundary>,
      );
    });
  } catch (e) {
    errors.push(`threw: ${(e as Error)?.stack ?? e}`);
  }
  return errors.slice(0, 3);
}

const interfaces = routableInterfaces();
const helpers: string[] = [];
// These build their screen tables with the bundler's require.context at import time, which bun test has no equivalent of.
const NEEDS_BUNDLER = new Set(['Pda', 'PreferencesMenu']);

describe('every tgui interface renders', () => {
  for (const [name, path] of interfaces) {
    if (NEEDS_BUNDLER.has(name)) {
      it.skip(`${name} (needs require.context)`, () => {});
      continue;
    }
    it(name, async () => {
      const mod = await import(path);
      const Routed = mod[name] as ComponentType | undefined;
      // A module with no export of its own name is a helper (the router would show "missing export"); nothing opens it.
      if (!Routed) {
        helpers.push(name);
        return;
      }
      const written = windowFixtures[name];
      const fields = written ? shapeFields(name) : null;
      // A window with a ui_shape always gets every key it declares (the server sends the window nothing before its first data), so
      // empty data is not a state it can be in: such a window is rendered with its shape-checked fixture instead.
      if (!fields) {
        expect(renderWith(name, Routed, {}), `${name} with {}`).toEqual([]);
      }
      const sample = fixtures[name];
      if (sample) {
        expect(
          renderWith(name, Routed, sample),
          `${name} with fixture`,
        ).toEqual([]);
      }
      if (written) {
        // A hand-written fixture carries exactly the window's ui_shape keys.
        if (fields) {
          expect(
            Object.keys(written).sort(),
            `${name}: __fixtures__/windows/${name}.json keys vs ui_shape`,
          ).toEqual([...fields].sort());
        }
        expect(
          renderWith(name, Routed, written),
          `${name} with __fixtures__/windows/${name}.json`,
        ).toEqual([]);
      }
    });
  }
});
