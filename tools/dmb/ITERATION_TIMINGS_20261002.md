# DeepQuarry iteration timings — 2026-10-02

Compiler commit: `17f27d9618`. One run per case, real DeepQuarry project using the existing prepared asset/input mirror (its manifest matches the worktree). Defines: `CBT`, `CIBUILDING`, `CITESTING`. Two workers; one heavy process at a time; 3 GiB process cap; default 512 MiB frontend pool. Development executable uses workspace package optimization overrides. OS filesystem caches were not flushed. Rust executable build time is excluded.

No correctness comparison, unit tests or DreamDaemon runs. Native build responses succeeded; that is not runtime correctness evidence. Receipt hashing was outside the request timer.

| Case | Build request seconds | Authored procedures lowered | Reused |
|---|---:|---:|---:|
| baseline | 298.445 | 68405 | 6 |
| unchanged | 0.584 | 0 | 68411 |
| body-edit | 176.857 | 1 | 68410 |
| revert-body-edit | 22.957 | 0 | 68411 |
| add-proc | 151.821 | 1 | 68411 |
| revert-add-proc | 22.032 | 0 | 68411 |
| add-var | 157.544 | 0 | 68411 |
| revert-add-var | 22.465 | 0 | 68411 |
| change-default | 156.928 | 0 | 68411 |
| revert-change-default | 37.484 | 0 | 68411 |
| cold-process-cached | 0.182 | 0 | 68411 |
| cold-body-edit | 261.308 | 1 | 68410 |

The initial baseline used a newly created empty compiler cache directory. The fresh cached process reused an already published output receipt: 0.182 s request, 0.452 s entire process. The fresh body edit rebuilt from disk caches: 261.308 s request, 262.771 s entire process. Neither should be confused with an OS-cache-cold run.

## Dominant measured stages

| Stage | Empty caches | Retained body edit | Fresh-process body edit |
|---|---:|---:|---:|
| project discovery/preprocessing | 31.572 | 15.292 | 11.442 |
| map/resource fingerprinting | 13.049 | 17.722 | 15.104 |
| compiler | 241.417 | 136.098 | 224.458 |
| input revalidation | 6.457 | 5.269 | 4.857 |
| generation publication | 2.098 | 0.250 | 0.119 |

Stages are nested elapsed totals, not an exhaustive additive partition. Resource fingerprinting includes its resource request scan and resource byte/proof work.

## Findings

- Edited builds remain slow despite reusing essentially all authored procedure lowering. Retained body edits are 176.857 s; structural edits are 151.821–157.544 s.
- The default frontend pool trims lexical state, decoded procedure payloads and prepared expansion inputs. The trace shows disk restoration/reconstruction on subsequent edits. Procedure graph metadata reaches its 256 MiB cap and refuses additional candidate retention.
- Structural declaration skeletons report roughly 158–159 MB retained charge against a 96 MiB persistence cap; the fresh-process body edit reaches type-default completion 118.153 s into compiler work.
- The compiler stage dominates: 136.098 s retained body edit and 224.458 s fresh-process body edit. Source/resource preparation adds substantial overhead.
- Generation publication is 0.119–0.271 s for edited generations in this run. These publication timings are not a standalone measurement of all wire encoding; that work is inside the compiler stage.
- The earlier retained body-edit measurement was 116.099 s and add-procedure 131.661 s. The new observations are slower (about 52% and 15%, respectively), although these are single runs and the implementation/cache configuration changed. The earlier 206.019 s baseline had existing caches and is not comparable to this empty-cache baseline.

Detailed machine-readable observations and trace files: `target/deepquarry-boundary-iteration-20261002/iteration.json`. The harness removed its owned manifest/source overlays after completion. No implementation changes were made during measurement.
