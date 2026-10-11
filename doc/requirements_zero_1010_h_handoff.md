# H: native simulation rule conditions

Landing branch: `codex/rule-conditions-native-1011`, merged onto master `73c3f0fbc8`. Original H base: `f18167ecb8`. Old-code metadata proof: `1cdbf28790`, eight focused tests passed (data/test-runs/20261011T010322_1cdbf28790.json).

This cohort replaces 12 production requirement-macro calls in 11 rule factories and four test calls in four factories: 16 calls across 15 factories. Rules now return immutable, interned unit-aware condition leaves, compiled into owned holder-only simulation trees. The rule consumer derives the existing threshold, band, key and difference subscriptions from complete ordered metadata. Conditions retain original units, comparison inclusivity, missing-property NOT behavior, cumulative hold pause/exit/rearm and dynamic right-hand-side wake behavior. Borrowed registry deletion fails closed and partial compilation failure releases its children.

Scope is simulation rules only. General op condition evaluation explicitly rejects native simulation nodes and leaves until a provider read-subscription contract exists; it never treats an unknown node as truthy. Remaining acceptance predicates and their consumers are not converted in H, and shared legacy macros/compiler remain for those callers.

## Behavior and pin causes

No behavior pin re-bless is intended for H. This is a representation and compiler-consumer change; all old numerical thresholds, operators, trigger dependencies and rule effects should remain equal. The committed old metadata fixture is preserved uniquely; enum assertion spelling changes to SIM_COMPARE names with byte-identical operator values. Existing materialized heat and integrity behavior remains the proof boundary. Any later incremental pin difference must be examined separately and attributed before blessing.

## Verification status

Old-code focused proof passed eight tests before conversion. Original H native generation passed; its original requirement_bool update left 306 callback rows unchanged on that base. This fresh landing also carries the separately verified hard ban: the current baseline is zero and req_bool is deleted. Native production/test compilation passed with zero errors and DreamChecker reported zero diagnostics on `883f8476c74a`, merged with master `09381885a5`. Production has 43 existing DreamMaker warnings; test compilation has 57. The final focused gate passed 27/28 tests, including the repaired repeatable-hold fixture and requirement protocol pin. Its sole conversion-pin failure was three unchanged holder diagnostics whose source stack line moved in master `d7f737b36b`; the cause is recorded in intended_changes.md. After refreshing only those rows, the failure-only retry passed 1/1 using the existing test binary: `data/test-runs/20261011T023209_be153fd0a7.json`. The initial ratchet process ran out of shared-machine memory; a targeted retry passed every ratchet (`h-final-ratchets-memory-repair.log`). Both final worlds passed the boot gate with zero pre-test runtimes/warnings. No full suite ran. The original lane-ready run did not stamp the combined repair evidence. The owner has now requested a fresh stamped landing; its verification is pending on the merged branch.

Final focused selectors are in `rule-native-H-final-focus.txt`: both mandatory requirement/conversion pins, eight old-code rule selectors, native condition parent and empty-group child, deleted registry, two-property dependency wake and repeatable hold cleanup fixtures. The threshold selector is `/datum/unit_test/dq_rule_thresholds/representative`, not the exhaustive parent. No full suite is requested.

## Explicit limits

The current real domain provider exposes thermal nodes; the two-property dynamic RHS regression uses actual TRACKED keyed properties and a private registry. It does not fabricate a second thermal domain node. Generic op subscription support and acceptance-context migration remain separate work.

The old-code proof reported existing dview/latency diagnostic cache warnings and an act_taken allocation-counter warning in the representative threshold fixture. They remain queued for the separate hygiene landing; no cleanup is claimed here.

## Fresh stamped landing

Lane-ready passed on 004fda4625b6ee824fe79c909f57e777f41dec27 against master 73c3f0fbc8: 40 passed, zero failed. Production/test builds had zero errors (43/57 existing warnings); DreamChecker had zero diagnostics and all ratchets passed. No pin re-bless or rerun was needed. Result logs and stamp are in data/merge-gates/004fda4625b6 and the lane-ready git note. Existing fixture STATE LEAK warnings remain queued for hygiene; they were not suppressed or repaired here. The baseline remains zero. REQ_ raw tracked-code occurrences fell 801 to 785; PRED_ occurrences fell 362 to 317. These literal counts include tests and snapshot text; the migration count is the 16 actual calls above.
