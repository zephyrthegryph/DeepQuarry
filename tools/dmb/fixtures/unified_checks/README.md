# Bounded checker observations

These fixtures compare explicitly migrated diagnostic families. They do not
establish full checker, parser, configuration or runtime parity.

`proc_group_order` covers interleaved ordinary overrides. `proc_group_adversarial`
covers lexical path traversal despite explicit `parent_type`, plus a bodyless
declaration reserving its proc group's position. Its child `probe` is an override,
not a repeated `/proc/probe` declaration: DreamMaker 516.1687 correctly rejects
the latter as a duplicate inherited definition, although pinned DreamChecker
0290db5c752fa292f9824521515b603a2afd11dc accepts it. Native compilation keeps that
rejection; checker-only acceptance of invalid DM is outside this source domain.

The late-formal ordering case stays in `checker_order_tests.rs`, not a
family-specific differential fixture. A same-owner override followed by its
formal declaration is legal when a `/proc` block appears beforehand (verified
with DreamMaker 516.1687, zero errors or warnings). The pinned parser additionally
records an `override_precedes_definition` Hint, which its default CLI does not
print. No reference diagnostic filtering is used to hide this extra family.

`literal_cr_segments` is byte-seeded (do not normalize its line endings). The
independent pinned checker emits static/if-determinate pairs at (2,7), (5,7),
(9,7), (14,7), (22,7): CR-only and raw CR are true; escaped CRLF alone
is false; its following extra LF is true, whereas escaped LF plus one LF is
false. CR inside interpolation contributes no literal segment. Native runtime
cooking remains unchanged; primary-issued segment ranges project onto raw bytes.

`literal_cr_boundary_gap` is intentionally outside the supported differential
cohort. Pinned escaped CR followed by `[a]` creates an interpolation and produces
no diagnostics. Existing native runtime CR normalization instead produces the
literal text `[a]`; lexical policy explicitly refuses that mismatched boundary.
This is an actual unresolved compiler lexical contract, not a fabricated invalid
source or filtered reference diagnostic. Atomic unsupported tests use this case.
