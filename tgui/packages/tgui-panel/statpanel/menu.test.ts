import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { allCommands } from './menu';

const skin = readFileSync(
  join(import.meta.dir, '../../../../interface/skin.dmf'),
  'utf8',
);

describe('stat panel menu', () => {
  it('reaches every command of the native menu bar', () => {
    const block = skin.slice(
      skin.indexOf('menu "menu"'),
      skin.indexOf('window "mainwindow"'),
    );
    const commands = [...block.matchAll(/command = "((?:[^"\\]|\\.)*)"/g)]
      .map((match) => match[1].replace(/\\"/g, '"'))
      .filter((command) => command && !command.includes('menu.textmode'));
    expect(commands.length).toBeGreaterThan(10);
    const reachable = allCommands();
    expect(commands.filter((c) => !reachable.includes(c))).toEqual([]);
  });

  it('the link strip left the skin', () => {
    for (const name of ['wikib', 'forumb', 'discord', 'patreon']) {
      expect(skin).not.toContain(`elem "${name}"`);
    }
  });
});
