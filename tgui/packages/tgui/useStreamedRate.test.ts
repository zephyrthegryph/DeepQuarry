import { describe, expect, test } from 'bun:test';
import { streamedValue, streamSettled } from './useStreamedRate';

const charging = { value: 100, rate: 25, at: 400 };

describe('streamedValue', () => {
  test('projects value + rate * elapsed', () => {
    expect(streamedValue(charging, 0)).toBe(100);
    expect(streamedValue(charging, 2)).toBe(150);
  });

  test('a negative rate drains', () => {
    expect(streamedValue({ value: 10, rate: -2, at: 0 }, 3)).toBe(4);
  });

  test('clamps to the bounds', () => {
    expect(streamedValue(charging, 100, { max: 1000 })).toBe(1000);
    expect(streamedValue({ value: 10, rate: -2, at: 0 }, 100, { min: 0 })).toBe(
      0,
    );
  });

  test('never runs backwards on a negative elapsed time', () => {
    expect(streamedValue(charging, -5)).toBe(100);
  });
});

describe('streamSettled', () => {
  test('a zero rate is settled', () => {
    expect(streamSettled({ value: 5, rate: 0, at: 0 })).toBe(true);
  });

  test('pinned against the bound it heads into is settled', () => {
    expect(streamSettled({ value: 1000, rate: 5, at: 0 }, { max: 1000 })).toBe(
      true,
    );
    expect(streamSettled({ value: 0, rate: -5, at: 0 }, { min: 0 })).toBe(true);
  });

  test('a moving reading is not settled', () => {
    expect(streamSettled(charging, { max: 1000 })).toBe(false);
    expect(streamSettled(charging)).toBe(false);
  });
});
