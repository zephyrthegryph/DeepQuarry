# Sequential runtime-issued normal suite

`tools/build/build.sh dm-test --normal-batches=8` compiles once, boots an inventory-only world, then runs sequential isolated focus batches through the existing acquired-output runner. This mode requires unfiltered normal tier and does not accept shard/focus/domain/incremental selections. Each world has a maximum300-second watchdog, including when the timeout environment requests longer. Nothing in this guide authorizes an agent to run the full suite.

Inventory comes from compiled `RunUnitTests` selection and priority ordering. Its common eligibility predicate excludes focus-only and self-abstract types. Explicit automatic result rows are required per batch. The aggregate rejects duplicate, unexpected, missing or incomplete results and preserves original per-test failure/runtime details. Boot failure or watchdog interruption prevents a passing aggregate.

Evidence is incrementally written to `data/normal-suite/<unique-id>.json`, with the actual compiler provenance/acquired native pair identity, individual compiler attempt receipts, runtime executable SHA256/security, and runtime version explicitly unknown (`null`). The existing acquisition verifies native files; this mode never labels a BYOND fallback as native. The runtime hash is a pre-spawn observation, not protection against concurrent executable replacement.

For identical BYOND/native batch scenarios, supply `--normal-plan=<prior-receipt> --normal-plan-sha256=<SHA256>`, alongside the same `--normal-batches` size. Current runtime membership and automatic rows must exactly match that hashed plan. The receipt retains the actual observed order separately and reports whether its order differs from the supplied plan. The receipt hash authenticates those supplied bytes; it does not authenticate a complete source/resource closure. Run both compilers against an externally frozen source/configuration when making parity claims.

Existing runners and ordinary suite behavior remain in use; the new mode avoids regex-based test inventory discovery. No benchmark timing or whole-game correctness is admitted merely by issuing an inventory.
