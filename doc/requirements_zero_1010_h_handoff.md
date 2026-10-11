# H: native simulation rule conditions

Base: fresh master `f18167ecb8`. Old-code metadata proof: `1cdbf28790`, eight focused tests passed (data/test-runs/20261011T010322_1cdbf28790.json).

This cohort replaces 12 production requirement-macro calls in 11 rule factories and four test calls in four factories: 16 calls across 15 factories. Rules now return immutable, interned unit-aware condition leaves, compiled into owned holder-only simulation trees. The rule consumer derives the existing threshold, band, key and difference subscriptions from complete ordered metadata. Conditions retain original units, comparison inclusivity, missing-property NOT behavior, cumulative hold pause/exit/rearm and dynamic right-hand-side wake behavior. Borrowed registry deletion fails closed and partial compilation failure releases its children.

Scope is simulation rules only. General op condition evaluation explicitly rejects native simulation nodes and leaves until a provider read-subscription contract exists; it never treats an unknown node as truthy. Remaining acceptance predicates and their consumers are not converted in H, and shared legacy macros/compiler remain for those callers.

## Behavior and pin causes

No behavior pin re-bless is intended for H. This is a representation and compiler-consumer change; all old numerical thresholds, operators, trigger dependencies and rule effects should remain equal. The committed old metadata fixture is preserved uniquely; enum assertion spelling changes to SIM_COMPARE names with byte-identical operator values. Existing materialized heat and integrity behavior remains the proof boundary. Any later incremental pin difference must be examined separately and attributed before blessing.

## Verification status

Old-code focused proof passed eight tests before conversion. Native generation passed; requirement_bool baseline update leaves 306 callback rows unchanged on this fresh base. Native compilation, ratchets and runtime verification are pending lane-ready.

Final focused selectors are in `rule-native-H-final-focus.txt`: both mandatory requirement/conversion pins, eight old-code rule selectors, native condition parent and empty-group child, deleted registry, two-property dependency wake and repeatable hold cleanup fixtures. The threshold selector is `/datum/unit_test/dq_rule_thresholds/representative`, not the exhaustive parent. No full suite is requested.

## Explicit limits

The current real domain provider exposes thermal nodes; the two-property dynamic RHS regression uses actual TRACKED keyed properties and a private registry. It does not fabricate a second thermal domain node. Generic op subscription support and acceptance-context migration remain separate work.

The old-code proof reported existing dview/latency diagnostic cache warnings and an act_taken allocation-counter warning in the representative threshold fixture. They remain queued for the separate hygiene landing; no cleanup is claimed here.
