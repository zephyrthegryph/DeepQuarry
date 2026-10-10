# Equipment-fit and simulation-rule requirement protocol proposal

Read-only audit; no production conversion, generation, build or test. The older audit's counts are historical, not a newly measured count.

## Proposed future work

Two consumer migrations are required, separately: (1) equipment/containment acceptance using the native null-or-reason requirement contract; (2) simulation-rule condition compilation with an explicit dependency/threshold model. Replacing REQ_* tokens alone is invalid. Neither consumer migration is implemented by this proposal.

## Existing forms versus missing forms

Existing: `req(PROC_REF(x))` returns null/reason; type `req(T, of =)`, `all_of`, `any_of`, `because`, `req_is`, `req_at_least`, native requirement `read_keys(A)`, `on_change`, tracked setters, declared slots accepting a type/list. Existing consumer APIs already return null/reason for equipment refusals, but their producers still compile legacy predicate lists. No complete native body-fit requirement, item constraint declaration/override contract, or unit-aware simulation property-comparison declaration was found. Proposed names below describe interfaces only, not callable forms on master.

## Exact equipment boundary

- `code/datums/properties/constraints.dm:45-88`: constraint_spec maps TYPE_TABLE fit_spec/equip_spec/hold_spec/suit_storage_spec; dq_constraint caches by kind/type with tracked instance overrides, then dq_constraint_refusal calls predicate.why_not(actor, thing, null).
- `constraints.dm:93-159`: set/clear/adopt_constraint, restrict_hold, restrict_fit, and dq_fit_bodytypes are real consumers/producers. They require instance override, explicit no-constraint, adopt/sharing and introspection semantics, not merely an equip callback.
- `code/datums/properties/equip_slots.dm:122`: shared per-slot predicates; :157 onward dq_equip_refusal checks slot existence/species slots, body-slot refusal, occupancy/over-wear, obstruction, then item constraints. Action slots backpack/tie have a distinct branch. :202 item fit is skipped for pockets and suit-storage; equip constraints are not skipped.
- `code/modules/body/slots.dm:63-73`: body slot calls wearer.body_slot_refusal first, then evaluates accepts with wearer as actor and inserted item as target. Do not substitute the external mover as the wearer.
- `code/engine/refs/containment/slot_def.dm:222`: general legacy slot refusal evaluates accepts with mover as actor, item as target, then holder_constraint. Native declared slot's :309 accepts currently supports type/list only; it cannot express body-shape, layered equipment, or arbitrary requirements.
- Slot rules in equip_slots.dm:216 onward return TRUE or a reason; every one must become null/reason with its caller, including suit storage, jumpsuit dependency, glove layering, both-ear occupancy, accessory compatibility and backpack insertion.

## Proposed equipment contract (new work)

One native requirement-evaluation entry point receives an explicit context: holder, candidate item, wearer/mover, destination slot and existing option flags. It returns null/reason and exposes its read dependencies. Existing op contexts can call it; direct inventory and relation moves must use the same evaluation path. Never create a second independent menu-only validator.

Item declarations need distinct fit/equip/hold/suit-storage channels and inherited ordered requirement composition. Preserve dq_spec_join's parent-before-child ordering; support a subtype replacing rather than appending a declaration. Instance override setters must distinguish unset (inherit) from explicitly empty (allow anything). Refit/adopt operations and bodytype introspection must remain supported by structured data; do not introspect callback text.

Body-fit is a library requirement over the wearer's actual body shape, including the legacy `exclude` list interpretation and exact `it only fits Teshari`/exclusion reasons. Engine declarations stay content-independent; the library implements body knowledge. Type constraints, wear tags and item capability reads become native requirements, without renaming the legacy predicate compiler.

Example mapping, conceptual only: Teshari-only glasses declare a fit requirement on the wearer; pocket placement deliberately bypasses that fit channel; all normal worn slots evaluate it after slot/body/occupancy/obstruction gates. A belt checks the wear tag then the jumpsuit requirement and preserves `you need a jumpsuit first`.

