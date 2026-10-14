# Phase 0 runtime parity observations

Six complete result observations (exact selection coverage, suite/shutdown markers); preserved runs included separately.

Normal-exit gate passed: **False**. Completed result data does not erase a terminal crash.
Exit outcomes: {'byond': {'exit_codes': [-1073741819, 0, -1073741819], 'stable': False, 'variable': True, 'normal_exit_gate_passed': False}, 'native': {'exit_codes': [0, 0, 0], 'stable': True, 'variable': False, 'normal_exit_gate_passed': True}}

Engine closure prelaunch proof: 5/6 runs; missing or post-run audits are coverage limitations.

Coverage complete: **False**. Equality is **not claimed**.
Normalization is heuristic; counts are observations from three runs, not proof of distribution equivalence.

| Observation | Count |
| --- | ---: |
| tests | 1089 |
| new stable crosscompiler divergences | 0 |
| dropped stable crosscompiler divergences | 1 |
| missing tests | 0 |
| stable test differences | 40 |
| variable test observations | 79 |
| runtime identities | 49 |
| stable located runtime differences | 0 |
| variable runtime identities | 2 |

Every test status, normalized message and runtime-count distribution is in normalized.json.
preserved-comparison.json checks full multiline messages (same line-wise reference/time/number normalization),
preserved signature/count absence, stable deviations and variable observations separately.
An observation outside the three-run range is descriptive, not statistical evidence.
Selected replay pins the same1089 eligible types; original runs lacked an explicit selection/tier filter.
Full original test objects and runtime logs remain in inputs/; evidence.json records hashes,
source-snapshot receipt, engine/pair identities, seed policy and exact normalization invocation.
Unknown runtime ownership or missing source/procedure coverage is retained explicitly;
per-test runtime totals are not added to event totals.

Evidence directory: `D:\dmb-native-v2-phase0\parity-final-corrected-20261007-b`. Exact file hashes are recorded in `finalized-baseline.json`.
