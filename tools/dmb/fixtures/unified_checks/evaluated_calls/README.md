# Evaluated-call cohort: independent pinned observations

This fixture covers ordinary missing/resolved calls, failed-call argument
suppression, typed and unknown dot receivers, dynamic colon arguments, named
arguments, lists, interpolation, global calls and duplicate lhs visits for <<.
The TOML explicitly disables proc_call_static_type, proc_has_no_parent and
unreachable_code. No reference output is filtered. Native event tests still
observe unknown-receiver and missing-parent events and suppressed arguments.

Pinned suite-1.11 gives exactly twelve errors, in order:
(4,5), (5,11), (7,10), (8,15), (9,17), (10,19), (11,17), (12,28),
(13,11), (14,5), (14,5), (14,23). Independent stderr capture is under
`data/unified-analysis/evaluated-calls-reference.stderr.txt`.

After root builds the new example and applies the wiring draft:

```powershell
python tools/dmb/scripts/compare_native_checker_fixture.py --reference C:/Users/bmene/SpacemanDMM/dreamchecker.exe --native <private-target>/debug/examples/native_evaluated_calls.exe --family undefined_proc tools/dmb/fixtures/unified_checks/evaluated_calls/probe.dme
```

`undefined_proc` is a native oracle routing key. These legacy errors have no
errortype, so this does NOT add a legacy TOML diagnostics.undefined_proc setting.
Severity is the old unconditional Error. Native comparison has not run yet.

Unsupported contexts fail atomically: control-bearing statements pending the
shared reachable observer, typed/array/stored locals lacking issued declaration
context, source directives/return policies, unary term origins, static
constructors, dynamic syntax primitives and unresolved field static types.
Known function results whose pinned builtin return type is not imported may be
discarded, but using one as a receiver is Unsupported rather than guessed.
There is no copied source model, secondary DM parser, runtime builtin-name
heuristic or complete-checker-parity claim.
