// bun test tools/build/lib/admission_retry.test.ts  (run by tools/ci/test_admission_retry.sh)
import { describe, expect, test } from 'bun:test';
import { retryWhileAdmissionExpired } from './admission_retry';

const expired = { code: 75, signal: null, combined: 'daemon build admission deadline expired (session or worker capacity)' };
const ok = { code: 0, signal: null, combined: '' };

describe('admission retry', () => {
  test('queues again after an expired admission and succeeds', async () => {
    const results = [expired, expired, ok];
    let calls = 0;
    const logs: string[] = [];
    const r = await retryWhileAdmissionExpired(async () => results[calls++], { budgetMs: 1000, now: () => 0, log: (m) => logs.push(m), holders: () => 'Held by: lane-x' });
    expect(r.code).toBe(0);
    expect(calls).toBe(3);
    expect(logs.length).toBe(2);
    expect(logs[0]).toContain('Held by: lane-x');
  });
  test('gives up with exit 75 once the overall budget is spent', async () => {
    let t = 0;
    let calls = 0;
    const r = await retryWhileAdmissionExpired(async () => { calls++; t += 600_000; return expired; }, { budgetMs: 1_800_000, now: () => t, log: () => {} });
    expect(r.code).toBe(75);
    expect(calls).toBe(3); // 10, 20, 30 minutes
  });
  test('other failures and signals are never retried', async () => {
    let calls = 0;
    const r = await retryWhileAdmissionExpired(async () => { calls++; return { code: 1, signal: null, combined: 'admission deadline expired' }; }, { budgetMs: 1000, now: () => 0, log: () => {} });
    expect(r.code).toBe(1);
    expect(calls).toBe(1);
    const killed = await retryWhileAdmissionExpired(async () => { calls++; return { ...expired, signal: 'SIGTERM' }; }, { budgetMs: 1000, now: () => 0, log: () => {} });
    expect(killed.signal).toBe('SIGTERM');
    expect(calls).toBe(2);
  });
});
