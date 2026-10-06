# Linking and observable order contract — Phase 0

Status: inventory and source probes, 6 October 2026. Four source probes were compiled and run by the coordinator under DreamMaker/DreamDaemon516.1687; paired preserved Build50 comparison now recorded below. Baseline: `ac1af55d1a`; format evidence is from that commit. This document distinguishes existing evidence from rules still requiring paired DreamMaker/native receipts. A cold-versus-incremental native oracle cannot prove DreamMaker order parity.

## Authority and acceptance

Every order below must depend only on the captured input occurrence stream, define set, compiler semantics and format version. Worker scheduling, hash-table iteration, cache presence and edit history cannot choose order. Preserve meaningful duplicates and reopen occurrences. An unordered semantic lookup index is not an emission-order source.

Run each manifest in `fixtures/phase0/link/manifest.json` with both compilers against the same captured inputs, fresh DMB/RSC outputs and the same DreamDaemon. Each world writes `phase0-link.json`, prints `PHASE0` JSON records and ends with `PHASE0 DONE`. Use a separate run directory per compiler/case; compare ordered arrays and complete records, not sets. Record compiler/runtime versions, binary hashes, input hashes and raw logs. Expected labels in the manifest are exact; order answers marked pending must be populated from paired receipts, never guessed. These source fixtures are standalone compiler probes, not game includes.

## Observable order inventory

| Surface | Required preservation | Existing baseline evidence | New receipt |
|---|---|---|---|
| Type enumeration / `typesof()` | Preserve runtime enumeration, lexical implicit parents, explicit `parent_type`, reopened types and builtin ordering. Do not globally alphabetize types. | Bootstrap `ensure_class` recursively creates lexical parents; native template fixtures preserve native builtin ordering. This is implementation evidence, not a general DreamMaker enumeration proof. | `observable.dme`: `types` pending |
| Datum `vars` | Preserve runtime field-name enumeration and inherited/overridden declaration behavior; order is separate from lookup sorting. | `FORMAT.md`: wire declaration pairs retain compiler order and need not be VarID-sorted; loader search ordering is separate. | `observable.dme`: atom `vars` pending |
| Procedure references and override chains | Preserve distinct declaration occurrences, nearest override and `..()` target; display names cannot replace source paths. | `native_proc_override_chain.rs` asserts native fixture IDs grandchild, child, base for `foo`, plus custom display-name dispatch. | `observable.dme`: override result/ref labels; existing fixture remains authoritative for its input |
| Verb enumeration and visibility | Preserve inherited verb list order, duplicates/redefinition policy and metadata; do not sort by display name as a linking shortcut. | Existing native proc/signature fixtures and bootstrap metadata encoder; no universal verb-list order rule established here. | `observable.dme`: `verbs` pending |
| Literal / associative lists | Preserve sequence duplicates, associative insertion/update/removal/reinsertion order; never canonicalize user data by key. | Existing lowering fixtures include associative iteration; runtime order still needs paired receipt. | `lists.dme` four labels pending |
| Global initialization | Preserve side-effect order and dependency semantics before `world.New`. | `native_compiler/initializer_order`, `initializer_categories`, `manifest_static_order` probes; bootstrap source-order occurrence scheduling. | `initialization.dme`: `startup` pending |
| Class defaults, static and instance initialization | Preserve dependency ordering, inherited defaults and creation-time side effects. Constant materialization and dynamic calls may have distinct phases. | `order_type_initializers` groups reopens in source order and resolves actual parent / `::` default dependencies; dynamic initializer emitter phases literal assignments before dynamic calls. These are baseline implementation rules to verify. | `initialization.dme` construction labels pending |
| Procedure-local statics | Preserve once-only initialization and sharing across inherited calls / distinct procedure declarations. | Existing `initializer_order` probe exercises repeated and inherited local-static calls. | `initialization.dme`: twice/child labels pending |
| Resource aliases / resource-to-text | Preserve complete named archive insertion order, first resource kind for equal content IDs, included scripts/skin/map phases, dead resource tokens and owner dependency scheduling. Content equality does not determine returned alias name. | `FORMAT.md`, `doc/audits/RESOURCE_ARCHIVE_ORDER_AUDIT.md`; 30 manifests / 60 ordered archive comparisons, 132 fresh legal cases. Finite probes do not establish full-game parity. | `resources.dme`: alias filenames pending; equal-payload equality expected |
| Map placement / startup traversal | Preserve placements and creation ordering where effects can observe them. Do not infer order from map memo storage. | Existing format/map fixtures; no new order receipt supplied. | `map_startup.dme`: creation and world iteration receipts pending |

