import { describe, expect, it } from 'bun:test';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const read = (path: string) =>
  readFileSync(join(import.meta.dir, '..', path), 'utf8');

describe('chat input wiring', () => {
  it('shares the console partial and the scanline variable', () => {
    expect(read('styles/components/ChatConsole.scss')).toContain(
      "@use '~tgui/styles/console'",
    );
    expect(read('styles/components/ChatConsole.scss')).toContain(
      'console.console-frame',
    );
    expect(read('styles/components/ChatInput.scss')).toContain(
      "@use '~tgui/styles/console'",
    );
  });

  it('keeps focus off the map while the input row is used', () => {
    expect(read('panelFocus.ts')).toContain('data-chat-input');
    expect(read('input/ChatInput.tsx')).toContain('data-chat-input');
  });

  it('listens for the radio channels and recalls history', () => {
    expect(read('events/listeners.ts')).toContain("'chat/radioChannels'");
    expect(read('input/ChatInput.tsx')).toContain('parseRadioPrefix');
    expect(read('input/ChatInput.tsx')).toContain('input.recall');
  });

  it('listens for the server focus request', () => {
    expect(read('events/listeners.ts')).toContain("'chat/focusInput'");
  });

  it('has one channel button on the left and listens for the layout', () => {
    expect(read('input/ChatInput.tsx')).toContain('nextChannel');
    expect(read('input/ChatInput.tsx')).not.toContain('INPUT_CHANNELS.map');
    expect(read('events/listeners.ts')).toContain("'chat/layout'");
    // The chat is a tgui interface (tgui/interfaces/Chat.tsx), so the column's window manager docks and floats it like any other.
    expect(read('../tgui/interfaces/Chat.tsx')).toContain('<Panel />');
    expect(read('styles/main.scss')).toContain('ChatLayout.scss');
  });

  it('ports the say popup: formatting keys, live preview and its rules', () => {
    const input = read('input/ChatInput.tsx');
    expect(input).toContain('SHORTCUT_MARKERS');
    expect(input).toContain('toggleLanguage');
    expect(input).toContain('buildPreview');
    expect(input).toContain('LanguagePreview');
    expect(input).toContain('focusMap');
    expect(read('events/listeners.ts')).toContain("'chat/languageRules'");
  });

  // The package is gone from git; a checkout that had it keeps an ignored node_modules folder there, so look for sources.
  it('has no say popup left', () => {
    const dir = join(import.meta.dir, '../../tgui-say');
    const left = existsSync(dir)
      ? readdirSync(dir, { recursive: true })
          .map(String)
          .filter((f) => !f.startsWith('node_modules'))
      : [];
    expect(left).toEqual([]);
  });
});
