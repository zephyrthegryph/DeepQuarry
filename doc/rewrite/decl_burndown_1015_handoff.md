# Declarative lifecycle burn-down — 2026-10-15

Branch: `codex/decl-burndown`.

## Result and scope

The declarative-lifecycle baseline shrank **47 → 6**: 41 rows removed, no additions. The original rows comprised 23 visual initializers, 10 starting-child sites, six destruction drops, five destruction effects, and one each of reagent initialization, registry membership and scheduling. Converted content uses existing native defaults, setup, starting relations and ending declarations. Baselines were updated by the analyzer, never hand-expanded.

## Engine forms

- `ref_one(..., starts =, starts_args =, early =, starts_after =)` optionally constructs a reference target without changing REF into ownership. Ordinary references allocate nothing; rejected/deleted targets are not adopted, and the target survives referrer deletion. `by =` resolution and starting construction are mutually exclusive.
- `setup(..., with_params = TRUE)` runs at constructor completion, after the full Initialize chain and before transient parameters disappear. Rejected constructors skip it; pending/parameter indexes are cleaned on handler failure. Default setup ordering remains unchanged.
- Registry `when` predicates are classified as initialization-only snapshots, matching existing runtime behavior. Reactive operation/periodic conditions retain their checks. The declaration lint distinguishes atom lifecycle from explicitly called datum business methods named Initialize.

Three targeted Rust regressions cover manual datum classification, initialization-only registry conditions, and reactive conditions containing quoted registry text.

## Six retained contracts

| Baseline site | Why it remains |
|---|---|
| `destroy_drop`, `code/game/objects/objs.dm`: generic `/obj/on_destroy` spill | Must retain LINKS ordering; a generic GUARD ending would run before descendant cleanup that inspects contents. |
| `destroy_drop`, `code/game/machinery/machinery.dm`: human/camera cleanup | Same LINKS ordering requirement; no global `/obj` or machinery ending was added. |
| `destroy_drop`, `code/modules/ventcrawl/ventcrawl_atmospherics.dm`: ventcrawler cleanup | Same requirement for descendant callbacks inspecting occupants. Concrete converted types have their own native endings. |
| `init_visuals`, `code/modules/overmap/sectors.dm`: unknown-sector concealment | Concealment must remain between overmap registration and the ship registration tail. Earlier setup changes registration; completion setup exposes the real name to vessel identity. |
| `init_new_child`, `code/modules/body/body.dm`: living body | Robot components are constructed before the living parent boundary. Starting body earlier exposes partial components and caused real power/movement runtimes. Original initializer and ownership remain. |
| `init_visuals`, `code/modules/pda/pda.dm`: pen overlay | Native `contents_of` read metadata exists (`7de6599bbc`), but physical movement into/out of a holder without a ledger/declared slot does not publish occupancy. Adding a slot changes topology. A physical-contents publication contract is needed; original PDA/app presentation remains. |

## Old-behavior proof

The shared old-production capture selected 55 tests (50 initially passed). Its three lifecycle fixture failures were traced to an existing statue mute leak, a correctly declined empty flipper emag, and hexadecimal color case. Bounded old-code repair selectors passed before conversion. The other two initial failures belonged to requirements. The old statue assertion recorded its defect; the final test checks actual stasis release. New engine-contract tests were excluded from old-code capture.

Coverage includes actual constructors, ownership/ref lifetimes, supplied MMI parameters, visuals, archaeological products, normal/forced destruction, deletion veto and released occupants. Shared constructor regressions cover internal storage, cloning and a pilotslug's real keyed timer. Telecube look-fixture cleanup observes actual reciprocal pairs before moving only those fixtures out of the map and deleting them; it does not clear production queues.

## Current verification and final repair

The gate at `70bbe160a0` passed production compilation, DreamChecker and ratchets. Its focused receipt `data/test-runs/20261016T022347_70bbe160a0.json` records **62 passed, two failed, zero skipped**. Both look sweeps, `dx_menu_order`, internal-storage/cloning and pilotslug regressions passed. Boot was clean; existing STATE LEAK warnings remain visible.

The two diagnosed failures are repaired in `00fe5debb2`:

- Conversion pin: only `ai_use_equipment` disappeared from `/obj/mecha` and `/obj/mecha/working/ripley`, inherited from master `f13b84652d` (2026-10-13). Expanded menus, clicks and all other keys were identical. Only those two literal key rows were promoted.
- Privacy fixture: raw test `set_var` bypassed publication. Both privacy fixtures now use existing `/area.set_flags`, including deferred restoration. Strict `privacy0 → privacy1` and actual flag assertions remain. Production privacy behavior is unchanged.

Causes are documented in `intended_changes.md`. The final failure-only selector file is `data/codex-decl/final-repair-selectors.txt`: mandatory requirement/conversion pins plus privacy and live-redraw fixtures. **That repair gate, final receipt and lane-ready stamp remain pending.** Earlier results are historical evidence, not a substituted stamp.

This gate explicitly used **DreamMaker/BYOND**, recorded in its receipt. Master `663e85e2ae` changed the default to native; a separate same-plan requirements diagnostic exposed host-dependent look sampling because the first 24 vars are chosen before plan filtering. Existing appearance goldens were preserved rather than blessing compiler-order drift. Backend choice and any remaining limitation must stay explicit in the final receipt.

## Completed lane-ready receipt

The final DreamMaker gate on source 79db428f3fac passed; lane-ready recorded look keys and stamped b4d8412911. Result: 53 passed, 0 failed (data/test-runs/20261016T032804_79db428f3f.json). Production compilation had 0 errors, DreamChecker 0 diagnostics; ratchets and analyzer tests passed. Both mandatory pins, both corrected privacy fixtures, both appearance pins and menu ordering passed. Existing fixture STATE LEAK warnings remain visible. This handoff-only follow-up uses the documented docs-only stamp carry rule, checked before pushing.
