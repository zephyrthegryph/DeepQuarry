import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { moveBefore } from 'tgui/dq';
import { NO_DRAG } from '../layout/ChatLayout';
import { reorderedPages } from './model';

const read = (path: string) =>
  readFileSync(join(import.meta.dir, '..', path), 'utf8');

describe('chat tabs', () => {
  it('keep a press on a tab out of the window drag', () => {
    // tgui-core renders a tab as .Tab.Tabs__Tab; the old '.Tabs__tab' matched nothing.
    expect(NO_DRAG.split(',').map((part) => part.trim())).toContain('.Tab');
  });

  it('reorder by drag, the main tab included', () => {
    const pages = ['main', 'radio', 'ooc'];
    expect(reorderedPages(pages, moveBefore(pages, 'ooc', 'radio'))).toEqual([
      'main',
      'ooc',
      'radio',
    ]);
    expect(reorderedPages(pages, moveBefore(pages, 'radio', 'main'))).toEqual([
      'radio',
      'main',
      'ooc',
    ]);
    expect(reorderedPages(pages, moveBefore(pages, 'main', 'ooc'))).toEqual([
      'radio',
      'ooc',
      'main',
    ]);
    expect(reorderedPages(pages, ['main', 'radio'])).toBeNull();
    expect(read('chat/ChatTabs.tsx')).not.toContain('fixed:');
  });

  it('share the stat panel tab row', () => {
    expect(read('chat/ChatTabs.tsx')).toContain("from 'tgui/dq'");
    // The stat panel's views are the column's stacked tabs: the same DQ tab strip (column/Column.tsx).
    expect(read('column/Column.tsx')).toContain("from 'tgui/dq'");
    // No second tab row of their own (tgui-core's Tabs.Tab used directly).
    for (const path of [
      'chat/ChatTabs.tsx',
      'column/Column.tsx',
      'statpanel/App.tsx',
      'statpanel/InspectTab.tsx',
      'statpanel/McHealth.tsx',
    ]) {
      expect(read(path)).not.toContain('Tabs.Tab');
      expect(read(path)).not.toMatch(
        /import \{[^}]*\bTabs\b[^}]*\} from 'tgui-core\/components'/,
      );
    }
  });
});
