import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  CONSOLE_THEME,
  SCANLINES_DISABLED_KEY,
  scanlineOverride,
} from './layouts/consoleTheme';

const read = (path: string) => readFileSync(join(import.meta.dir, path), 'utf8');

describe('console theme', () => {
  it('is imported by the entry point', () => {
    expect(read('index.tsx')).toContain(
      `./styles/themes/${CONSOLE_THEME}.scss`,
    );
  });

  it('declares its root class and the scanline variable', () => {
    const scss = read(`styles/themes/${CONSOLE_THEME}.scss`);
    expect(scss).toContain(`.theme-${CONSOLE_THEME}:root`);
    expect(scss).toContain('--console-scanline-strength');
  });

  it('shares its values with the lobby', () => {
    expect(read('styles/interfaces/LobbyMenu.scss')).toContain(
      "@use '../console'",
    );
  });

  it('turns scanlines off only when the lobby preference says so', () => {
    expect(SCANLINES_DISABLED_KEY).toBe('lobby-filter-disabled');
    expect(scanlineOverride(true)).toBe('0');
    expect(scanlineOverride(undefined)).toBeNull();
    expect(scanlineOverride(false)).toBeNull();
  });
});
