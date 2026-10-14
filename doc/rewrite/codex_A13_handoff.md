# A13 initializer sweep

Branch `codex/A13`, WT `E:/projects/dq-wt/codex-A13`, base `1fff26dc1f`.

Exact scope derived before edits by excluding all A1-A12 directory prefixes: 491 baseline rows (477 init_lines, 14 world_reads), 106 files. It includes the remaining map-file rows. `scoped-baseline.txt` records that inventory; `initial-bodies.txt` records the read-first audit.

53 production files changed, one eight-test file. Source identity estimate init_lines 477 -> 289 (188 removed), world_reads 14 -> 8 (6 removed). Root must certify. No baselines edited.

## Migrated jobs and proofs

Native setup covers HUD ability/palette/PIP/mapper frames, reactive screwdriver, capacitor rating, area motion-camera lookup, shuttle window joining, cursed form, compass markers, holodeck/mapping displays, instrument scratch-list release, bookcase/map notice collection, looking-glass area/console/viewer setup, recycler/partial vendor display, nail polish description, media/NTNet registration, z-pipe direction/stair integrity, refinery network/parts/reagent naming, resleeving database/modules/partless-machine settings, rogue-zone shuttle lookup, sample sale, emergency shield atmos+damage, diffuser flooring, charged/upgraded shield settings, one-use spell name, telepad parts, train/vehicle startup, shuttle displays, outpost pad lookup, meteorite rotation and platform ID access.

Full-tree block audit: new blocks unique, canonical existing blocks reused. Full-tree constructor audit found two remaining descendants of moved parents: PIP/AI only links the aiEye supplied by its own declared starts, and does not read backgrounds/map generation; jukebox only validates tracks and breaks if absent, not the media source link. Both preserve constructor-visible data. Other fully moved parent types have no remaining descendant Initialize consumers.

Train neighbor latching and all engine shutdown descendants moved together. Each type has a distinct shutdown hook, preserving repeated inherited turn_off calls rather than collapsing them through setup's proc-key deduplication. Emergency shield parent atmos refresh remains before malfai damage. Charged/upgraded shield children moved, but the parent mode-construction phase remains before them.

Capacitor capacity scaling finishes before constructor returns, so a gun creating the part can read the same scaled max_charge. Instrument song starts consume the allowed IDs before their scratch-list-release setup. Mapper owned children precede frame/cache setup. Research/renderer-style moved appearance writes use existing setters where required: mapper frame state; recycler hatch/monitor icon+state; vendor monitor icon+state; outpost multitool state; meteorite icon. Platform access additions use include_access to retain union semantics. All pre-existing setter calls, TRACKED lines and ownership/reference declarations preserved.

No seeded RNG conversions in this lane. Maint-vendor catalog creation and shuffle remain together; only independent display setup moved after that constructor work. Telecube and blob correlated randomness remain intact.

## Remaining groups: exhaustive by scoped file

All exact remaining fingerprints/counts and raw bodies are in `remaining-text-audit.txt`.