Dependency requirements: tracked constraint_overrides on the item; wearer body/species/slot-plan changes; slot occupancy and currently worn suit/uniform/gloves/ear/backpack; obstruction/coverage, item tags and material/size properties. Cross-object reads must register against their real owners. Immutable type declarations can be cached; acceptance results must invalidate on these dependencies, including same-tick changes. Static callback source read_keys alone is insufficient for a dynamic worn-item lookup; use supported runtime read capture or extend the engine consumer to record it explicitly. No manual `changed()` workaround.

Reasons: preserve first failing gate order, explicit overrides and silent refusal. Native all_of/any_of's default message composition must be compared against old predicates' all/any/negation/because reason generation; do not assume text parity. Keep old visible text until a separately justified intended change. The existing equip_refusal side-effect message wrapper remains outside the pure requirement.

## Exact rule boundary and proposal (new work)

`code/datums/rules/rule.dm:96-118` compiles condition into a predicate and traverses its node tree to derive triggers; a rule with no channel-backed or DM-key trigger is rejected. rule_compiler.visit (:210 onward) extracts numeric thresholds, bands, property comparisons and DM keys. `code/datums/rules/binding.dm:198-232` subscribes threshold/band/difference/key triggers; :267 check evaluates predicate; :293 onward maintains edges, exit effects, once/rearm and cumulative hold_for with pauses.

A rule is a simulation Boolean condition, not a player refusal. Proposed native condition nodes must retain (a) pure evaluation, (b) property units and compile-time compatibility checks, (c) complete dependency metadata, (d) threshold/band introspection for native domain watches and generated tests. A callback-only rewrite loses (b)-(d) and is not acceptable. Native requirement nodes may be reused for composition where meaningful, but their null/reason result must not invert rule truth, and simulation conditions need no player-facing refusal.

Example: ignition compares temperature >= ignition-point, both on the target, preserving Kelvin checks and provider watches. Overheating also needs the reverse edge to revoke its capability. Integrity break preserves the positive breaking threshold and ratio <= failure point, order before destruction, and repair exit. Cooking preserves cumulative paused hold time, not uninterrupted time.

Keep current rule binding scheduling/effects until the new condition compiler proves parity. Preserve strict-comparison epsilon, dynamic right-side property dependencies, missing-threshold rejection, key wake coalescing, no-trigger rejection, threshold generated-test enumeration and deletion cleanup. This is a framework/relations coordination item, not an isolated content token sweep.

## Migration / proof plan

1. Record old-code equipment pins plus explicit boundary tests: inclusive/exclusive shape lists, human/nonhuman, missing part/slot, tie/backpack action slots, jumpsuit/suit dependency, both ears, layered gloves, occupancy/overwear, obstruction, pocket fit bypass, instance refit/clear/adopt and inherited first-failure text.
2. Add same-clock warm-menu refusal/recovery tests after changing actual worn equipment, body shape and item overrides; also test direct inventory/relocation refusal, not just menus.
3. Implement and test native equipment consumer + structured declaration/override contracts. Convert a complete small cohort with all producers and direct callers, then grow; delete legacy tables/compiler only after the last remaining rule/predicate consumer is retired. Do not touch ix-r2 resolver/keybinding code.
4. Separately record thermal/integrity rule threshold/edge/hold behavior. Implement unit-aware native condition/dependency compilation, verify invalid unit/unknown-property/reversed-band errors and generated threshold metadata, then convert all rule declarations as one coherent consumer sweep.
5. Reuse focused `dq_constraint_parity/equip/representative`, `dq_constraint_reasons`, `dq_constraint_equip_reasons`, body-slot/containment tests, predicate combinator/unit tests and rule threshold/hold tests (validate exact active test names before one combined run). Pins preserve old behavior; no blanket REQ_ ban because request outcome constants are unrelated.

No proposed new forms should be used by content until they land. Continuing req_bool callback retirement is independent and safe while these contracts are reviewed.
