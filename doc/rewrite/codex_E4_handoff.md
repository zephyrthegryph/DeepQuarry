# E4 analyzer test harness cache

Merge gates now cache compiled analyzer test harnesses under E:/dq-cache/analyze-test, keyed by source, lockfile, path dependencies, configuration, toolchain, target/profile/flags and canonical checkout. Every harness is executed on every hit; results are never reused. Checkout binding prevents env!(CARGO_MANIFEST_DIR) fixtures from silently testing a sibling. Executable or unclassified doctests fall back to Cargo. Compilation is serialized and uses two workers.

Controlled regression suite: ten cases covered (hit/miss, source/lock/toolchain/profile/build-target invalidation, local dependencies, harness arguments/failure collection, checkout identity, corruption, doctest fallback, mid-run input changes). Nine passed in the combined run; the one I/O timeout was diagnosed and its failure-only rerun passed. No Rust or DM compiler was needed for these tests. Final lane gate pending. No gameplay change, baseline change, merge or push.
