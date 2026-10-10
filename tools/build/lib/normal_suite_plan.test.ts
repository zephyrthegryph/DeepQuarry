import { describe, expect, test } from 'bun:test';
import { normalSuiteBatches, exactNormalUnion, bindNormalPlan, suiteBatches, exactSuiteUnion, bindSuitePlan, sameSuiteRuntime, suiteRowSucceeded, type IssuedSuiteInventory, type IssuedNormalInventory } from './normal_suite_plan';
const inventory: IssuedNormalInventory = { schema: 1, tier: 'normal',
  eligible: ['/datum/unit_test/b', '/datum/unit_test/a', '/datum/unit_test/c'],
  excluded: [{ name: '/datum/unit_test/base', reason: 'abstract' }], automaticRows: ['issued_framework'] };

test('all and exhaustive inventories retain actual tiers and exact pre-tier omissions', () => {
  const all: IssuedSuiteInventory = { ...inventory, tier: 'all', preTierCount: 4, tierExcluded: [] };
  expect(suiteBatches(all, 2)).toHaveLength(2);
  expect(() => normalSuiteBatches(all as IssuedNormalInventory, 2)).toThrow('normal');
  const exhaustive: IssuedSuiteInventory = { ...all, tier: 'exhaustive', eligible: [inventory.eligible[0]],
    tierExcluded: inventory.eligible.slice(1).map(name => ({ name, tier: 'normal' })) };
  expect(suiteBatches(exhaustive, 2)).toEqual([[inventory.eligible[0]]]);
  expect(() => bindSuitePlan(all, exhaustive)).toThrow('tier');
  expect(() => suiteBatches({ ...exhaustive, preTierCount: 3 }, 1)).toThrow('coverage');
  expect(() => suiteBatches({ ...all, tierExcluded: [{ name: '/datum/unit_test/x', tier: 'normal' }] }, 1)).toThrow('exclusion');
  expect(exactSuiteUnion(exhaustive, [{ requested: exhaustive.eligible, results: {
    [exhaustive.eligible[0]]: { status: 1 }, issued_framework: { status: 0 },
  } }]).tests[exhaustive.eligible[0]].status).toBe(1);
});
describe('runtime-issued normal inventory', () => {
  test('preserves issued priority order, exact automatic rows and original failures', () => {
    expect(normalSuiteBatches(inventory, 2)).toEqual([inventory.eligible.slice(0, 2), inventory.eligible.slice(2)]);
    const failed = { status: 1, runtimes: 2, message: 'original failure' };
    const union = exactNormalUnion(inventory, [
      { requested: inventory.eligible.slice(0, 2), results: { '/datum/unit_test/b': failed, '/datum/unit_test/a': { status: 0 }, issued_framework: { status: 0 } } },
      { requested: inventory.eligible.slice(2), results: { '/datum/unit_test/c': { status: 2 }, issued_framework: { status: 0 } } },
    ]);
    expect(union.tests['/datum/unit_test/b']).toBe(failed);
    expect(union.frameworkFindings).toHaveLength(2);
  });
  test('prior plan requires exact current membership and retains its order', () => {
    const current = { ...inventory, eligible: [...inventory.eligible].reverse() };
    expect(bindNormalPlan(current, inventory).eligible).toEqual(inventory.eligible);
    expect(() => bindNormalPlan({ ...current, eligible: current.eligible.slice(1) }, inventory)).toThrow('does not match');
    expect(() => bindNormalPlan({ ...current, automaticRows: ['other'] }, inventory)).toThrow('does not match');
  });
  test('rejects missing/foreign/duplicate rows and incomplete union', () => {
    const one: IssuedNormalInventory = { ...inventory, eligible: [inventory.eligible[0]] };
    expect(() => exactNormalUnion(one, [{ requested: one.eligible, results: { [one.eligible[0]]: 0 } }])).toThrow('missing automatic');
    expect(() => exactNormalUnion(one, [{ requested: one.eligible, results: { [one.eligible[0]]: 0, issued_framework: 0, foreign: 0 } }])).toThrow('unexpected result');
    expect(() => exactNormalUnion(one, [])).toThrow('incomplete');
    expect(() => normalSuiteBatches({ ...one, eligible: [...one.eligible, ...one.eligible] }, 1)).toThrow('duplicate');
  });
  test('same selected tests cannot conceal different exclusions or pre-tier membership', () => {
    expect(() => bindNormalPlan({ ...inventory, excluded: [{ ...inventory.excluded[0], reason: 'focus_only' }] }, inventory))
      .toThrow('exclusions differ');
    expect(() => bindNormalPlan({ ...inventory, excluded: [{ name: '/datum/unit_test/other_base', reason: 'abstract' }] }, inventory))
      .toThrow('exclusions differ');
    const exhaustive: IssuedSuiteInventory = { ...inventory, tier: 'exhaustive', preTierCount: 5,
      tierExcluded: [{ name: '/datum/unit_test/omitted', tier: 'normal' }] };
    expect(() => bindSuitePlan({ ...exhaustive, tierExcluded: [{ name: '/datum/unit_test/other_omitted', tier: 'normal' }] }, exhaustive))
      .toThrow('pre-tier coverage differs');
    expect(bindNormalPlan({ ...inventory, preTierCount: 4, tierExcluded: [] }, inventory).preTierCount)
      .toBe(4); // Historical selected-test comparison has no prior pre-tier proof.
    expect(bindSuitePlan({ ...exhaustive, eligible: [...exhaustive.eligible].reverse() }, exhaustive).eligible)
      .toEqual(exhaustive.eligible);
  });
});

describe('suite runtime and result contracts', () => {
  test('different owned slots preserve exact runtime/library content identity', () => {
    const identity = { executable: 'E:/byond/dd.exe', sha256: 'a', version: null, security: '-trusted',
      library: { source: 'E:/work/verdigris.dll', hosted: 'E:/slot-a/verdigris.dll', sha256: 'b', bytes: 12 } };
    const next = { ...identity, library: { ...identity.library, hosted: 'E:/slot-b/verdigris.dll' } };
    expect(sameSuiteRuntime(identity, next)).toBe(true);
    expect(sameSuiteRuntime(identity, { ...next, library: { ...next.library, sha256: 'changed' } })).toBe(false);
    expect(sameSuiteRuntime(identity, { ...next, security: '-safe' })).toBe(false);
    expect(sameSuiteRuntime(identity, undefined)).toBe(false);
  });
  test('malformed or runtime-bearing result cannot pass', () => {
    expect(suiteRowSucceeded({ status: 0, runtimes: 0 })).toBe(true);
    expect(suiteRowSucceeded({ status: 2, runtimes: 0 })).toBe(true);
    expect(suiteRowSucceeded({ status: 0, runtimes: 1 })).toBe(false);
    expect(() => suiteRowSucceeded({ status: 99 })).toThrow('invalid');
    expect(() => suiteRowSucceeded({ status: 0, runtimes: -1 })).toThrow('invalid');
  });
});
