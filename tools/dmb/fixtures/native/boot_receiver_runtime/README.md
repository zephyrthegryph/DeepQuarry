# Standalone boot receiver runtime contract

This isolates the first native game boot failure (`world/Profile`: cannot read
`.loaded`) without game assets, FFI or the full world. It exercises null-safe
global member access, unary negation, bitwise/short-circuit conditions and a
`/world/Profile` callback. A real global `new` config receiver verifies the
non-null branch. Semicolon-separated global list/hash/new declarations and an
earlier global constructor test initializer order and safe/direct method calls.

Both compilers must independently match all 15 ordered `DQ_BOOT` observations
in `run.py`, with zero runtime errors. Authenticated BYOND receipt `94588d09ebf64075a51e83626d697d97` proves early
constructor access sees a non-null HiddenInitializer sentinel, not a constructed
cache datum. The fixture therefore checks both `isnull == 0` and `istype == 0`,
and guards method access with typed availability; it emits no early direct-call
marker. Later access expects the initialized cache method to return 42. Null interpolation is empty
text, distinct from numeric zero. Agreement on an incorrect result is rejected.
The separate null global tests still exercise null-safe access. A non-null
initializer sentinel is deliberately not dereferenced: `?.` checks nullness,
not typed availability.

Run `run.py` with the authenticated `--native`, `--template`, `--dm`, `--dd`
and matching `--*-sha256` arguments in
`../power_retirement_runtime/README.md`, plus an owned E: `--output-root`.
The shared launcher retains SHA/version authentication, separate source copies,
owned watchdog cleanup, output pair acquisition and the sampled 4GB limit.
`test_run.py` checks the observation reader only. No execution is claimed by
adding these files. This fixture does not establish full game boot correctness.
