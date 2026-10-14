# Local receiver compiler controls

Authenticated pinned BYOND 516.1687 controls prove untyped local ordinary-dot
calls reject both known and missing member names; colon accepts known Copy and
typed local list Copy accepts. Source hashes and exact diagnostics are in
byond_observations.json. No runtime is started.

run.py uses explicit compiler/template SHA pins, serial 30 second children,
90 second overall watchdog and one 4GiB owned Job with unconditional reap.
Default both compares acceptance and source-rejection classes; --backend
byond-only needs only pinned DM flags. Outputs default to E:/dq-cache/.
