# Machinery requirement migration audit (2026-10-08)

Audited `origin/master` / branch base `4375b8068230378f8abaf8920c7a62158d458337`. The initial audit was read-only. The subsequent three-file declarative conversion and focused behavior tests are recorded below; verification is performed by the root agent.

## Actual remaining inventory

There are **zero executable uppercase `REQ_*` macros** in `code/game/machinery` and `code/modules/power`. The uppercase names survive only in comments. The initial inventory had **24 former-REQ boolean adapters in 18 machinery files**, and **zero in power**. Four adapters have now been replaced by existing declarative requirements in CableLayer (1), bomb tester (1), and painter (2), leaving **20 comment-tagged adapters in 15 machinery files** (a historical subset, not the complete inventory). These adapters call old `(actor, target, held)` helpers, convert TRUE to pass, and often pair that with a separate refusal proc. Merely deleting comments or renaming helpers would not implement the requested null-or-reason protocol.

| File | Adapters | Legacy helper names |
|---|---:|---|
| `code/game/machinery/computer/aifixer.dm` | 1 | `can_use_card` |
| `code/game/machinery/computer/arcade.dm` | 1 | `wants_payment` |
| `code/game/machinery/computer/guestpass.dm` | 2 | `can_insert_id, dq_actor_can_act` |
| `code/game/machinery/computer/prisonshuttle.dm` | 1 | `can_open_console` |
| `code/game/machinery/computer/skills.dm` | 1 | `within_contact_range` |
| `code/game/machinery/computer/supply.dm` | 1 | `lets_in` |
| `code/game/machinery/cryopod.dm` | 2 | `can_take_occupant, can_enter` |
| `code/game/machinery/floor_light.dm` | 1 | `can_switch` |
| `code/game/machinery/food_replicator.dm` | 1 | `dq_actor_can_act` |
| `code/game/machinery/nuclear_bomb.dm` | 3 | `is_extended, dq_actor_can_act, can_make_deployable` |
| `code/game/machinery/partslathe.dm` | 1 | `can_load_item` |
| `code/game/machinery/rechargestation.dm` | 2 | `is_vacant, grab_holds_living` |
| `code/game/machinery/robot_fabricator.dm` | 1 | `wants_steel` |
| `code/game/machinery/virtual_reality/ar_console.dm` | 1 | `dq_actor_can_act` |
| `code/game/machinery/virtual_reality/vr_console.dm` | 1 | `drag_meant` |

## Framework gap: custom requirement protocol

The engine on this master still requires boolean predicates:

- `code/engine/parts/cond.dm:163`: `req(PROC_REF(x), because = ...)` explicitly documents TRUE/FALSE.
- `code/engine/parts/cond.dm:194`: generic `holds()` returns `!!op_call(A, what)`.
- `code/engine/parts/cond.dm:122`: part `require()` delegates to boolean `holds()`.
- `code/engine/parts/cond.dm:129`: refusal is evaluated independently, through `because` or the default reason.
- `code/engine/parts/requirement.dm:10`: unsupported legacy requirement objects fail; no null-or-reason callback constructor exists here.

Consequently changing a helper to return null on success makes a valid action fail. Returning a textual refusal makes the boolean predicate pass. No machinery-only conversion can wire a single null-or-reason callback to this engine without an adapter/workaround or an engine protocol addition. The requested custom requirement migration is blocked on that final form. `starts()` returning a reason is an effect-stage feature and must not substitute for a pure requirement.

## Declarative replacements already usable

These are genuine existing forms, not new custom callback semantics:

- `painter.dm`: empty insert slot can use `req_empty(nameof(inserted), because = ...)`; operable click-selection can use the existing `req_operable()` as its boolean `when` gate. Preserve the existing distinction between selection and refusal.
- `nuclear_bomb.dm`: extended click-selection can use `req_is(nameof(extended))` only after confirming the variable is tracked (it currently carries an untracked-read ALLOW). Do not add another ALLOW.
- `bomb_tester.dm`: free tank selection is a disjunction of two empty slots; existing `any_of(req_empty(...), req_empty(...))` can express it if those slots are declared correctly.
- `CableLayer.dm`: `any_of(req_full(nameof(cable)), req_is(nameof(on)))` can represent the current cable-or-on test, retaining its explicit refusal text. A zero-count cable object currently satisfies the pointer test; preserve that behavior.
- `rechargestation.dm`: vacancy is a declared occupant slot, so use an existing slot-empty requirement only if its actual slot identifier and constructor are verified; do not invent an API. The held grab's living passenger is a cross-object predicate, not just a type test on the grab itself.
- The repeated `dq_actor_can_act` callbacks can potentially use `req_capable()` but must first compare semantics: the old helper's consciousness/mob-kind checks are not automatically identical to the new action stat gate.

Composite access policy, map contact levels, aifixer restoration state with dynamic reason, clawmachine vendor-account suspension, fabricator material identity, grabbed passenger state, and the preserving silent-swallow branches in parts lathe/nuclear bomb need actual case-by-case requirements. Existing boolean `req()` can still express them, but that is not the requested new null-or-reason migration.

## Recommended partitions once the protocol lands

1. Computers: aifixer, arcade, guestpass, prisonshuttle, skills, supply (7 adapters).
2. Other machinery: floor_light, food_replicator, nuclear_bomb, partslathe, robot_fabricator, rechargestation (9 adapters).
3. Occupant/VR: cryopod, ar_console, vr_console (4 adapters); coordinate cryopod with its prompt conversion.

