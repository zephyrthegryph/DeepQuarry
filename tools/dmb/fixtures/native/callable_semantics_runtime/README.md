# Callable value runtime contract

This standalone DM world asserts independently chosen values for typed native list
Copy and original-list isolation, untyped safe known/null calls, dynamic colon and
typed/self source verb calls, thrown number capture and typed exception capture.
The compiler-only corpora establish acceptance; this contract tests execution.

`run.py` delegates to the existing power_retirement_runtime paired launcher.
Supply explicit authenticated native compiler, template, DreamMaker and DreamDaemon
paths and SHA pins using that launcher's arguments. It owns the bounded Windows Job,
watchdogs, private runtime copies and unconditional cleanup. No separate executor
is introduced. Output and caches stay on E:. No fixture has been executed yet.

Exact DQ_CALL values are declared in run.py; equal-but-wrong native/reference output,
missing/extra markers or runtime errors fail. The launcher measures fresh paired
execution only; it does not claim retained revision coverage. The source can be
used with the existing incremental_runtime_contract orchestration when a retained
scenario is explicitly added there; this fixture does not invent another daemon.
