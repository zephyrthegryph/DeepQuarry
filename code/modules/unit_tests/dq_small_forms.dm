// The last small forms (lane small-forms): look parts for a transform and a maptext, the hop read of another atom's look (look.watch_look()),
// the slot release a gibber's remains use, and the engine world watches that replaced the om_world_* procs.

// ---- look_part_key(): transform and maptext ----

/// An image's key names its transform and its maptext (a compass marker turned to a new bearing is another look), and an image that sets
/// neither keeps the key it always had.
/datum/unit_test/dq_small_forms_part_key_names_transform_and_maptext

/datum/unit_test/dq_small_forms_part_key_names_transform_and_maptext/Run()
	var/image/plain = look_overlay_image('icons/obj/stock_parts.dmi', "fix")
	var/matrix/turned = matrix()
	turned.Turn(45)
	var/image/rotated = look_overlay_image('icons/obj/stock_parts.dmi', "fix", transform = turned)
	TEST_ASSERT(look_part_key(plain) != look_part_key(rotated), "a transform differs in the key")
	var/matrix/other_turn = matrix()
	other_turn.Turn(90)
	var/image/rotated_more = look_overlay_image('icons/obj/stock_parts.dmi', "fix", transform = other_turn)
	TEST_ASSERT(look_part_key(rotated) != look_part_key(rotated_more), "another transform is another key")
	var/image/labelled = look_overlay_image('icons/obj/stock_parts.dmi', "fix")
	labelled.maptext = "N"
	TEST_ASSERT(look_part_key(plain) != look_part_key(labelled), "a maptext differs in the key")
	var/image/relabelled = look_overlay_image('icons/obj/stock_parts.dmi', "fix")
	relabelled.maptext = "S"
	TEST_ASSERT(look_part_key(labelled) != look_part_key(relabelled), "another maptext is another key")
	var/image/twin = look_overlay_image('icons/obj/stock_parts.dmi', "fix")
	TEST_ASSERT_EQUAL(look_part_key(plain), look_part_key(twin), "an image with neither keeps the key it had")
	TEST_ASSERT(!findtext(look_part_key(plain), ":t") && !findtext(look_part_key(plain), ":m"), "and its key carries no transform or maptext part: [look_part_key(plain)]")

// ---- the compass holder redraws its markers with no update_icon call ----

/// A waypoint's bearing is the marker's transform: moving the holder turns the marker, the holder's look key changes and the new look is applied.
/datum/unit_test/dq_small_forms_compass_markers_follow_the_bearing

/datum/unit_test/dq_small_forms_compass_markers_follow_the_bearing/Run()
	var/turf/T = test_floor()
	var/obj/compass_holder/C = allocate(/obj/compass_holder, T)
	refresh_flush()
	C.set_waypoint("north", "N", T.x, T.y + 10, T.z, "#ffffff")
	refresh_flush()
	var/before = C.rx?.look_key
	TEST_ASSERT_NOTNULL(before, "the holder draws its markers")
	TEST_ASSERT_EQUAL(length(C.compass_waypoint_markers), 1, "the shown waypoint has a marker")
	var/turf/east = get_step(T, EAST)
	TEST_ASSERT_NOTNULL(east, "a floor beside the test floor")
	C.forceMove(east)
	C.rebuild_overlay_lists()
	refresh_flush()
	TEST_ASSERT(C.rx?.look_key != before, "the waypoint turned with the holder, and the look followed with no update_icon call")
	var/after_move = C.rx?.look_key
	C.hide_waypoint("north")
	C.rebuild_overlay_lists()
	refresh_flush()
	TEST_ASSERT(C.rx?.look_key != after_move, "a hidden waypoint leaves the look")
	TEST_ASSERT_EQUAL(length(C.compass_waypoint_markers), 0, "and the marker list")

/obj/compass_holder/dq_small_heading
	show_heading = TRUE

/// The heading marker is a fresh image each time, so a new facing is a tracked change that redraws.
/datum/unit_test/dq_small_forms_compass_heading_marker_redraws

/datum/unit_test/dq_small_forms_compass_heading_marker_redraws/Run()
	var/turf/T = test_floor()
	var/obj/compass_holder/dq_small_heading/C = allocate(/obj/compass_holder/dq_small_heading, T)
	refresh_flush()
	var/image/first = C.compass_heading_marker
	TEST_ASSERT_NOTNULL(first, "a holder that shows its heading has a marker")
	TEST_ASSERT_NOTNULL(C.rx?.look_key, "the first look is applied")
	C.recalculate_heading()
	TEST_ASSERT(C.compass_heading_marker != first, "the marker is a new image after a recalculation")