Do not alter the draw-items lane's charge/shot writes. No changes to framework code, baselines, ceilings, or annotations are proposed by this report.
## Declarative conversions applied

- CableLayer: `any_of(req_full(nameof(cable)), req_is(nameof(on)))`, both carrying `MSG(cablelayer/toggle_no_cable)`. Its text is exactly "doesn't have any cable loaded". `any_of` deduplicates identical refusal texts. Presence remains a pointer-presence check, so an empty cable-coil object retains the previous semantics. `on` already has `TRACKED_BRIDGED` in machinery_fields; no new annotation.
- Bomb tester: selection uses `any_of(req_empty(nameof(tank1)), req_empty(nameof(tank2)))`, on the two declared `OWN_CONTAINED` relations. A full tester falls through rather than introducing a new refusal.
- Painter: selection uses `req_operable()`, the same `STAT_OPERABLE` read as its existing `operable()` proc. Insertion uses `req_empty(nameof(inserted), because = MSG(gear_painter/loaded))` with the exact text "the machine is already loaded". The existing ownership declaration supplies the relation.

Three focused behavior tests were appended to the existing `dq_hc_machinery_behaviour.dm`: `dq_hc_struct/cablelayer_declarative_requirement`, `dq_hc_struct/painter_declarative_requirement`, and `dq_hc_struct/bomb_tester_declarative_requirement`. They exercise actual operation input, state changes and exact refusals/selection fallthrough. Their results must be reported after the root's focused batch, not assumed.

These four conversions do not provide the missing custom null-or-reason callback protocol. The remaining 20 comment-tagged adapters are part of the broader inventory below; they are not the complete callback count. No engine, ceiling, baseline or ALLOW change was made in these conversions.
## Expanded adapter inventory (completeness correction)

The initial 24-to-20 count counted only the explicit `was REQ_*` comments. A complete scan of operation callbacks delegating to old `(actor, target, held)` checks identifies **39 remaining logical adapters across 23 machinery files and one power file**. A holds/refusal pair is counted once; callbacks used only for selection still appear because they retain the old check interface. The pre-conversion comparable total was **43**, reduced by the four declarative conversions. The 20 comment-tagged adapters listed above are a subset of these 39.

Additional 19 adapters, beyond that tagged subset:

| File | Count | Callback / old helper |
|---|---:|---|
| `code/game/machinery/bioprinter.dm` | 1 | `printer_menu_allowed` / `can_open_menu` (held-provider argument, paired refusal) |
| `code/game/machinery/camera/camera.dm` | 4 | `actor_can_shred_holds`, `paper_show_meant_holds`, `camera_can_use_holds`, `held_is_bashing_holds` |
| `code/game/machinery/computer/law.dm` | 3 | AI `can_select_ai_holds`, `can_connect_holds`; borg `can_select_borg_holds` (paired refusal callbacks) |
| `code/game/machinery/computer/pod.dm` | 1 | syndicate `lets_in_holds` |
| `code/game/machinery/floor_light.dm` | 1 | item `can_install_holds` (paired refusal; also checks actor turf membership) |
| `code/game/machinery/frame_construction.dm` | 2 | `native_board_fits` / `accepts_board`; `native_has_components` / `has_all_components` (`read_once`, paired board refusal) |
| `code/game/machinery/pandemic.dm` | 1 | `beaker_item_holds` / `is_beaker_or_syringe` |
| `code/game/machinery/suit_storage/suit_cycler.dm` | 4 | `can_insert_grabbed_holds`, `can_insert_helmet_holds`, `can_insert_suit_holds` (paired refusal); `cycler_actor_can_act` / `dq_actor_can_act` |
| `code/game/machinery/suit_storage/suit_storage.dm` | 1 | `storage_entry_ready` / `storage_entry_reason` / `can_move_inside` |
| `code/modules/power/singularity/particle_accelerator/particle_smasher.dm` | 1 | `actor_can_act` / `dq_actor_can_act` |

This count is deliberately **logical legacy adapters**, not grep occurrences: refusal pairs duplicate calls; direct return adapters omit `var/answer`; VR uses `typed_held`; bioprinter uses `held_provider()`. Conversely `_holds` names such as heavy-coil type selection, privacy-switch cooldown, computer gripper-content selection and washer actor-containment are direct native predicates rather than wrappers around old three-argument helpers.

`cloning.dm:284` has `container_space(datum/act/op/A)`, a direct boolean predicate comparing `read_once(LAZYLEN(containers))` with `read_once(container_limit)`. It is not an old three-argument adapter, but it **also cannot be changed to a null-or-reason custom requirement on this engine**. The same applies to other direct native boolean custom predicates in these folders: the 39 adapter inventory does not claim they all disappear if those legacy delegates are converted. They require the final custom-requirement callback protocol whenever the user's null-or-reason migration encompasses them.

No additional production code was edited during this expanded audit. The engine gap remains exactly the same: generic `req(PROC_REF(...))` booleanizes its callback result. The machinery/power-only restriction prevents implementing that missing engine protocol here.
## Separate existing click-ranking defect

The first requirement verification found that a plain item click on painter or bomb tester opens the interface instead of loading. `interface()` creates `ui_open` at OP_PRIORITY_DEFAULT (`code/engine/parts/part.dm:793`); their typed insertion/loading actions use DEFAULT - 1. `hand()` matches the target even with an item held (`resolve.dm:183`), and tier sorting precedes binding specificity. These tiers predate this branch and were not changed by the requirement conversion. The focused requirement regressions now select the public loading menu operations (test_menu), exercising native requirements, held items, real effects and custody. Click priority is reported separately, not blessed as an intended requirement change.