### Resource phases already supported by recorded probes

The resource audit establishes separate explicit `/var`, `/proc`, `/verb` namespace phases anchored by first declarations, including resource-free declarations. Relative nested vars are separate occurrences. Field overrides and bare method overrides are separate phases. Reopens group lexical subtrees; an actual nonlexical parent delays an owner until a later traversal pass, not immediate scheduling when that parent is encountered. Root globals precede owner groups; map resources follow code; included scripts precede interfaces/code, and skin imports precede interfaces. Keep the existing resource archive probes as regression inputs; the simple new alias world does not replace them.

## Procedure and declaration metadata

All `set` metadata belongs to declaration meaning and its memo key, even when executable statements are unchanged. Preserve source proc path independently from visible name. Baseline procedure settings include `name`, `desc`, `category` (including null), `src` selection mode, `invisibility`, `waitfor`, `hidden`, `background`, `instant`, and `popup_menu`. Baseline flag mapping includes hidden=1, waitfor=4, popup-menu-disabled=0x40, background=0x100, instant=0x200. These flags must be compared in decoded output; a runtime verb enumeration alone cannot verify them. Preserve parameter order, type annotations, defaults and named-argument dispatch metadata; proc reference table entries; world/header settings; type variable flags and initial values; initializer references; client script/interface settings. Unknown `set` settings must retain the baseline diagnostic rather than silently disappear.

`observable.dm` uses an `/obj` hierarchy so runtime verb lists exist, and includes all listed boolean flags plus visible text, src and invisibility. Expected decoded metadata should be captured alongside runtime labels by the existing DMB exporter; it is not yet a generated reference receipt.

## Canonical orders where genuinely unobservable

Symbol lookup tables and cache segments may use a fixed lexical or numeric order. Private symbol hashes must not define user-visible dense IDs. For serialized strings, code/list objects and other internal tables, choose deterministic first use in the approved observable traversal only after probes establish that aliasing, `__PROC__`, resource text, enumeration and initialization cannot distinguish the alternative. Preserve ordered relocations by offset and validate overlaps before linking. Deduplication must preserve semantic identity, flags and distinguishable mutable list instances. The following is the proposed replacement policy for tables certified unobservable; it is not a claim about the frozen compiler or DreamMaker. Dense IDs are assigned by first use in a single deterministic linking traversal: fixed builtin seed order, approved declaration/owner occurrence order, procedure declaration order, instruction offset order, then approved initializer/map/resource phases. Within one instruction or record, operand visits follow the format schema field order; list elements follow their stored sequence. A repeated immutable semantic object reuses its first assigned ID only when its full typed identity and mutability class agree. Mutable list instances are distinct even if equal in content. Relocations visit increasing offset, then schema operand ordinal; overlap is rejected. No worker, cache or hash enumeration participates. Lookup-only indexes sort by canonical key bytes. An internal table must remain on the observable policy until its ID/alias/reflection effects have been ruled out by paired evidence; this policy cannot justify changing resource alias, procedure reflection or user list order.

## Baseline receipt locations

- `tools/dmb/FULL_SUITE_COMPARISON.md`: September 30 frozen comparison, BYOND 985 pass / 46 fail, Rust 997 pass / 34 fail, 1,089 records. This is not full parity.
- BYOND run `6475a3d057ca4f5eabab43addc3dae04`; Rust run `8a6054fad0144a82b6456d651415ba16`; tracked `results/full-suite-comparison-2026-09-30.csv`. Raw JSON/logs/frozen sources remain in gitignored `target/` comparison/runtime directories; availability must be checked by the baseline runner.
- Keep the recorded private compatibility edits, map substitutions, Verdigris and runtime configuration. The older September 28 `DM_TEST_REPORT.md` is a separate comparison and cannot replace this baseline.

## Exit gate

Fill every pending observable rule with paired fresh output receipts, including missing map/startup coverage. Freeze raw records and decoded metadata. Run worker-count/scheduler determinism separately from DreamMaker parity. A rule that is merely native implementation behavior remains explicitly labeled until the paired oracle proves it.

## Captured DreamMaker reference — 6 October 2026

Coordinator receipts: `D:/dmb-native-v2-phase0/contracts-reference-run2/results.json`. All four link cases compile and run with exit0; no timeout recorded. Exact reference arrays are tracked beside each source as `*.reference.json`; fixture manifest records original observations, compile/runtime log paths, and SHA256 for each captured manifest, common source, case source and resource payload. These are DreamMaker observations, not a completed native parity claim.

