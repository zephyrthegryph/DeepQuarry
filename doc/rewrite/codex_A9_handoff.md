# A9 initialization sweep

Branch `codex/A9`, WT `E:/projects/dq-wt/codex-A9`, base `d36a5946fb`.

21 production files changed, one five-test file. Analyzer-certified baseline: 4115 -> 4066 (49 removed), decl 47 -> 46. Source estimate 185 -> 135 was approximate; exact analyzer result controls. Exact retained identity inventory and raw bodies are in remaining-text-audit.txt.

Native setup jobs cover fighter/hoverpod ion trails, damaged-component integrity, cable-length mirror, inflatable deployer link, combat shield settings/back-link, syringe synthesizer startup, spent 14.5mm casing, harpoon failure rating, initial macrobattery charge + repeat gate, kinetic charge draining, pneumatic hopper settings, magic charge, magnetic capacitor charge + rating, material-fed gun cost/rating, leaf projectile transforms, spikethrower initial cooldown, blob chemicals, life-crystal state and micro carrier species sprite.

Verified forms: setup() definition/code and existing examples under code/engine/lifeforms/setup.dm; ancestor-first post-chain jobs, no newly invented form. For one-line meaningful hooks the block calls the existing proc directly, not a wrapper. The phoronbore no-op Initialize was deleted. No RNG was concealed in setup.

Order proofs:
- Component damage completes before its real constructor returns and before mecha C.attach(). No component descendant initializer found.
- The magnetic ancestor and matfed child jobs migrated together, preserving capacitor charging before child ratings/cost. Remaining railgun child initializer only handles layout and transform; it does not read capacitor charge or power_per_tick.
- No live Initialize descendants were found for the other moved types. Gun base firemode application stays before all inherited equipment setup.
- Macrobattery's existing charge setters and gate update retain their order. The ammunition parent supplies the projectile first.
- Combat shield's declared projector already exists before setup; settings and back-link remain together.
- Mini-uzi has two legacy initializer definitions in automatic.dm and automatic_serdy.dm. The serdy transform call is now declared; automatic.dm's conditional transform remains constructor-local. update_transform recalculates from the same initial transform. z8's setup entry was placed in its existing canonical block in automatic.dm; no second block.
- Micro holder reads the durable held_mob relation after the parent captures it. No descendant Initialize exists; its species-dependent sprite data is ready before returning to callers.

Protected TRACKED, ownership/reference declarations and existing setter-call text preserved. Four moved micro-holder sprite writes use existing setters; generated tracked check passed with zero sites. All debug/logging retained.

## Complete retained cohorts

- Old durand/gygax/marauder/phazon/odysseus/mining ripley: stateful random cell charge depends on the cell built by the mecha parent, alongside damaged integrity. rolls() targets holder state, not another owned entity's mutable charge; converting starts would alter protected ownership declarations. Retain ordered pair with exact existing setter.
- Base mecha: creates and attaches type-table components/equipment, opens icon and establishes radio/cabin/tank/smoke/cell, logs creation and issues loc.Entered. Descendant old/mining initializers consume the cell/contents. Moving base alone would run after those consumers; starts+attachment policy migration needs protected declarations. No blanket rename.
- Mining ripley: density-independent random drill attachment and deletion of tracking beacons; relies on base component/slot contents having already been populated. Native spawn plus attach policy requires the same coordinated assembly migration.
- Rectangular mecha shield: constructor-location mecha link, movement observation and recursive movement registration. Needs typed owner-context declaration and preserving parent shield initialization phase; not moved blindly.
- Ammo magazine: constructor forge_material affects round identity (lathe passes it), latent initial ammunition and initial icon-cache preparation are ordered with constructor flags. Preserve forge input and parent/child material setup; existing tracked setters remain exact.
- Gun base: scoped_accuracy captures constructor accuracy and chosen firemode applies fields before every gun-subclass initializer. Post-chain migration would apply it after subclass part/charge setup and change results.
- Energy gun base: conditional self-recharge/cell_type starting child selection and optional random owned-cell charge. Proper starts conversion requires protected ownership declaration changes, not moving a creation body into setup.
- Laser and railgun: map/subtype geometry fields (is64x32_override, expected width, icon) decide their conditional transformation. Keep per-instance layout handling and its constructor ordering.
- Modular gun: CheckParts() changes component/charge inputs and FireModeModify() reconfigures firemodes; needs coordinated base-gun acceptance/assembly forms and cannot move after base firemode selection blindly.
- Projectile gun: starts_loaded and allowed magazine policy plus random removal of owned ammunition; protected ownership/magazine declarations need native starting-ammo policy. Conditional type-table transform stays here.
- Automatic mini-uzi and pump: conditional geometry transform tied to actual per-instance is64x32 layout; other unconditional leaf transform calls migrated.
- Pirate pistol (both world_reads): chooses a correlated ammo type, description and caliber before the parent creates ammo. A post-init hook would load the old caliber, and a single independent roll target cannot express all three without a proper preinit declaration/context. Retained rather than delaying RNG.
- Sniper barrel/stock/trigger: constructor establishes self-relation identity for assembly; leave existing relation protocol intact rather than change protected ownership/assembly declarations.
- Projectile base: constructor-location casing identity is needed while the casing's own Initialize is still running; retained typed relation binding.
- Aiming overlay: constructor-location mob binding, invalid-holder deletion and nullspace relocation stay as one validity protocol.
- Belly: list sharing before anything reads the lists, initial mob owner registration/owned vore-organs and scheduling; parent/mob constructor ordering and protected relation policies preclude safe standalone migration.
- Soulgem: constructor-location mob owner binding; retain per-instance relation input.
- Fluff box: has_items controls pre-parent storage capacity and starting contents. Proper starts needs protected contents ownership configuration; moving children post-parent can violate storage admission.
- Vulpine utility belt: starting tool contents need starts with argument-bearing cable-coil construction, which modifies protected contents declaration.
- Charlotte fancy storage: default open/closed states depend on subtype initial icon before parent uses them. Per-instance/map state retained.
- Antoinette harness: inherited storage setup before capacity override and starting constrained knife/bottle; requires the coordinated base-accessory/contents declaration conversion, owned by other scope.
- Tempest soundloop row was already absent in current source (stale baseline); analyzer update should remove it independently.

## Root verification

No build/test/gen/baseline/manifest/commit/merge/push performed. git diff --check passes. Cross-tree new CAPABILITIES audit found and fixed z8's outside-file canonical block; protected-text comparison clean.

Root include: `#include "code\modules\unit_tests\dq_a9_initialization_tests.dm"`.
Focused selector: `/datum/unit_test/dq_a9_initialization` (component_damage, macrobattery, pneumatic_hopper, magic_charge, shield_configuration), plus task-required `dq_look_pin`.

## Exact retained site identities

[Committed residual inventory](codex_A9_residual_sites.txt) lists every retained source identity from this lane’s post-edit audit, including repeated normalized rows. The per-file reasons above classify those identities; this is a source audit snapshot, not a fresh analyzer verdict after rebasing. Master’s subsequently removed declarations and rewritten setters must remain authoritative, and the root verification will establish the final baseline counts.


Source audit repair (2026-10-15): the newly added setup declarations referenced inherited procs with PROC_REF, which checks a current-type proc path. Changed only these new hook references to TYPE_PROC_REF at the actual defining ancestor: `/obj/item/ammo_casing/a145/spent` → `/obj/item/ammo_casing::expend`. Hook names and dynamic dispatch remain unchanged; no wrappers, declarations, setters or behavior changed. No generation, analyzer, compile or test was run for this source-only repair. Verification remains with the A coordinator.
