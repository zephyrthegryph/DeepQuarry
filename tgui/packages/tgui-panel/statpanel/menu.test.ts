import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { allCommands } from './menu';

const skin = readFileSync(
  join(import.meta.dir, '../../../../interface/skin.dmf'),
  'utf8',
);

/** What the native menu bar did, before it left skin.dmf. */
const NATIVE_MENU_COMMANDS = [
  '.screenshot auto',
  '.screenshot',
  '.reconnect',
  '.ping',
  '.quit',
  '.winset "mapwindow.map.icon-size=0"',
  '.winset "mapwindow.map.icon-size=128"',
  '.winset "mapwindow.map.icon-size=96"',
  '.winset "mapwindow.map.icon-size=64"',
  '.winset "mapwindow.map.icon-size=48"',
  '.winset "mapwindow.map.icon-size=32"',
  '.winset "mapwindow.map.zoom-mode=distort"',
  '.winset "mapwindow.map.zoom-mode=normal"',
  '.winset "mapwindow.map.zoom-mode=blur"',
  'request-help',
  'hotkeys-help',
  'character-setup',
  'game-options',
];

describe('stat panel menu', () => {
  it('the map split has a default and is never restored from a save', () => {
    const split = skin
      .slice(skin.indexOf('elem "mainvsplit"'))
      .split('\n\n')[0];
    expect(split).toContain('splitter = 70');
    expect(split).toContain('saved-params = ""');
  });

  it('reaches every command of the old native menu bar', () => {
    const reachable = allCommands();
    expect(NATIVE_MENU_COMMANDS.filter((c) => !reachable.includes(c))).toEqual(
      [],
    );
  });

  it('the menu bar and link strip left the skin', () => {
    expect(skin).not.toContain('menu "menu"');
    expect(skin).not.toMatch(/^\s*menu = "/m);
    for (const name of ['wikib', 'forumb', 'discord', 'patreon']) {
      expect(skin).not.toContain(`elem "${name}"`);
    }
  });
});
