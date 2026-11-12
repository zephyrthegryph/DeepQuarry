import { describe, expect, it } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  CONSOLE_THEME,
  resolveTheme,
  WINDOW_THEMES,
  SCANLINES_DISABLED_KEY,
  scanlineOverride,
} from './layouts/consoleTheme';

const read = (path: string) =>
  readFileSync(join(import.meta.dir, path), 'utf8');

describe('console theme', () => {
  it('is imported by the entry point', () => {
    expect(read('index.tsx')).toContain(
      `./styles/themes/${CONSOLE_THEME}.scss`,
    );
  });

  it('declares its root class and draws the shared scanlines', () => {
    const scss = read(`styles/themes/${CONSOLE_THEME}.scss`);
    expect(scss).toContain(`.theme-${CONSOLE_THEME}:root`);
    expect(scss).toContain('console.console-scanlines');
    expect(scss).toContain('console.console-component-vars');
  });

  it('keeps each effect on one shared knob', () => {
    const scss = read('styles/console.scss');
    for (const knob of [
      '--console-scanline-strength',
      '--console-fringe-strength',
      '--console-glow',
      '--console-glow-inset',
      '--console-vignette',
    ]) {
      expect(scss).toContain(`${knob}:`);
    }
    // No surface sets its own strength or bloom any more.
    for (const path of [
      `styles/themes/${CONSOLE_THEME}.scss`,
      'styles/interfaces/LobbyMenu.scss',
    ]) {
      expect(read(path)).not.toContain('--console-scanline-strength:');
      expect(read(path)).not.toContain('0 0 15px');
    }
  });

  it('shares its values with the lobby', () => {
    expect(read('styles/interfaces/LobbyMenu.scss')).toContain(
      "@use '../console'",
    );
  });

  it('lists exactly the themes that have a stylesheet', () => {
    const files = readdirSync(join(import.meta.dir, 'styles/themes'))
      .filter((f) => f.endsWith('.scss'))
      .map((f) => f.replace(/\.scss$/, ''))
      .sort();
    expect([...WINDOW_THEMES].sort()).toEqual(files);
  });

  it('draws a window in the console look unless it names a styled theme', () => {
    expect(resolveTheme(undefined)).toBe(CONSOLE_THEME);
    expect(resolveTheme('')).toBe(CONSOLE_THEME);
    expect(resolveTheme('default')).toBe(CONSOLE_THEME);
    expect(resolveTheme('pda_retro')).toBe(CONSOLE_THEME);
    expect(resolveTheme('syndicate')).toBe('syndicate');
    expect(resolveTheme('ntos')).toBe('ntos');
  });

  it('turns scanlines off only when the lobby preference says so', () => {
    expect(SCANLINES_DISABLED_KEY).toBe('lobby-filter-disabled');
    expect(scanlineOverride(true)).toBe('0');
    expect(scanlineOverride(undefined)).toBeNull();
    expect(scanlineOverride(false)).toBeNull();
  });
});
