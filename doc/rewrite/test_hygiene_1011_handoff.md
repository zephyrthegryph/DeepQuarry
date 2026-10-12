# Test hygiene handoff

Branch: `codex/test-hygiene-1011`. Lane-ready tested and stamped
`6176e3f2e69c` against master `f359190806`.

- `tracked_tests`: 225 → 0. Ordinary test writes now use actual setters.
- The intentional missed-publication fault uses a guarded, analyzer-validated
  test driver; the sequence audit still detects and repairs the real fault.
- Known fixture state leaks are scoped/restored. A detected STATE LEAK now
  changes the test's final result to FAILED instead of retaining PASS.
- The runtime clock is not backdated by the generic test wrapper.
- Appearance probing excludes fundamental base fields without losing legitimate
  leaf fields. A real slime regression proves the shiny branch. The rifle
  regression proves starting-stock parity; its test-only lever subtype is
  abstract and excluded from production pin discovery.

The final normal lane-ready run passed **32 tests, zero failures**, including
`dq_requirement_protocol_pin`, `dq_conversion_pin`, both appearance pins, the
rifle and slime regressions, and the STATE LEAK status guard. Production compile
had zero errors; DreamChecker found zero diagnostics; analyzer and all ratchets
passed. No full suite was run.

Earlier repair evidence includes 27 targeted Rust fault-validation tests and
the failure-only prompt/UI/counter repairs. Earlier interrupted runs are not
stamps. The final stamp comes from the normal run above.

Pin changes are narrowly documented per class and cause in
`intended_changes.md`: 62 state rows, 31 tree rows and eight appearance-changer
color-format rows. Test-helper pollution was removed by fixing discovery,
not by blessing its rows. Actor names and nutrition were fixed in fixtures;
their goldens were retained.