// ---- look.watch_look(): the hop read of another atom's look ----

/obj/dq_small_look_subject
	name = "look subject"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/shade = 0
	var/noise = 0

TRACKED(/obj/dq_small_look_subject, shade)
TRACKED(/obj/dq_small_look_subject, noise)

/obj/dq_small_look_subject/draw(datum/look/look)
	..()
	look.overlay("shade-[shade]")

/obj/dq_small_look_composer
	name = "look composer"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/obj/dq_small_look_subject/subject
	var/draws = 0

/obj/dq_small_look_composer/draw(datum/look/look)
	..()
	draws++
	look.watch_look(subject)
	look.overlay("composed")

/// The composer redraws when the subject's look changes, and not when the subject writes a var its look does not show.
/datum/unit_test/dq_small_forms_watch_look_hears_the_look_only

/datum/unit_test/dq_small_forms_watch_look_hears_the_look_only/Run()
	var/turf/T = test_floor()
	var/obj/dq_small_look_subject/S = allocate(/obj/dq_small_look_subject, T)
	var/obj/dq_small_look_composer/C = allocate(/obj/dq_small_look_composer, T)
	refresh_flush()
	C.subject = S
	changed(C)
	refresh_flush()
	var/datum/cap_engine_state/theirs = cap_engine_state_of(S)
	TEST_ASSERT(theirs?.look_watchers?[OWN_KEY(C)], "the subject knows who composes its look")
	TEST_ASSERT(!length(S.rel_watchers), "and the composer is not a watcher of its every change")
	var/key = C.rx?.look_key
	var/drawn = C.draws
	S.set_noise(5)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.draws, drawn, "a var the subject's look does not show leaves the composer alone")
	S.set_shade(2)
	refresh_flush()
	TEST_ASSERT(C.draws > drawn, "the subject's new look redraws the composer")
	TEST_ASSERT(C.rx?.look_key != key, "and the composer's key moved with the version of the look it composes")
	TEST_ASSERT(cap_engine_state_of(S)?.look_serial >= 1, "the subject counted its published look")
	C.subject = null
	changed(C)
	refresh_flush()
	TEST_ASSERT(!length(cap_engine_state_of(S)?.look_watchers), "a draw that stops composing it stops hearing it")

/obj/item/remote_scene_tool/voodoo_doll/dq_small_counting
	var/draws = 0

/obj/item/remote_scene_tool/voodoo_doll/dq_small_counting/draw(datum/look/look)
	..()
	draws++

/// The voodoo doll shows its necklace's wearer from the wearer's look: the necklace being worn names the doll after them, the wearer's changed
/// layers redraw the doll, and a var of the wearer that is not part of its look does not.
/datum/unit_test/dq_small_forms_voodoo_doll_composes_the_wearer

/datum/unit_test/dq_small_forms_voodoo_doll_composes_the_wearer/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/remote_scene_tool/voodoo_doll/dq_small_counting/doll = allocate(/obj/item/remote_scene_tool/voodoo_doll/dq_small_counting, T)
	var/obj/item/remote_scene_tool/voodoo_necklace/neck = allocate(/obj/item/remote_scene_tool/voodoo_necklace, T)
	doll.link_to(neck)
	neck.link_to(doll)
	refresh_flush()
	TEST_ASSERT(!doll.partner_live, "a partner nobody wears is not live")
	H.equip_to_slot_if_possible(neck, SLOT_ID_MASK)
	neck.last_loc = null
	neck.delayed_loc_check()
	H.put_in_hands(doll)
	doll.last_loc = null
	doll.delayed_loc_check()
	refresh_flush()
	TEST_ASSERT_EQUAL(doll.partner_wearer, H, "the doll knows who wears its necklace")
	TEST_ASSERT_EQUAL(doll.name, "Voodoo doll of [H.name]", "and is named after them")
	TEST_ASSERT(cap_engine_state_of(H)?.look_watchers?[OWN_KEY(doll)], "a doll on a human composes the human's look")
	var/drawn = doll.draws
	H.set_nutrition(H.nutrition + 10)
	refresh_flush()
	TEST_ASSERT_EQUAL(doll.draws, drawn, "a var of the wearer that is not part of its look leaves the doll alone")
	H.overlays_standing[SKIN_LAYER] = image('icons/obj/stock_parts.dmi', "fix")
	H.apply_layer(SKIN_LAYER)
	refresh_flush()
	TEST_ASSERT(doll.draws > drawn, "a changed layer of the wearer redraws the doll")
	doll.set_no_fun_mode(TRUE)
	refresh_flush()
	TEST_ASSERT(!length(cap_engine_state_of(H)?.look_watchers), "with the special rendering off the doll no longer composes the wearer")

