# Cleanup: edit markers, snippets and lifecycle presentation

Branch: `codex/cleanup-lifecycle-docs-1014`, based on master `874b916db2` in a new E: worktree. No old migration branches are merged into it. This branch will not be pushed.

## Edit markers

Removed all 36 marker comments in 18 files. The disabled saddlebag implementation inside the marked block was deleted as dead commented-out code. Active code and text literals are unchanged, and original source encodings are preserved.

## Documentation

All 50 stale baseline sites were covered by 34 obsolete complete examples in seven documents. Those examples were removed and replaced with references to their actual live implementations. The archive and final API design are unchanged. The doc-snippet lint passed and its baseline shrank from 50 to zero.

## Constant icon defaults

Two of the 23 rows are unconditional type constants:

- `/obj/structure/lattice`: `latticeblank` is now the default; smoothing and neighbor updates remain in initialization.
- `/obj/structure/prop/machine/nt_pod`: `nt_pod` is now the default; its mask, visual parts and contents setup remain.

Runtime presentation is intended to remain identical. Editor defaults consequently change from `latticefull` and `nt_pod_mappreview`, respectively. Neither initializer became empty apart from parent chaining.

The other 21 rows remain because they are instance-dependent:

- Mirror: `mirror_frame` is conditional on the building constructor argument.
- Reflector: the overlay is built from its deflector state and rotation.
- Shuttle wall: `base_state` depends on the subtype or mapped instance and join group.
- Off-ear clothing: copies its containing object's current state.
- Dark maw (two rows): used state depends on light exposure or trigger state.
- Overmap sector: unknown appearance depends on discovery and its concrete sector state.
- PDA: pen overlay depends on the chosen icon family; it is not an icon-state constant.
- Privacy switch: depends on its actual area's ghost-sight state.
- Micro holder: depends on the held occupant and its species.
- Artifact: depends on its instance icon number, which may be randomized.
- Archaeological find (ten rows): states depend on the selected find kind; statuettes, gas items, pens and crystals also have random branches. These are one runtime find type, not separate constant subtypes.

`dq_look_pin/cleanup_type_defaults` exercises a surviving lattice on a real open turf, its delayed four-neighbor smoothing, and the initialized pod's mask and three visual parts. The existing `dq_look_pin` is also selected; no look golden is re-recorded.

## Destruction consequences

All six `destroy_drop` and five `destroy_effects` rows already use `on_destroy(force)` on master. There are no corresponding `Destroy()` overrides to migrate. The new statue regression exposed a phase-order bug: automatic slot spill happened before the specialized cleanup, leaving the released subject muted. Its unchanged cleanup now runs through declared `on_ending()` before spill; `destroy_drop` shrinks from six to five. The other ten rows remain specialized hooks rather than renamed debt.

Nine real-qdel tests cover the eleven rows: machine occupants and perspective, generic micro holders, micro-tunnel camera and message, ventcrawler release, statue mute and injury-stasis removal, belly ghost release, gargoyle crumble message, telecube mate unlink/message, and crystal phoron/ordinary debris. Crystal assertions count only newly created shards. The telecube test uses a nullspace mate and verifies its message and reverse-link cleanup; it does not claim explosion-propagation coverage.

These specialized consequences include cleanup that a generic spill policy would lose. No annotation, baseline increase or new framework workaround is introduced.

The gargoyle regression also exposed transient constructor arguments being discarded before `setup()` read them. Argument disposal now follows setup, preserving rejected-holder handling. A direct setup-argument test verifies consumption, clearing and rejection.

## Verification

Initial lane-ready: production and test builds had zero errors; DreamChecker had zero diagnostics; ratchets passed. The focused batch passed 59 tests and failed the two destruction regressions above plus `dq_conversion_pin`. The latter reports master-side internal-storage and cloning initialization runtimes and stale mecha operation keys. Repairs and final verification are pending; no failed proof is stamped or recovered.
