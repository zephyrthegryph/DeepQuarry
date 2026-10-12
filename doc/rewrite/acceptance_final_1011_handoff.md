# Acceptance final cohort handoff

Lane-ready stamped commit: `95cbd1cea269`. Branch: `codex/acceptance-final-1011`.
Tested master base: `eb6096546b`.

Converted 149 acceptance tables to native acceptance entries, reducing the legacy table inventory from 173 to 24. Ordered refusal text, actual wearer/mover contexts, slot admission, related tracked dependencies and override behavior are retained. No unrelated pin differences were blessed. Master snapshot conflicts were resolved with master files, preserving the converted source and current client fixes.

Verification: 41 focused tests passed, zero failures; production compilation had zero errors, DreamChecker zero diagnostics, analyzer and ratchets passed. Both dq_requirement_protocol_pin and dq_conversion_pin passed, together with native acceptance runtime/dependency and old-behavior grouped tests. Lane-ready ran incremental look pins with an empty change set, not a full sweep. No full suite ran.

The remaining 24 tables and compiler retirement remain on a separate draft. Four garment Initialize name assignments must use their setters before the final tracked-name requirements can land; the user assigned those writers to the init lane. No baseline increase or debt annotation was used to bypass them.

Existing coalesce_runs, test_prompts and NIF cache leak diagnostics are being repaired in the separate hygiene branch. This handoff does not claim that cleanup is complete.
