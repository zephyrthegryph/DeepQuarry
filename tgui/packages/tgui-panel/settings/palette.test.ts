import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DARK_PALETTE } from './palette';
import { clientThemeWinset, SKIN_PANES } from './themes';

const root = join(import.meta.dir, '../../../..');
const skin = readFileSync(join(root, 'interface/skin.dmf'), 'utf8');
const statCss = readFileSync(
  join(import.meta.dir, '../statpanel/statpanel.scss'),
  'utf8',
);
const chatSheet = readFileSync(
  join(import.meta.dir, '../styles/tgchat/chat.scss'),
  'utf8',
);
const chatTokens = readFileSync(
  join(import.meta.dir, '../styles/tgchat/chat-tokens.scss'),
  'utf8',
);

/** The body of `@mixin name { ... }` in chat-tokens.scss (empty when absent). */
function tokenMixin(name: string): string {
  const start = chatTokens.indexOf(`@mixin ${name} {`);
  if (start < 0) return '';
  const end = chatTokens.indexOf('\n}\n', start);
  return chatTokens.slice(start, end);
}

/** The chat sheet as one theme sees it: every --chat- token replaced by that theme's value, plus its own rules. */
function chatSheetFor(theme: string): string {
  const values = new Map<string, string>();
  for (const match of tokenMixin(theme).matchAll(
    /^ {2}(--chat-[\w-]+): (.+);$/gm,
  )) {
    values.set(match[1], match[2]);
  }
  const resolved = chatSheet.replace(
    /var\((--chat-[\w-]+)\)/g,
    (whole, name: string) => values.get(name) ?? whole,
  );
  return `${resolved}\n${tokenMixin(`${theme}-rules`)}`;
}

const chatDark = chatSheetFor('dark');

/** The body of one element in skin.dmf, up to the next elem or window. */
function skinElem(name: string): string {
  const start = skin.indexOf(`elem "${name}"`);
  expect(start).toBeGreaterThan(-1);
  return skin.slice(start).split(/\n\s*(?:elem|window) /)[0];
}

function luminance([r, g, b]: number[]): number {
  const f = (c: number) =>
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}

function hslToRgb(h: number, s: number, l: number): number[] {
  const a = (s / 100) * Math.min(l / 100, 1 - l / 100);
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    return l / 100 - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
  };
  return [f(0), f(8), f(4)];
}

describe('native dark palette', () => {
  it('every skin element the theme sets exists in skin.dmf', () => {
    for (const key of Object.keys(clientThemeWinset('dark'))) {
      expect(skin).toContain(`elem "${key.split('.')[0]}"`);
    }
  });

  it('skin.dmf starts dark, in the palette', () => {
    for (const name of SKIN_PANES) {
      expect(skinElem(name)).toContain(
        `background-color = ${DARK_PALETTE.base}`,
      );
    }
  });

  it('the light theme undoes every colour the dark theme sets', () => {
    expect(Object.keys(clientThemeWinset('light')).sort()).toEqual(
      Object.keys(clientThemeWinset('dark')).sort(),
    );
  });

  it('the stat panel reads the palette', () => {
    const hex = (value: string) => value.toLowerCase();
    expect(statCss).toContain(`--stat-base: ${hex(DARK_PALETTE.base)}`);
    expect(statCss).toContain(`--stat-section: ${hex(DARK_PALETTE.section)}`);
    expect(statCss).toContain(`--stat-text: ${hex(DARK_PALETTE.text)}`);
    expect(statCss).toContain(`--stat-link: ${hex(DARK_PALETTE.hyperlink)}`);
  });
});

describe('vchatdark chat colours', () => {
  const vchatDark = chatSheetFor('vchatdark');

  it('every text colour on the bare chat background is readable', () => {
    const background = luminance(hslToRgb(0, 0, 12.5));
    const unreadable: string[] = [];
    for (const rule of vchatDark.matchAll(/([^{};]+)\{([^{}]*)\}/g)) {
      if (rule[2].includes('background')) continue;
      const color = rule[2].match(
        /(?:^|\s)color:\s*hsl\(([\d.]+),\s*([\d.]+)%,\s*([\d.]+)%\)/,
      );
      if (!color) continue;
      const [h, s, l] = color.slice(1).map(Number);
      const text = luminance(hslToRgb(h, s, l));
      if ((text + 0.05) / (background + 0.05) < 4.5) {
        unreadable.push(rule[1].trim());
      }
    }
    expect(unreadable).toEqual([]);
  });
});

describe('dark chat colours', () => {
  it.each([
    'red',
    'green',
    'blue',
    'warning',
    'danger',
    'alert',
    'boldannounce',
    'adminhelp',
    'ooc .admin',
    'cult',
  ])('.%s is readable on the chat background', (name) => {
    const match = chatDark.match(
      new RegExp(
        `\\.${name}\\s*(?:,[^{}]*)?\\{[^}]*?color:\\s*hsl\\(([\\d.]+),\\s*([\\d.]+)%,\\s*([\\d.]+)%\\)`,
      ),
    );
    expect(match).not.toBeNull();
    const [h, s, l] = match!.slice(1).map(Number);
    const text = luminance(hslToRgb(h, s, l));
    const background = luminance(hslToRgb(0, 0, 12.5));
    expect((text + 0.05) / (background + 0.05)).toBeGreaterThanOrEqual(4.5);
  });
});

describe('one chat stylesheet', () => {
  it('every token the sheet reads is defined for every theme', () => {
    const used = new Set(
      [...chatSheet.matchAll(/var\((--chat-[\w-]+)\)/g)]
        .map((match) => match[1])
        .filter((name) => !name.includes('#{')),
    );
    for (const theme of ['dark', 'light', 'vchatdark', 'vchatlight']) {
      const body = tokenMixin(theme);
      const missing = [...used].filter((name) => !body.includes(`${name}:`));
      expect({ theme, missing }).toEqual({ theme, missing: [] });
    }
  });
});
