export type Summary = {
  n: number;
  mean: number;
  min: number;
  p50: number;
  p95: number;
  p99: number;
  max: number;
};

/** Nearest-rank percentile of an ascending array. */
export function percentile(sorted: number[], p: number): number {
  if (!sorted.length) return 0;
  const rank = Math.ceil((p / 100) * sorted.length);
  return sorted[Math.min(Math.max(rank, 1), sorted.length) - 1];
}

export function summarize(values: number[]): Summary {
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  const mean = n ? sorted.reduce((a, b) => a + b, 0) / n : 0;
  return {
    n,
    mean,
    min: sorted[0] ?? 0,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    p99: percentile(sorted, 99),
    max: sorted[n - 1] ?? 0,
  };
}

export function median(values: number[]): number {
  return percentile(
    [...values].sort((a, b) => a - b),
    50,
  );
}
