import { useEffect, useState } from 'react';

/**
 * A quantity the server streams as a rate instead of pushing every change:
 * `value` is the reading when the sample was taken, `rate` its change per
 * second, and `at` the server's clock at that moment (it only tells samples
 * apart; the client anchors on the moment the sample arrived).
 *
 * The DM half is `om_ui_stream()` / `om_ui_rate()` (code/datums/om/ui.dm). A
 * SMES charge, a grid's supply and load, or a tank's pressure is declared as a
 * stream rate; the server sends a new sample only when the rate changes.
 */
export type StreamedRate = {
  value: number;
  rate: number;
  at: number;
};

export type StreamBounds = {
  /** The reading never goes below this (default: unbounded). */
  min?: number;
  /** The reading never goes above this (default: unbounded). */
  max?: number;
};

/** The reading `elapsedSeconds` after `sample` arrived: value + rate * elapsed, clamped. */
export function streamedValue(
  sample: StreamedRate,
  elapsedSeconds: number,
  bounds: StreamBounds = {},
): number {
  const { min = Number.NEGATIVE_INFINITY, max = Number.POSITIVE_INFINITY } =
    bounds;
  const projected = sample.value + sample.rate * Math.max(elapsedSeconds, 0);
  return Math.min(Math.max(projected, min), max);
}

/** True once a sample can no longer move: no rate, or pinned against a bound it heads into. */
export function streamSettled(
  sample: StreamedRate,
  bounds: StreamBounds = {},
): boolean {
  if (!sample.rate) {
    return true;
  }
  if (sample.rate > 0 && bounds.max !== undefined) {
    return sample.value >= bounds.max;
  }
  if (sample.rate < 0 && bounds.min !== undefined) {
    return sample.value <= bounds.min;
  }
  return false;
}

/**
 * Interpolates a streamed quantity on the client, so a live meter moves
 * smoothly between the few samples the server sends. Returns the current
 * reading; re-renders every `intervalMs` while the reading is moving, and not
 * at all while it is steady, pinned at a bound, or `sample` is missing.
 */
export function useStreamedRate(
  sample: StreamedRate | undefined,
  bounds: StreamBounds = {},
  intervalMs = 100,
): number | undefined {
  const { min, max } = bounds;
  const [reading, setReading] = useState<number | undefined>(sample?.value);

  // A new sample (a changed value, rate or server time) restarts the projection.
  const value = sample?.value;
  const rate = sample?.rate;
  const at = sample?.at;
  useEffect(() => {
    if (value === undefined || rate === undefined || at === undefined) {
      setReading(undefined);
      return;
    }
    const current: StreamedRate = { value, rate, at };
    const limits = { min, max };
    const anchor = performance.now();
    setReading(streamedValue(current, 0, limits));
    if (streamSettled(current, limits)) {
      return;
    }
    const timer = setInterval(() => {
      const elapsed = (performance.now() - anchor) / 1000;
      setReading(streamedValue(current, elapsed, limits));
    }, intervalMs);
    return () => clearInterval(timer);
  }, [value, rate, at, min, max, intervalMs]);

  return reading;
}
