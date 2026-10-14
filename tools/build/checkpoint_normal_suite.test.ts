import { expect, test } from 'bun:test';
import { checkpointArguments } from './checkpoint_normal_suite';

test('continuation CLI requires exactly six arguments and an exact positive batch size', () => {
  const args = ['prior', 'a'.repeat(64), 'evidence', 'b'.repeat(64), '32', 'destination'];
  expect(checkpointArguments(args).batchSize).toBe(32);
  for (const size of ['0', '-1', '1.5', '32junk', '9007199254740992']) {
    expect(() => checkpointArguments([...args.slice(0, 4), size, args[5]])).toThrow();
  }
  expect(() => checkpointArguments(args.slice(0, 5))).toThrow();
  expect(() => checkpointArguments([...args, 'unexpected'])).toThrow();
});
