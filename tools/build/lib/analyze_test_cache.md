The `analyze-test` build target caches compiled Cargo test harnesses in
`E:/dq-cache/analyze-test`. Merge gates use this target instead of recompiling
the analyzer tests on every gate. A hit executes every harness again; it does
not reuse test results. Failures are collected across harnesses, matching
`cargo test --no-fail-fast`.

The key includes analyzer sources and fixtures, Cargo.lock, every local/path
dependency reported by locked Cargo metadata, Cargo configuration, toolchain
versions, platform, target, profile and compilation flags. The default test
profile remains Cargo's `dev` profile. `DQ_ANALYZE_TEST_PROFILE` selects another
profile, `DQ_ANALYZE_TEST_CACHE` selects a cache directory or disables caching
with `off`, and arguments after the build target go to the Rust test harnesses.
Only a miss enters the machine-wide Cargo slot; compilation uses two workers.
Use the normal sccache environment for compilation.

Entries also include the canonical checkout path. Analyzer tests compile
`env!("CARGO_MANIFEST_DIR")` into fixture paths, so sharing those executables
between distinct worktrees would silently test the wrong tree. This deliberately
limits reuse to repeated gates in the same checkout until the analyzer's test
root protocol supports relocatable binaries. No analyzer source is changed.

The cache validates executable checksums and publishes complete immutable
directories atomically. Incomplete entries are misses; damaged entries are
retained under an `.invalid-` name rather than executed. Compilation and tests
are rejected if their inputs change during the run. No lock files are removed.

Executable or unclassified doctests conservatively fall back to the original
Cargo test invocation, so a future Rust example is never silently omitted.
The current analyzer has only non-executable examples and ignored doctests.

Controlled regression tests use fake Cargo and executable artifacts:
`bun test tools/ci/analyze_test_cache.test.ts`. They cover misses, hits, exact
harness arguments, all-harness failure collection, source/lock/toolchain/profile
and path-dependency invalidation, checkout binding, corrupt artifacts and
doctest fallback without compiling Rust or DM.

The cache is capped and disposable. After each run, entries (including stale
`.stage-` and `.invalid-` leftovers) older than `DQ_ANALYZE_TEST_MAX_AGE_DAYS`
(default 7) are removed, then the least recently used until the total fits
`DQ_ANALYZE_TEST_BUDGET_GB` (default 4). A hit refreshes the entry's recency;
the entry in use is never evicted.
