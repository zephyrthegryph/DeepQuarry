import { describe, expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const packages = join(import.meta.dirname, '..', '..');

function scssFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name === 'node_modules') return [];
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return scssFiles(path);
    return entry.name.endsWith('.scss') ? [path] : [];
  });
}

const sheets = scssFiles(packages).map((path) => ({
  name: relative(packages, path).split(sep).join('/'),
  text: readFileSync(path, 'utf8'),
}));

function sheet(name: string): string {
  return sheets.find((s) => s.name === name)?.text ?? '';
}

// A @use, @forward or load-css of a tgui-core sheet that holds CSS emits the whole sheet where it is imported.
// A copy in a lazy chunk or under a scope lands after the page's own rules and undoes them at equal specificity.
const EMITS_CORE =
  /(@(use|forward|import)\s+|load-css\(\s*)['"]~?tgui-core\/styles(\/components\/[^'"]+)?['"]/;

const ENTRIES = ['tgui-panel/styles/main.scss', 'tgui/styles/main.scss'];

describe('tgui-core button styles', () => {
  test('only the two entry sheets emit tgui-core', () => {
    expect(
      sheets
        .filter((s) => EMITS_CORE.test(s.text))
        .map((s) => s.name)
        .sort(),
    ).toEqual(ENTRIES);
  });

  test('each entry loads the button baseline after the library', () => {
    for (const name of ENTRIES) {
      const text = sheet(name);
      expect(text.indexOf('dq/index.scss')).toBeGreaterThan(
        text.search(EMITS_CORE),
      );
    }
    expect(sheet('tgui/styles/dq/index.scss')).toContain(
      './button-baseline.scss',
    );
  });

  test('the baseline keeps a last button level with its row', () => {
    expect(sheet('tgui/styles/dq/button-baseline.scss')).toMatch(
      /\.Button:last-child \{\s*margin-bottom: calc\(var\(--space-xs\) \/ 2\);/,
    );
  });
});
