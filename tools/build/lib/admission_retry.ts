// A native compile that the resident compiler daemon could not admit in its 10 minute budget exits 75 with "daemon build admission
// deadline expired (session or worker capacity)": the daemon was busy with other lanes' builds, nothing is wrong with this one. The build
// queues again instead of failing, still holding the compile-root slot it already waited for (so its place among the lanes is kept), and
// says how long it has waited and who holds the machine's compile slot. DQ_NATIVE_ADMISSION_MAX_MIN (default 30) is the overall cap.

export const ADMISSION_EXPIRED = /admission deadline expired/i;

export function admissionBudgetMs(): number {
  const minutes = Number(process.env.DQ_NATIVE_ADMISSION_MAX_MIN);
  return (Number.isFinite(minutes) && minutes > 0 ? minutes : 30) * 60_000;
}

export async function retryWhileAdmissionExpired<T extends { code: number | null; signal?: string | null; combined: string }>(
  run: () => Promise<T>,
  options: { budgetMs?: number; now?: () => number; log?: (m: string) => void; holders?: () => string } = {},
): Promise<T> {
  const budget = options.budgetMs ?? admissionBudgetMs();
  const now = options.now ?? Date.now;
  const log = options.log ?? ((m: string) => console.warn(m));
  const began = now();
  for (;;) {
    const result = await run();
    if (result.code !== 75 || result.signal || !ADMISSION_EXPIRED.test(result.combined)) return result;
    const waited = now() - began;
    if (waited >= budget) {
      log(`Native compile: still no daemon capacity after ${Math.round(waited / 60_000)} min (DQ_NATIVE_ADMISSION_MAX_MIN); giving up with exit 75.`);
      return result;
    }
    const who = options.holders?.() ?? '';
    log(`Native compile: the compiler daemon had no capacity for ${Math.round(waited / 60_000)} min (other lanes are compiling); queueing again, first come first served.${who ? ` ${who}` : ''}`);
  }
}
