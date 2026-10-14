# Frozen output debug coverage

The read-only `debug_coverage` example decoded both frozen baseline DMBs.
No DreamDaemon or external profiler was launched. The compact observations and
full report hash are in [debug-coverage-summary.json](debug-coverage-summary.json).

| Observation | BYOND | Preserved native |
| --- | ---: | ---: |
| Procedure records | 61,379 | 62,101 |
| Decode errors | 0 | 0 |
| Debug file instructions | 73,108 | 0 |
| Debug line instructions | 467,499 | 0 |
| Ordinary instructions | 2,327,273 | 2,484,120 |
| Sequentially located ordinary instructions | 2,164,634 | 0 |

The comparison found 48,399 unique exact-name matches and 162 ambiguous names;
four unique names occurred only on each side. It does not compare table IDs or
certify semantic equivalence. Sequential locations do not establish control-flow
domination or runtime routing, and runtime errors are not assigned to tests here.

The absent native source markers confirm a limitation of the preserved baseline's
runtime attribution. They do not prove that the differing programs behave alike,
or explain the `power_bridge.dm` list-bounds divergence. Phase 0 remains open.

The detailed report is external evidence at
`E:/dmb-native-v2-phase0/debug-coverage-frozen.json` (233,586,083 bytes); its SHA-256
is recorded in the compact summary. New inspection runs should use aggregate
output unless instruction boundaries are needed.
