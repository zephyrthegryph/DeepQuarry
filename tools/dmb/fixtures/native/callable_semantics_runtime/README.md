# Callable value runtime contract

This standalone DM world asserts independently chosen values for typed native list
Copy and original-list isolation, untyped safe known/null calls, dynamic colon and
typed/self source verb calls, thrown number capture and typed exception capture.
The compiler-only corpora establish acceptance; this contract tests execution.

`run.py` delegates to the existing power_retirement_runtime paired launcher.
Supply explicit authenticated native compiler, template, DreamMaker and DreamDaemon
paths and SHA pins using that launcher's arguments. It owns the bounded Windows Job,
watchdogs, private runtime copies and unconditional cleanup. No separate executor
is introduced. Output and caches stay on E:. The paired fixture has been executed; evidence is recorded below.

Exact DQ_CALL values are declared in run.py; equal-but-wrong native/reference output,
missing/extra markers or runtime errors fail. The launcher measures fresh paired
execution only; it does not claim retained revision coverage. The source can be
used with the existing incremental_runtime_contract orchestration when a retained
scenario is explicitly added there; this fixture does not invent another daemon.

## Retained revisions

`python run_retained.py` accepts the SAME eight executable/template pin flags as
incremental_runtime_contract/run.py and delegates to that one orchestration core.
The four revisions are initial, unchanged, verb body edit (+5), and a structural
field addition plus changed receiver default (23 to31). Each revision authenticates
source copies, checks fifteen independent numeric runtime markers plus the completion marker against BYOND and both
native modes, and requires exact fresh/retained DMB and RSC hashes. The unchanged
4GiB sampled ownership limit and 300 second overall lifetime remain in force.
The unused resource sidecar satisfies the shared harness's authenticated source
closure; it is not a resource-change test. The expanded loop controls passed every retained revision; evidence is recorded below.

The contract also checks sized local array methods: explicit `var/list/value[2] = list(7)` then `Add(11)` and `Copy()` yields 18; implicit `var/value[2]` then `Add(13)` and `Copy()` yields length 3 plus final element 13, or 16. These two markers remain unchanged across body and structural revisions.

The field control declares `var/items[2]` on a datum, calls `Add(7)` and `Copy()` on that field, and expects length 3 plus the third element 7, or 10. This checks field-array allocation and inferred list-method dispatch independently of the local-array controls. The marker is required in every retained revision and in both fresh paired outputs. The field control passed the paired and retained execution checks recorded in STATUS.md.

## Loop initializer receiver controls

Typed list and source-datum declarations in C-style loop initializers must retain their receiver types and implied `new` context. The list control expects 18; the datum control follows the verb body/default edits (23, 28, 36).

The expanded 16-marker paired fixture passed on 2026-10-11 against pinned native source `00e44b6e7f` and BYOND 516.1687, with zero runtime errors. Receipt: `E:/dq-cache/dmb-callable-loop-runtime/34dd54b4e13740cdb3c11d29e944f5d8/receipt.json`. This is a focused semantics result, not full-suite parity or a performance benchmark.

The same expanded fixture passed all four retained revisions (initial, unchanged, body, structural), with identical fresh/retained DMB and RSC and matching BYOND runtime values: `E:/dq-cache/dmb-callable-loop-retained/27020249d138402ea4e1f7fb62c74607/receipt.json`.
