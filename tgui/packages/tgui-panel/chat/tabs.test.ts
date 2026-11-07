import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { moveBefore } from 'tgui/components/reorder';
import { NO_DRAG } from '../layout/ChatLayout';
import { keepFirst } from './model';

const read = (path: string) =>
  readFileSync(join(import.meta.dir, '..', path), 'utf8');

describe('chat tabs', () => {
  it('keep a press on a tab out of the window drag', () => {
    // tgui-core renders a tab as .Tab.Tabs__Tab; the old '.Tabs__tab' matched nothing.
    expect(NO_DRAG.split(',').map((part) => part.trim())).toContain('.Tab');
  });

  it('reorder by drag, the main tab staying first', () => {
    const pages = ['main', 'radio', 'ooc'];
    expect(keepFirst(pages, moveBefore(pages, 'ooc', 'radio'))).toEqual([
      'main',
      'ooc',
      'radio',
    ]);
    expect(keepFirst(pages, moveBefore(pages, 'radio', 'main'))).toBeNull();
    expect(keepFirst(pages, ['main', 'radio'])).toBeNull();
  });

  it('share the stat panel tab row', () => {
    expect(read('chat/ChatTabs.tsx')).toContain('ConsoleTabs');
    expect(read('statpanel/App.tsx')).toContain('ConsoleTabs');
    expect(read('chat/ChatTabs.tsx')).not.toContain('<Tabs');
    expect(read('statpanel/App.tsx')).not.toContain('<Tabs');
  });
});
