# Remaining requirements after E: read-only classification

Source: 2b059f9a2b; requirement_bool baseline **193 fingerprints across 131 files**. Counts are fingerprint rows, not constructor instances. No tracked file or build/test changed.

## Separate pending equipment-fit/rules macro inventory

**None of the 193 requirement_bool rows are REQ_* table rows**: every current row is a native req_bool callback. The pending table consumer migration is a separate inventory. Direct source scan (excluding generated, tests, benchmarks, macro definitions, quoted text and comment-only lines) finds **160 production lines containing 197 REQ_* constructor tokens**, across 45 files. Multiple nested constructors count as one line here; this is an audit count, not an analyzer baseline. Equipment-fit and rules tables stay untouched pending proposal review. The macro list also includes consent/stance/hold consumers (vore_consent.dm, combat_mode.dm, folders/backpack/internal/custom_items): these are a further consumer-protocol group, not automatically covered by the equipment-fit proposal; trace their actual consumers and propose parity before replacing them.

| File | Lines | Tokens |
|---|---:|---:|
| `code/datums/properties/constraints.dm` | 1 | 1 |
| `code/datums/properties/equip_slots.dm` | 27 | 48 |
| `code/datums/rules/declarations.dm` | 12 | 12 |
| `code/game/objects/items/weapons/storage/backpack.dm` | 2 | 2 |
| `code/game/objects/items/weapons/storage/internal.dm` | 1 | 2 |
| `code/game/objects/structures/crates_lockers/__closets.dm` | 1 | 2 |
| `code/modules/clothing/accessories/accessory.dm` | 1 | 1 |
| `code/modules/clothing/accessories/holster.dm` | 1 | 2 |
| `code/modules/clothing/clothing.dm` | 2 | 2 |
| `code/modules/clothing/ears/ears.dm` | 1 | 1 |
| `code/modules/clothing/glasses/glasses.dm` | 2 | 2 |
| `code/modules/clothing/gloves/arm_guards.dm` | 1 | 1 |
| `code/modules/clothing/gloves/miscellaneous.dm` | 1 | 1 |
| `code/modules/clothing/masks/breath.dm` | 1 | 1 |
| `code/modules/clothing/masks/gasmask.dm` | 2 | 2 |
| `code/modules/clothing/masks/tesh_synth_facemask.dm` | 1 | 1 |
| `code/modules/clothing/shoes/leg_guards.dm` | 1 | 1 |
| `code/modules/clothing/shoes/magboots.dm` | 2 | 2 |
| `code/modules/clothing/shoes/xeno/teshari.dm` | 1 | 1 |
| `code/modules/clothing/spacesuits/alien.dm` | 4 | 4 |
| `code/modules/clothing/spacesuits/rig/rig_pieces.dm` | 4 | 4 |
| `code/modules/clothing/spacesuits/rig/suits/alien.dm` | 7 | 7 |
| `code/modules/clothing/spacesuits/rig/suits/combat.dm` | 4 | 4 |
| `code/modules/clothing/spacesuits/rig/suits/station.dm` | 8 | 8 |
| `code/modules/clothing/spacesuits/spacesuits.dm` | 2 | 2 |
| `code/modules/clothing/spacesuits/void/ert.dm` | 2 | 2 |
| `code/modules/clothing/spacesuits/void/event.dm` | 2 | 2 |
| `code/modules/clothing/spacesuits/void/station.dm` | 2 | 2 |
| `code/modules/clothing/spacesuits/void/void.dm` | 4 | 4 |
| `code/modules/clothing/spacesuits/void/zaddat.dm` | 2 | 2 |
| `code/modules/clothing/suits/aliens/teshari.dm` | 7 | 7 |
| `code/modules/clothing/suits/aliens/vox.dm` | 1 | 1 |
| `code/modules/clothing/suits/armor.dm` | 3 | 3 |
| `code/modules/clothing/suits/miscellaneous.dm` | 3 | 3 |
| `code/modules/clothing/suits/utility.dm` | 2 | 2 |
| `code/modules/clothing/under/xenos/teshari.dm` | 1 | 1 |
| `code/modules/clothing/under/xenos/vox.dm` | 1 | 1 |
| `code/modules/mob/combat_mode.dm` | 4 | 4 |
| `code/modules/mob/living/carbon/human/npcs.dm` | 1 | 1 |
| `code/modules/mob/living/carbon/human/species/station/protean/protean_rig.dm` | 4 | 4 |
| `code/modules/paperwork/folders.dm` | 1 | 2 |
| `code/modules/vore/eating/vore_consent.dm` | 12 | 24 |
| `code/modules/vore/fluffstuff/custom_clothes.dm` | 14 | 14 |
| `code/modules/vore/fluffstuff/custom_items.dm` | 3 | 3 |
| `code/modules/weapons/MadokaSpear.dm` | 1 | 1 |

