import { describe, expect, test } from 'bun:test';
import {
  type AbilityEntry,
  activeToggles,
  cooldownMs,
  cooldownText,
  hasAbilities,
  hoverText,
  moveBefore,
  refusalAt,
  resourceFill,
  sectionsOf,
} from './abilities';

const entry = (
  ref: string,
  category = 'Items',
  extra: Partial<AbilityEntry> = {},
): AbilityEntry => ({
  ref,
  id: `${category}/${ref}`,
  name: ref,
  desc: `${ref} desc`,
  category,
  icon: null,
  cost: null,
  cooldown: 0,
  toggled: null,
  channel: null,
  refusal: null,
  slot: null,
  ...extra,
});

describe('sectionsOf', () => {
  test('groups the default category order into one section each', () => {
    const sections = sectionsOf([
      entry('a'),
      entry('b'),
      entry('c', 'Species'),
      entry('d', 'Spells'),
    ]);
    expect(sections.map((s) => s.category)).toEqual([
      'Items',
      'Species',
      'Spells',
    ]);
    expect(sections[0].entries.map((e) => e.ref)).toEqual(['a', 'b']);
  });

  test('an interleaved order gets a section per run and keeps the order', () => {
    const sections = sectionsOf([
      entry('a'),
      entry('c', 'Species'),
      entry('b'),
    ]);
    expect(sections.map((s) => s.category)).toEqual([
      'Items',
      'Species',
      'Items',
    ]);
    expect(sections.flatMap((s) => s.entries.map((e) => e.ref))).toEqual([
      'a',
      'c',
      'b',
    ]);
  });

  test('nothing in, nothing out', () => {
    expect(sectionsOf([])).toEqual([]);
  });
});

describe('moveBefore', () => {
  const order = ['a', 'b', 'c', 'd'];
  test('dragging up lands before the target', () => {
    expect(moveBefore(order, 'd', 'b')).toEqual(['a', 'd', 'b', 'c']);
  });
  test('dragging down lands after the target', () => {
    expect(moveBefore(order, 'a', 'c')).toEqual(['b', 'c', 'a', 'd']);
  });
  test('to the very end and the very start', () => {
    expect(moveBefore(order, 'a', 'd')).toEqual(['b', 'c', 'd', 'a']);
    expect(moveBefore(order, 'd', 'a')).toEqual(['d', 'a', 'b', 'c']);
  });
  test('dropping on itself or on something unknown changes nothing', () => {
    expect(moveBefore(order, 'b', 'b')).toEqual(order);
    expect(moveBefore(order, 'b', 'zzz')).toEqual(order);
    expect(moveBefore(order, 'zzz', 'b')).toEqual(order);
  });
  test('it does not change the list it was given', () => {
    const copy = [...order];
    moveBefore(order, 'a', 'd');
    expect(order).toEqual(copy);
  });
  test('keeps every ref exactly once', () => {
    expect([...moveBefore(order, 'b', 'd')].sort()).toEqual(order);
  });
});

describe('cooldowns', () => {
  const e = entry('a', 'Items', { cooldown: 50, refusal: 'recharging' });
  test('counts down from the time the message arrived', () => {
    expect(cooldownMs(e, 1000, 1000)).toBe(5000);
    expect(cooldownMs(e, 1000, 3000)).toBe(3000);
    expect(cooldownMs(e, 1000, 9000)).toBe(0);
  });
  test('the recharging refusal ends with the cooldown', () => {
    expect(refusalAt(e, 1000, 2000)).toBe('recharging');
    expect(refusalAt(e, 1000, 7000)).toBeNull();
  });
  test('any other refusal stays', () => {
    const stunned = entry('s', 'Items', {
      cooldown: 50,
      refusal: 'you are stunned',
    });
    expect(refusalAt(stunned, 1000, 9000)).toBe('you are stunned');
    expect(refusalAt(entry('f'), 0, 0)).toBeNull();
  });
  test('text shows tenths under ten seconds', () => {
    expect(cooldownText(3400)).toBe('3.4s');
    expect(cooldownText(12100)).toBe('13s');
    expect(cooldownText(0)).toBe('');
  });
});

describe('toggles, hover, resources', () => {
  test('only the toggles that are on are active', () => {
    const list = [
      entry('a', 'Items', { toggled: true }),
      entry('b', 'Items', { toggled: false }),
      entry('c'),
    ];
    expect(activeToggles(list).map((e) => e.ref)).toEqual(['a']);
  });

  test('hover text lists description, cost, slot and the reason', () => {
    const text = hoverText(
      entry('a', 'Items', { cost: '40 energy', slot: 2 }),
      'recharging',
    );
    expect(text.split('\n')).toEqual([
      'a desc',
      'Cost: 40 energy',
      'Hotkey slot 2',
      'Cannot use now: recharging',
    ]);
    expect(hoverText(entry('a'), null)).toBe('a desc');
  });

  test('a bar fills by value over max and clamps', () => {
    expect(resourceFill({ name: 'E', value: 25, max: 100 })).toBe(0.25);
    expect(resourceFill({ name: 'E', value: 250, max: 100 })).toBe(1);
    expect(resourceFill({ name: 'E', value: -5, max: 100 })).toBe(0);
    expect(resourceFill({ name: 'N', value: 5, max: null })).toBe(0);
  });

  test('a tab with nothing to show is no tab', () => {
    expect(hasAbilities(null)).toBe(false);
    expect(hasAbilities({ abilities: [], resources: [], slots: 9 })).toBe(
      false,
    );
    expect(
      hasAbilities({ abilities: [entry('a')], resources: [], slots: 9 }),
    ).toBe(true);
    expect(
      hasAbilities({
        abilities: [],
        resources: [{ name: 'E', value: 1, max: 2 }],
        slots: 9,
      }),
    ).toBe(true);
  });
});
