# Life scheduler migration: measured result

## Workload and records

`mob_life_body_pipeline` creates 64 humans and runs eight nominal Life cycles in
each 16-second workload window. It measures idle, ordinary body changes,
monitored changes, heavy changes, and teardown on the Virgo minitest map.
Both records use BYOND 516.1687 on the same Windows host with the same
Verdigris DLL. The historical control uses the original `SSmobs` Life cadence;
the migrated result uses the object-model Life Behaviour on a shared, bounded
cadence. The control has five measured boots, and the migrated result has three.

- Original Life control: `data/bench/runs/20260925T002905_d58f79336c_body-post-om-no-owned-life-timer.json`
- Shared-cadence result: `data/bench/runs/20260925T053041_d58f79336c_life-shared-cadence-verified.json`
- Old Life proc profile: `data/bench/profiles/20260925T010319_d58f79336c_body-post-profile/iteration1/`
- New Life proc profile: `data/bench/profiles/20260925T052527_d58f79336c_life-shared-profile/iteration1/`

| Metric (median) | Original Life | Shared Behaviour Life |
|---|---:|---:|
| Idle tick average / p95 / p99 | 5.73% / 29% / 76% | 14.00% / 21% / 24% |
| Normal tick average / p95 / p99 | 6.70% / 38% / 83% | 16.80% / 27% / 31% |
| Monitored-heavy tick average / p95 | 7.49% / 46% | 16.42% / 25% |
| Idle FFI calls / reactor wakes | 3,026 / 40 | 7,850 / 148 |
| Normal FFI calls / reactor wakes | 4,383 / 77 | 8,418 / 161 |
| Spawn / teardown | 0.99 s / 0.81 s | 1.23 s / 1.01 s |
| Private memory after spawn / soak | 1,055 / 1,053 MB | 1,058 / 1,052 MB |
| Rust heap after spawn / soak | 109.10 / 105.31 MB | 109.07 / 105.32 MB |

All three migrated boots produced exactly **512 Life frames and 512 biology
steps per 16-second window** (64 mobs × 8 cycles). All workload windows held
40 TPS with zero tick overruns. The control predates those frame-count metrics.

## Why total tick cost rose

The old `SSmobs` loop intended to spread one mob roster over eight slices, but
recomputed its per-slice quota from the *shrinking remainder* on every fire:
`ceil(length(currentrun) / 8)`. Starting at 64 mobs, the quota fell after each
slice, so the roster took roughly 20–25 slices instead of eight. The proc
profiles show only 177–186 old Life calls in comparable windows versus 535
new calls (511 human calls plus other living mobs). The new cadence restores
the intended two-second rate; it does substantially more gameplay work.

Profiled Life cost per call, including descendants, was 4.27 / 4.80 / 5.47 /
5.36 ms in the four old windows and 4.34 / 5.54 / 6.02 / 5.15 ms in the new
ones. The median per-call cost differs by roughly 5%. This profile is a
diagnostic sample, not a replacement for the unprofiled tick measurements.
The environment exchange path cost about 1.18 ms per call in both versions in
the first profiled window. The larger total tick average is chiefly the
correction of missed Life cycles, not a threefold slowdown per Life call.

The same shrinking-quota error affected nonliving mobs still handled by
`SSmobs`. That roster now snapshots its quota at the start of each eight-slice
cycle. `dq_life_legacy_slice_budget` verifies that a 64-entry roster drains in
eight slices. This follow-up was applied after the three-run living benchmark;
it does not change the shared living cadence.

The first implementation put one recurring native wheel deadline on each mob.
Its idle reactor wakes reached 658 per window. The final design shares awake
cadence in bounded reactor buckets and reserves native owner deadlines for
explicit deferred wakes; the three-run median is 148 idle wakes. The remaining
FFI increase reflects additional Life work and other object-model traffic.

## Limits

The old and new source trees differ in more than scheduling, so the raw
before/after totals are whole-tree measurements. The proc-call comparison is
the evidence for the cadence explanation. Whole-mob accelerated biology is
still selective: only audited `tick_biology()` hooks opt into extra virtual
steps. Polymorphic organ, reagent, addiction, and subtype callbacks still need
classification before their biological effects can run faster than real time.

## Equal-cadence control and scheduler diagnostics

The earlier raw comparison included the old `SSmobs` shrinking-quota bug.
For an equal-work comparison, the pre-object-model body worktree keeps the old
Life scheduler and body implementation but snapshots the eight-slice quota
once per roster. It also records Life and biological frame counts. The same
`mob_life_body_pipeline.dm` file, Virgo minitest map, BYOND 516.1687, 64 humans,
eight-cycle windows, and Verdigris DLL SHA-256
`9AED41629D48CC72B2FFE435BD4BD6101CD580B21E5E2969211A1B0422449D80`
were used on both sides. Each side has one warm-up and three measured boots.

- Control: `E:/projects/CHOMPStation2-body-baseline/data/bench/runs/20260925T055120_d58f79336c_body-pre-om-fixed-cadence.json`
- New: `data/bench/runs/20260925T071051_d58f79336c_object-model-life-final-verified.json`
- Rendered new report: `data/bench/reports/life-final.html`

| Median metric | Old body and fixed old Life scheduler | Object-model body and new Life Behaviour |
| --- | ---: | ---: |
| Idle Life frames per 16 s | 512 | 512 |
| Normal Life frames per 16 s | 512 | 512 |
| Idle tick average / p95 / p99 | 11.61% / 82% / 88% | 14.88% / 21% / 23% |
| Normal tick average / p95 / p99 | 13.09% / 83% / 88% | 17.82% / 29% / 33% |
| Monitored-heavy tick average / p95 | 14.44% / 81% | 17.52% / 26% |
| Idle FFI calls / reactor wakes | 8,295 / 77 | 7,668 / 130 |
| Spawn / teardown | 1.08 s / 0.71 s | 1.04 s / 1.04 s |
| Private memory after spawn / soak | 1,054 / 1,052 MB | 1,058 / 1,052 MB |

Both sides held 40 TPS, completed all 512 frames in every measured window,
and had zero overruns. The new scheduler had no missed deadlines in any
measured window. It recorded one physiology call at 2.17 ms in one normal
window and one monitored-normal window; its ordinary Life frames did not flood
the slow-call ring. The new scheduler spreads work far more evenly across
ticks, but its average tick cost is higher at equal cadence. Its diagnostic
sampling and object-model scheduling are included in that measured cost. The
control worktree retains surrounding compatibility code, so this is a
matched-workload whole-tree comparison, not a measurement of one isolated
function call. The new run also reports exact scheduler call counts, sampled
per-system cost, work units, missed deadlines and deferrals; the old control
has no corresponding diagnostic counters.