## Mob/admin/window residual cohort

**14 admin fingerprints in 6 files; 3 mob fingerprints in 2 files; 10 TGUI module fingerprints in 8 files.** These total 27 native rows; no equipment-fit table protocol dependency.

| File | Rows | Next action |
|---|---:|---|
| `code/modules/admin/admin_newscaster_panel.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/admin/edit_player_panel.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/admin/holder2.dm` | 7 | Admin rights/rank/token plus actual client-only branches need real holder/client fixtures; do not replace with AUTH_ADMIN bypass assertions |
| `code/modules/admin/magnetic_console_panel.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/admin/player_effects.dm` | 3 | nif_target_ok and ai_target_ok eligible with real organ/NIF/teleop boundaries; item_tf_ready positive proof requires real keyed player |
| `code/modules/admin/specops_shuttle_panel.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/mob/living/silicon/robot/component.dm` | 2 | Defer until resolver-owner AI fix lands; shared kit_goes_first inverse must be converted alongside kit_goes_last in paintkit.dm |
| `code/modules/mob/living/simple_mob/simple_mob.dm` | 1 | Ghost-join genuine client/preferences proof required; do not fabricate ckey or prefs eligibility |
| `code/modules/tgui/modules/_base.dm` | 1 | Cross-module UI lifecycle dependency; migrate original method and any ordinary callers together, with open/closed prompt lifecycle proof |
| `code/modules/tgui/modules/appearance_changer.dm` | 3 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/tgui/modules/crew_monitor.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/tgui/modules/late_choices.dm` | 1 | Late-join client/selected-job proof; callback migration is expressible, complete positive test needs real supported client fixture |
| `code/modules/tgui/modules/law_manager.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/tgui/modules/ntos-only/cardmod.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/tgui/modules/overmap.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |
| `code/modules/tgui/modules/rcon.dm` | 1 | Eligible null/reason callback conversion after old-code pins plus helper/subtype consumer trace |

## Ten semantic samples for next review

1. **Admin jobban** (`holder2.dm`): one fingerprint has five callbacks (rights, moderator policy, target present, rank ordering, ready). All remain separately ordered null/reason requirements; preserve first refusal. Tests need real holder ranks and jobban state restoration.
2. **Admin sendbacktolobby** (`holder2.dm`): observer-kind and real client clauses are distinct. Kind refusal can use a real human/ghost; positive client clause cannot be proven by forged ckey.
3. **Eventkit quick NIF** (`player_effects.dm`): unsuitable target means nonhuman or missing head; existing NIF on a headed human means nif_present. Merge both procs preserving that distinction and first-pass order.
4. **Eventkit give AI** (`player_effects.dm`): requires actual living target with neither client nor teleop. Negative nonliving gives ai_not_living; any player control gives ai_player. Real relation teleop transitions supply clientless negative coverage; real client case still needs genuine connection.
5. **Eventkit item transformation** (`player_effects.dm`): positive is living plus actual ckey. Native protocol exists, but old successful behavior needs genuine player state; do not fake ckey to remove this row.
6. **Item kit ordering** (`component.dm`, definitions paintkit.dm): kit_goes_first is logical inverse of kit_goes_last; root void helmet/suit, hooded suit and rig belong to last group. A naive conversion that keeps ! on null/reason swaps meaning. This shares file with resolver owner pending Equip change; defer.
7. **Ghost join** (`simple_mob.dm`, denecrotizer.dm): banned role, occupied ckey and capture preference refusal ordering is already centralized in ghost_join_refusal. Replace paired wrapper only after real client/preference proof; keep the helper’s READS_FROM() declaration.
8. **Base TGUI ui_usable** (`_base.dm`): no window is allowed before an answer, but refused after an answer; an existing window must be STATUS_INTERACTIVE. This is not a simple owner/client check. Keep open/closed distinction and silent refusal.
9. **Crew monitor range** (`crew_monitor.dm`): actual gate requires an actor turf with its z in using_map.player_levels; preserve crew_monitor/out_of_range and station-level/off-station transition instead of replacing with a generic adjacent clause.
10. **Law manager malf** (`law_manager.dm`): malf target authorization belongs to the real owner/mob context. Its when clauses/ordinary calls may remain Boolean while only the actual req callback becomes null/reason; trace before bulk token changes.

## Full native requirement_bool residual file inventory