// ---- the slot release ----

/// A thing that stays inside a machine but leaves the occupant slot is filed under the default slot, and the occupant slot empties.
/datum/unit_test/dq_small_forms_slot_release_keeps_the_remains_inside

/datum/unit_test/dq_small_forms_slot_release_keeps_the_remains_inside/Run()
	var/turf/T = test_floor()
	var/obj/machinery/gibber/G = allocate(/obj/machinery/gibber, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(G, OCCUPANT_SLOT_GIBBER, H, force = TRUE), "the occupant goes in")
	TEST_ASSERT_EQUAL(G.slot_item(OCCUPANT_SLOT_GIBBER), H, "it is the occupant")
	TEST_ASSERT(G.slot_release(H), "the release is done")
	TEST_ASSERT_NULL(G.slot_item(OCCUPANT_SLOT_GIBBER), "nobody is the occupant any more")
	TEST_ASSERT_EQUAL(H.loc, G, "and it did not move")
	var/datum/ledger/L = dq_ledger_peek(G)
	TEST_ASSERT_EQUAL(L.entries[H][LEDGER_E_SLOT], CONTAINER_SLOT_INTERNALS, "it is filed under the internals slot")
	TEST_ASSERT(!G.slot_release(H), "releasing it again is a no-op")
	G.slot_remove(H, T)

// ---- the world watches of the engine ----

/// The world-watch helpers live in the engine under their own names: the tick a time rounds up to, and the diagnostics list the profilers read.
/datum/unit_test/dq_small_forms_world_diagnostics_are_engine_forms

/datum/unit_test/dq_small_forms_world_diagnostics_are_engine_forms/Run()
	TEST_ASSERT_EQUAL(world_tick_of(world.time), CEILING(world.time / world.tick_lag, 1), "world_tick_of rounds up to the wheel tick")
	var/list/diagnostics = world_diagnostics()
	TEST_ASSERT(islist(diagnostics), "the diagnostics are one list")
	TEST_ASSERT(!isnull(diagnostics["wakes_by_type"]), "with the wakes by owner type")
	TEST_ASSERT(!isnull(diagnostics["rust"]), "and Rust's own counters")

// ---- relations declared in the CAPABILITIES block ----

/obj/machinery/power/quantumpad/dq_small_pad_a
	map_pad_id = "dq_small_pad_a"
	map_pad_link_id = "dq_small_pad_b"

/obj/machinery/power/quantumpad/dq_small_pad_b
	map_pad_id = "dq_small_pad_b"
	map_pad_link_id = "dq_small_pad_a"

/// A keyed relation whose two ends keep the id in differently named vars (`by =` the holder's, `target_key =` the target's): a pad finds the pad
/// whose map_pad_id is its map_pad_link_id, whichever of the two is made first.
/datum/unit_test/dq_small_forms_keyed_pads_find_each_other

/datum/unit_test/dq_small_forms_keyed_pads_find_each_other/Run()
	var/turf/T = test_floor()
	var/obj/machinery/power/quantumpad/dq_small_pad_a/A = allocate(/obj/machinery/power/quantumpad/dq_small_pad_a, T)
	var/obj/machinery/power/quantumpad/dq_small_pad_b/B = allocate(/obj/machinery/power/quantumpad/dq_small_pad_b, get_step(T, EAST) || T)
	TEST_ASSERT_EQUAL(A.linked_pad(), B, "the first pad found the second, made after it")
	TEST_ASSERT_EQUAL(B.linked_pad(), A, "and the second found the first")
	qdel(B)
	TEST_ASSERT_NULL(A.linked_pad(), "a deleted pad is dropped from the view")

/// A pair declared once with links() writes both ends, and a deleted end clears the other.
/datum/unit_test/dq_small_forms_hotspot_pair_is_one_link

/datum/unit_test/dq_small_forms_hotspot_pair_is_one_link/Run()
	var/turf/T = test_floor()
	var/obj/effect/hotspot/spot = allocate(/obj/effect/hotspot, T)
	var/datum/hot_group/group = new
	rel_set(spot, nameof(spot.our_hot_group), group)
	TEST_ASSERT(spot in group.spot_list, "linking the hotspot to its group lists it there")
	rel_set(spot, nameof(spot.our_hot_group), null)
	TEST_ASSERT(!(spot in group.spot_list), "unlinking takes it off the list")
	rel_set(spot, nameof(spot.our_hot_group), group)
	qdel(spot)
	TEST_ASSERT(!length(group.spot_list), "a deleted hotspot leaves its group")
	qdel(group)
