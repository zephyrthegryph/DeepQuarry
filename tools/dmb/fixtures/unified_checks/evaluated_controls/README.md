# Evaluated control roots (bounded undefined-proc cohort)

Reference: SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc, GPL-3.0.
Independent dreamchecker.exe SHA256:
`bafd54168a539e61d8c3f71d9778e92de76d7ffbf11c693541e10be10c9633ba`.

The reference emits exactly 28 untagged error diagnostics, in source traversal
order. C-style loop increment precedes body; range end and step precede declared
start; do-body precedes condition. No reference diagnostic is filtered.

Compare native example `native_evaluated_calls` output against the exact pinned
checker with `compare_native_checker_fixture.py --family undefined_proc` and this
`.dme`, using the script's command arguments (never a fabricated expected model).
The native family still explicitly fails unsupported variable/static-type,
constructor, directive and lexical contexts; these fixtures do not certify full
checker or full undefined-call parity.