- `_helpers/radiation.dm`: simulated turf radiation notification shares prototype/table-init phase; its canonical block is in another cohort. Do not add a duplicate or delay it across child constructors.
- `_onclick/hud/screen_objects.dm`: mapper child binds constructor location as parent; durable per-instance relation input remains.
- `controllers/globals.dm`: bootstrap Initialize drives InitGlobal procs while GLOB itself is being constructed. This manually invoked framework API cannot become automatic datum setup; diagnostic logging retained.
- `datums/gear/loadout_shoes.dm`: none-shoes immediately drop/spill their constructor owner's inventory, move away and expire; delaying would affect subsequent loadout construction and equip order.
- `datums/repositories/decls.dm`: manually invoked decl Initialize contract (SHOULD_CALL_PARENT/SHOULD_NOT_SLEEP), not atom lifecycle.
- `datums/variants/crayon_variants.dm`: variant application precedes parent reads. `paperwork/pen.dm`'s later colour prefix must coordinate with the canonical crayon block in A2's items file; no duplicate added.
- `game/area/areas.dm`: ceiling application before parent, luminosity after parent; fundamental area/prototype setup used by area descendants, not an isolated leaf job.
- `game/atom/atoms_initializing_EXPENSIVE.dm`: the framework root sets initialized flags, integrity and runs lifecycle_decls_init/caps_init. Moving it to a hook would remove the phase supplying every descendant.
- `game/atoms_movable.dm`: movable_instance_setup is shared with table_initialize and consumed by descendants immediately after parent; retain framework phase.
- `game/dna/dna_modifier.dm`: nested body-record/DNA starting buffer factories need argument-aware starts and protected ownership declarations.
- `modules/admin/callproc/callproc.dm`: singleton constructor validity/QDEL plus GLOB registration must remain one protocol; not converted to post-validation work.
- `artifice/telecube.dm`: correlated per-instance colour RNG and optional paired child mirror/pair protocol; starts requires protected ownership declarations, independent rolls would change pairing/order. Existing setters unchanged.
- `assembly/holder.dm`: starting igniter/timer, secured state, mutual holder links and owner verb grant form an attachment-construction protocol; protected starts declarations need coordinated conversion.
- `asset_cache/transports/asset_transport.dm`: Initialize(assets) is explicitly called to replace preloads and schedule client transfers; it is not constructor lifecycle. Leave this API intact.
- `awaymissions/redgate.dm`: start_pos is the actual constructor location snapshot used to reset flags/hyperballs, genuinely per-instance.
- `blob2/blobs/base_blob.dm`: pre-parent faction/tile consumption/look update consumed by child core. `blobs/core.dm`: placed_at_make and overmind validity select make_overmind plus correlated deferred-creator RNG; preserve constructor argument/order. `overmind/overmind.dm`: name RNG + real_name + language bootstrap before parent and complementary/core colour after; coordinated mob constructor protocol, not independent rolls.
- `combat_ai/integration/mob_living.dm`: base AI brain creation is consumed by living descendants' Initialize bodies; delayed setup would reverse that dependency. No base-state declarations added.
- `emotes/emote_define.dm`: manual declaration Initialize registers emote keys after repository setup; not automatic datum constructor.
- `exploration/lootsafe.dm`: make_code and generate_loot are correlated random/starting-content factory calls; need native roll/loot policy and protected ownership declarations, not renamed helpers.
- `fireworks/firework_launcher.dm`: EXPIRY_STAMP captures actual constructor clock time for anti-reconstruction cooldown; per-instance initial state remains.
- `games/wizoff.dm`: owned playing cards need starts with text/name/icon arguments; protected cards ownership declaration prevents correct conversion here.
- `identification/item_procs.dm`: /obj/item creates identity before parent initializes capabilities; needed by descendants, protected starting ownership policy.
- `instruments/instrument_data/_instrument_data.dm`: manual sample Initialize is invoked by instrument data service when it is ready; not automatic New/setup.
- `lore_codex/codex.dm`: pre-parent shared-cache tree link supplies parent capability readers; native memo/ownership declaration conversion must precede delaying it.
- `maint_recycler/code/maint_vendor.dm`: catalog factory and RNG shuffle stay ordered in constructor; display moved. `code/util.dm`: pre-parent beacon registry update supplies later map placement; preserve ordering until a registry declaration replaces it. `remote_scene_tools.dm`: starting argument-bearing linked tool pair remains; size calibration moved.
- `maps/merge_conflicts.dm`: deliberate constructor CRASH/diagnostic sentinel; moving to safely-called setup could alter error handling/boot failure semantics.
- `modular_computers/computers/modular_computer/core.dm`: hardware/programs installed before parent; readers need those instances. `hardware/_hardware.dm`: binds holder before drive file checks. `hardware/hard_drive.dm` + `portable_hard_drive.dm`: parent installs programs then portable clears/recalculates; proper starts/ownership policy migration required. Delaying only parent would refill the supposed empty crystal after child cleared it.
- `multiz/turf.dm`: HasBelow assertion validates mapped turf constructor, not a post-init job.
- `nifsoft/nif.dm`: constructor load_data_at_make/wear_at_make, client-body quick_implant validity/QDEL and cached icon; transient args cannot be delayed past params cleanup. `software/13_soulcatcher.dm`: actual client brain ownership/eye transfer, typed validity/QDEL and parent-human relocation form a per-instance client constructor protocol.
- `paperwork/filingcabinet.dm`: pre-parent collection can affect parent storage/capability initialization. `folders.dm`: initial memo factory needs protected starts and argument-bearing text/name policy. `paper.dm`: mapload flag and map-edited HTML cleanup run before paper-subtype customization; moving it post-chain would encode/overwrite subtype HTML. `pen.dm`: see canonical-block crayon coordination above.
- `persistence/datum/persistence_datum.dm` + `paintings.dm`: explicitly invoked file-load/age/apply-token APIs, not automatic datum setup. `graffiti.dm`: real mapload argument decides persistence registration before parent; preserve map policy.
- `planet/sun.dm`: created directional overlap images must become declared owned starting presentation pieces, requiring protected reference declarations. `planet/thor.dm` + `virgo4.dm`: two definitions of the same SMES subtype initializer, with canonical power declarations in A6; avoid duplicate blocks and map compile-order changes.
- `refinery/core/industrial_reagent_mixer.dm`: pre-parent angle setter is preserved; default parts moved.
- `resleeving/implant.dm`: argument-bearing owned backup implant factory needs protected starts; `sleevecard.dm`: per-instance owner PDA naming and language capture during inherited pai constructor; preserve parent/child state snapshot rather than delay without proof.
- `rogueminer/wrappers.dm`: teleport coordinates snapshot each map constructor's x/y/z/world dimensions, genuine map state.
- `shieldgen/shield_gen.dm`: pre-parent facing-neighbor capacitor claiming; parent setup/capability consumers must not see an unlinked generator. `shield_generator.dm`: owned shield-mode factory and mode policy before charged/upgraded descendants require protected starts; child settings migrated.
- `spells/spells.dm`: real owner validity/QDEL constructor guard. `targeted/ethereal_jaunt.dm`: last_valid_turf captures the starting constructor location for later recovery.
- `tables/tables.dm`: material layers, duplicate-table breakup/reentrant qdel and map-preview reset are one constructor validity protocol. Correct keeps_if/construction/ownership conversion must preserve breakup consequences, not just omit invalid setup.
- `maps/common/common_things.dm`: SC-away spawner missing-table diagnostic/QDEL validity remains (outpost lookup moved). `maps/submaps/engine_submaps/engine.dm`: duplicate engine-loader warning, delete_me and singleton mapping registration are map resolver validity/selection, not a delayed job.