| File | Rows |
|---|---:|
| `code/datums/behaviours/burning.dm` | 1 |
| `code/defines/obj/weapon.dm` | 1 |
| `code/game/gamemodes/endgame/supermatter_cascade/blob.dm` | 1 |
| `code/game/gamemodes/technomancer/catalog.dm` | 1 |
| `code/game/machinery/computer/security.dm` | 1 |
| `code/game/machinery/computer/skills.dm` | 1 |
| `code/game/machinery/machinery.dm` | 3 |
| `code/game/machinery/syndicatebeacon.dm` | 2 |
| `code/game/mecha/mecha_control_console.dm` | 1 |
| `code/game/objects/effects/anomalies/_anomalies.dm` | 1 |
| `code/game/objects/effects/mines.dm` | 1 |
| `code/game/objects/items/bodybag.dm` | 5 |
| `code/game/objects/items/devices/binoculars.dm` | 1 |
| `code/game/objects/items/devices/e_beacon.dm` | 1 |
| `code/game/objects/items/devices/flashlight.dm` | 1 |
| `code/game/objects/items/devices/modkit.dm` | 1 |
| `code/game/objects/items/devices/paicard.dm` | 1 |
| `code/game/objects/items/devices/personal_shield_generator.dm` | 2 |
| `code/game/objects/items/devices/radio/headset.dm` | 1 |
| `code/game/objects/items/devices/scanners/gas.dm` | 1 |
| `code/game/objects/items/devices/scanners/health.dm` | 1 |
| `code/game/objects/items/devices/scanners/mass_spectrometer.dm` | 1 |
| `code/game/objects/items/devices/translator.dm` | 1 |
| `code/game/objects/items/devices/tvcamera.dm` | 1 |
| `code/game/objects/items/devices/whistle.dm` | 2 |
| `code/game/objects/items/latexballoon.dm` | 1 |
| `code/game/objects/items/petrifier.dm` | 1 |
| `code/game/objects/items/robobag.dm` | 1 |
| `code/game/objects/items/shooting_range.dm` | 1 |
| `code/game/objects/items/stacks/marker_beacons.dm` | 3 |
| `code/game/objects/items/stacks/stack.dm` | 1 |
| `code/game/objects/items/toys/toys.dm` | 1 |
| `code/game/objects/items/uav.dm` | 1 |
| `code/game/objects/items/weapons/RMS.dm` | 1 |
| `code/game/objects/items/weapons/autopsy.dm` | 1 |
| `code/game/objects/items/weapons/candle.dm` | 1 |
| `code/game/objects/items/weapons/cigs_lighters.dm` | 1 |
| `code/game/objects/items/weapons/cosmetics.dm` | 1 |
| `code/game/objects/items/weapons/dna_injector.dm` | 1 |
| `code/game/objects/items/weapons/implants/implantpad.dm` | 2 |
| `code/game/objects/items/weapons/material/ashtray.dm` | 1 |
| `code/game/objects/items/weapons/material/gravemarker.dm` | 1 |
| `code/game/objects/items/weapons/picnic_blankets.dm` | 2 |
| `code/game/objects/items/weapons/storage/bible.dm` | 2 |
| `code/game/objects/items/weapons/traps.dm` | 2 |
| `code/game/objects/mail.dm` | 3 |
| `code/game/objects/micro_structures.dm` | 1 |
| `code/game/objects/structures/artstuff.dm` | 1 |
| `code/game/objects/structures/barricades.dm` | 1 |
| `code/game/objects/structures/bedsheet_bin.dm` | 1 |
| `code/game/objects/structures/desert_planet_structures.dm` | 1 |
| `code/game/objects/structures/door_assembly.dm` | 1 |
| `code/game/objects/structures/fitness.dm` | 1 |
| `code/game/objects/structures/flora/trees.dm` | 2 |
| `code/game/objects/structures/ghost_pods/ghost_pods.dm` | 2 |
| `code/game/objects/structures/ghost_pods/unified_ghost_hole.dm` | 1 |
| `code/game/objects/structures/grille.dm` | 1 |
| `code/game/objects/structures/janicart.dm` | 1 |
| `code/game/objects/structures/low_wall.dm` | 1 |
| `code/game/objects/structures/mirror.dm` | 1 |
| `code/game/objects/structures/railing.dm` | 2 |
| `code/game/objects/structures/reflectors.dm` | 1 |
| `code/game/objects/structures/safe.dm` | 1 |
| `code/game/objects/structures/simple_doors.dm` | 1 |
| `code/game/objects/structures/stool_bed_chair_nest/bed.dm` | 5 |
| `code/game/objects/structures/stool_bed_chair_nest/chairs.dm` | 1 |
| `code/game/objects/structures/stool_bed_chair_nest/stools.dm` | 2 |
| `code/game/objects/structures/trash_pile.dm` | 1 |
| `code/game/objects/structures/under_wardrobe.dm` | 1 |
| `code/game/objects/structures/watercloset.dm` | 1 |
| `code/game/objects/structures/windoor_assembly.dm` | 1 |
| `code/game/objects/structures/window.dm` | 1 |
| `code/game/turfs/simulated/nanogoop.dm` | 2 |
| `code/modules/admin/admin_newscaster_panel.dm` | 1 |
| `code/modules/admin/edit_player_panel.dm` | 1 |
| `code/modules/admin/holder2.dm` | 7 |
| `code/modules/admin/magnetic_console_panel.dm` | 1 |
| `code/modules/admin/player_effects.dm` | 3 |
| `code/modules/admin/specops_shuttle_panel.dm` | 1 |
| `code/modules/body/organs/organ.dm` | 1 |
| `code/modules/body/organs/organ_external.dm` | 7 |
| `code/modules/casino/casino.dm` | 3 |
| `code/modules/casino/slots.dm` | 2 |
| `code/modules/catalogue/cataloguer.dm` | 1 |
| `code/modules/client/stored_item.dm` | 1 |
| `code/modules/detectivework/tools/sample_kits.dm` | 2 |
| `code/modules/economy/sales_lots.dm` | 1 |
| `code/modules/entrepreneur/entrepreneur_items.dm` | 3 |
| `code/modules/fireworks/firework_launcher.dm` | 3 |
| `code/modules/holodeck/HolodeckObjects.dm` | 1 |
| `code/modules/holomap/mapper.dm` | 1 |
| `code/modules/library/lib_items.dm` | 1 |
| `code/modules/maintenance_panels/maintpanel_stack.dm` | 1 |
| `code/modules/materials/sheets/organic/wood.dm` | 1 |
| `code/modules/medical/instruments/instruments.dm` | 3 |
| `code/modules/medical/instruments/resuscitation.dm` | 3 |
| `code/modules/mob/living/silicon/robot/component.dm` | 2 |
| `code/modules/mob/living/simple_mob/simple_mob.dm` | 1 |
| `code/modules/nifsoft/nif_softshop.dm` | 3 |
| `code/modules/nifsoft/nif_tgui.dm` | 3 |
| `code/modules/nifsoft/nifsoft.dm` | 1 |
| `code/modules/paperwork/filingcabinet.dm` | 1 |
| `code/modules/paperwork/paperbin.dm` | 1 |
| `code/modules/pda/pda.dm` | 1 |
| `code/modules/projectiles/ammunition/smartmag.dm` | 1 |
| `code/modules/projectiles/guns/projectile/sniper/collapsible_sniper.dm` | 1 |
| `code/modules/recycling/conveyor2.dm` | 1 |
| `code/modules/security levels/keycard authentication.dm` | 1 |
| `code/modules/shieldgen/emergency_shield.dm` | 1 |
| `code/modules/shieldgen/sheldwallgen.dm` | 1 |
| `code/modules/shieldgen/shield_gen.dm` | 1 |
| `code/modules/shieldgen/shield_generator.dm` | 1 |
| `code/modules/surgery/surgery_ops.dm` | 1 |
| `code/modules/telesci/bscyrstal.dm` | 1 |
| `code/modules/telesci/quantum_pad.dm` | 1 |
| `code/modules/telesci/telesci_computer.dm` | 1 |
| `code/modules/tgui/modules/_base.dm` | 1 |
| `code/modules/tgui/modules/appearance_changer.dm` | 3 |
| `code/modules/tgui/modules/crew_monitor.dm` | 1 |
| `code/modules/tgui/modules/late_choices.dm` | 1 |
| `code/modules/tgui/modules/law_manager.dm` | 1 |
| `code/modules/tgui/modules/ntos-only/cardmod.dm` | 1 |
| `code/modules/tgui/modules/overmap.dm` | 1 |
| `code/modules/tgui/modules/rcon.dm` | 1 |
| `code/modules/vehicles/Securitrain.dm` | 1 |
| `code/modules/vehicles/cargo_train.dm` | 1 |
| `code/modules/vehicles/rover.dm` | 1 |
| `code/modules/vehicles/train.dm` | 1 |
| `code/modules/vore/smoleworld/smoleworld.dm` | 2 |
| `code/modules/xenoarcheaology/tools/tools.dm` | 2 |
| `code/modules/xenobio/items/weapons.dm` | 2 |

## Cohort accounting correction

E mobs draft estimate 31 was one high: the string-based manifest predictor mistakenly counted unchanged simple_mob ghost_join alongside nutrition_heal. Actual mobs/clothing reduction is 30; ghost_join is intentionally still present. No missing conversion hunk.

Machinery remote robot callbacks, TOPIC shared shim and key/resolver families need coordination with their owner; this audit does not authorize those edits. Remaining generic item/structure callbacks are native and generally convertible once old-code boundary and inheritance traces are recorded.