- `observable`: types enumerate `/obj/link_order`, `/obj/link_order/base`, `/obj/link_order/a_child`, `/obj/link_order/z_child`. This particular result puts the explicit parent before its children and the child names in a different order from their declarations; it does not establish a universal alphabetical type-table rule. Vars begin `z_value,a_value,reopened_value`, followed by the exact engine list in observable.reference.json. Verbs are `a_verb,z_verb`, despite z being declared first. Override result is `child|base`; proc and verb references preserve their source paths.
- `lists`: sequence `z,a,z,m`; associative keys `z,a,m`, values `1,4,3`; deleting/reinserting a yields `z,m,a`.
- `initialization`: startup is `global_z|static_z|local_static|global_a|`. The procedure-local static is initialized before world.New and global_a, not at first call. Constructing base adds `instance_z|base_New|`; calling local_static twice adds nothing. Child construction adds `instance_z|child_value|base_New|child_New|` and its inherited local_static adds nothing. Do not implement lazy local-static initialization from the source syntax alone.
- `resources`: all three equal-content resource references stringify as `alias_a.txt`; equality is1. This proves that source reference filenames are not necessarily the runtime alias text. Full archive insertion order remains the separate existing audit contract.

The inventory table's pending references now mean general rule certification pending. A targeted decoded procedure comparison is recorded below; broader flag comparison and map/startup traversal coverage remain outstanding. Preserve exact labels and arrays from these receipts rather than replacing them with a guessed general order.

## Paired preserved Build50 baseline

Coordinator run `D:/dmb-native-v2-phase0/contracts-paired-run1/results.json` used preserved `compiler-integration-fiftieth.exe`, native_template.bin, and DreamMaker516.1687 on the same captured fixture source. Each tracked `*.paired.json` contains compact complete observations, per-label differences, SHA256 for input closure/compiler/builtin/observation files, raw receipt paths and actual commands/outcomes. This establishes baseline behavior for these probes, not native-v2 replacement performance or full parity. No compiler fix is included in Phase0.

| Case | Observed result | Baseline classification |
|---|---|---|
| observable | Native types end z_child,a_child; reference ends a_child,z_child. Native verbs z_verb,a_verb; reference a_verb,z_verb. Vars, override result and reference paths agree. | Two observable-order divergences |
| initialization | Native startup static_z,global_z,global_a,local_static; reference global_z,static_z,local_static,global_a. All later checkpoints retain that difference; instance/New suffixes agree. | Initialization registration-order divergence; local static is eager in both |
| resources | Native all aliases stringify alias_z.txt; reference alias_a.txt. Resource equality agrees. | Observable resource alias identity divergence |
| lists | All four ordered arrays agree. | Match for this finite input only |
| observable decoded metadata | `/obj/link_order/base/z_verb` has reference `proc.source = Other { kind: 16, parameter: 127 }`, native `Default`, for the fixture `set src in world`. | Fourth divergence category: procedure source metadata |

Carry these exact differences into the preserved divergence list. Do not normalize array order away or treat resource equality as alias parity. The reference arrays remain the target orders for replacement fixtures; the native arrays are frozen baseline receipts to prevent invented progress claims. A universal rule still needs broader reopens/parent/namespace/metadata/map probes. Existing older archive fixtures do not override this newly observed alias mismatch.

The targeted release `dmb-inspect dmb-compare` receipt is
`D:/dmb-native-v2-phase0/contracts-paired-run1/link-observable/opcode-diff.log`.
It reports exactly one semantic discrepancy in the compared `/obj/link_order`
prefix: the `proc.source` values above. Its SHA256 and exact raw representations
are retained in `observable.paired.json` and the fixture manifest. This records
the fixture's world-source setting without assigning an unverified meaning to
the numeric kind/parameter or claiming broader metadata coverage.

## Additional source probes (receipts pending)

Three additional manifests are source-only probes until the coordinator captures fresh compilation, decoded metadata and paired runtime receipts. No expected order has been invented in their manifest entries.

- `map_startup.dme` places opposite object orders on four coordinates, records area/turf/object `New` calls before `world.New`, and records world iteration with coordinates. It separates placement order from runtime traversal.
- `metadata_modes.dme` covers both values of every listed boolean flag, null/non-null category, text/desc/invisibility/parameter annotation, and `src in world`, `usr`, `usr.loc`, and `view(1)`. Decode the complete procedure settings, not just verb visibility. These are representative legal source modes, not an exhaustive grammar claim.
- `reopens_parent.dme` combines a child declared before its explicit nonlexical parent, a reopened parent, override dispatch, and verb source names whose display-name ordering is reversed. Capture type/vars/verbs arrays exactly.

The existing four paired cases retain their recorded outcomes. Generalization beyond those finite inputs and these new pending probes remains uncertified.