Client/preferences_save_service rows were already absent in source before this sweep; root baseline update should independently remove those stale fingerprints. No edits to already-retired APIs.

## Verification delegated to root

No build, test, cargo, generation, baseline/manifest edits, commits, merges or pushes run. git diff --check passes. Add `#include "code\modules\unit_tests\dq_a13_initialization_tests.dm"` in root's manifest.

Run `/datum/unit_test/dq_a13_initialization` (eight leaves: capacitor_rating, compass_markers, mapper_cache, instrument_ids, vehicle_shutdown, shield_damage, recycler_display, meteorite_rotation), plus task-required `dq_look_pin`.

Root analyzer certification: init baseline4115 ->3933 (182 fingerprints removed), decl47unchanged; generated trackedcheck clean after original_zLevel and compass label additions use existing setters. The occurrence-based source estimate is not the analyzer fingerprint count. Runtime verification pending.

## Exact retained site identities

[Committed residual inventory](codex_A13_residual_sites.txt) lists every retained source identity from this lane’s post-edit audit, including repeated normalized rows. The per-file reasons above classify those identities; this is a source audit snapshot, not a fresh analyzer verdict after rebasing. Master’s subsequently removed declarations and rewritten setters must remain authoritative, and the root verification will establish the final baseline counts.

### Commented preference-save initializer

`code/modules/client/preferences_save_service.dm` retains an old initializer inside an existing `/* ... */` comment block. These eight input-baseline fingerprints are not live constructor work and are absent from the post-edit live-source inventory; no lifecycle conversion or callback blocker is claimed for them:

```text
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::while
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::prefs
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::expr
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::prefs.setup
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::while
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::new_player
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::expr
init_lines	code/modules/client/preferences_save_service.dm	@/datum/system/character_setup::Initialize::new_player.deferred_login
```
