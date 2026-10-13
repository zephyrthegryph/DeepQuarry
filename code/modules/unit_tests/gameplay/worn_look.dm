// What is worn follows the worn thing: a hand mark used to stand in for the state a worn or held look reads. These scenarios change an item the way its
// own toggle does and read what the wearer shows, with nothing marking the wearer by hand.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A welding mask flipped up is drawn flipped up on the head.
/datum/unit_test/dq_gameplay/worn_visor_flip

/datum/unit_test/dq_gameplay/worn_visor_flip/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 2))
	var/obj/item/clothing/head/welding/mask = allocate(/obj/item/clothing/head/welding, tile(2, 2))
	H.equip_to_slot_or_del(mask, SLOT_ID_HEAD)
	refresh_flush()
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_HEAD), mask, "the mask is on the head")
	TEST_ASSERT(overlay_state_shown(H, "welding"), "the lowered mask is drawn ([json_encode(overlay_states(H))])")
	mask.head_welding_toggle_verb(H)
	refresh_flush()
	TEST_ASSERT(overlay_state_shown(H, "weldingup"), "the flipped mask is drawn up ([json_encode(overlay_states(H))])")
	TEST_ASSERT(!overlay_state_shown(H, "welding"), "and the lowered one is gone")
	mask.head_welding_toggle_verb(H)
	refresh_flush()
	TEST_ASSERT(overlay_state_shown(H, "welding"), "flipped down again, it is drawn lowered")

/// A utility belt shows what is in it on the wearer, and follows it in and out.
/datum/unit_test/dq_gameplay/worn_belt_contents

/datum/unit_test/dq_gameplay/worn_belt_contents/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 2))
	var/obj/item/storage/belt/utility/belt = allocate(/obj/item/storage/belt/utility, tile(2, 2))
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, tile(2, 2))
	H.equip_to_slot_or_del(belt, SLOT_ID_BELT)
	refresh_flush()
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_BELT), belt, "the belt is on the waist")
	var/before = overlay_count(H)
	TEST_ASSERT(belt.handle_item_insertion(crowbar, TRUE), "the crowbar goes in the belt")
	refresh_flush()
	TEST_ASSERT(overlay_count(H) > before, "the crowbar shows on the belt the player wears ([before] -> [overlay_count(H)] overlays)")
	var/with_crowbar = overlay_count(H)
	belt.remove_from_storage(crowbar, tile(2, 2))
	refresh_flush()
	TEST_ASSERT(overlay_count(H) < with_crowbar, "and goes from it when it is taken out ([with_crowbar] -> [overlay_count(H)] overlays)")

/// Glasses flipped through their own toggle change the sprite on the face.
/datum/unit_test/dq_gameplay/worn_glasses_state

/datum/unit_test/dq_gameplay/worn_glasses_state/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 2))
	var/obj/item/clothing/glasses/eyepatch/patch = allocate(/obj/item/clothing/glasses/eyepatch, tile(2, 2))
	H.equip_to_slot_or_del(patch, SLOT_ID_EYES)
	refresh_flush()
	var/was = patch.icon_state
	TEST_ASSERT(overlay_state_shown(H, was), "the eyepatch is drawn as [was] ([json_encode(overlay_states(H))])")
	patch.set_icon_state("[was]_1")
	refresh_flush()
	TEST_ASSERT(overlay_state_shown(H, "[was]_1"), "the eyepatch moved to the other eye is drawn so ([json_encode(overlay_states(H))])")
	TEST_ASSERT(!overlay_state_shown(H, was), "and no longer on the first")

/// The icon states of `A`'s drawn overlays.
/datum/unit_test/dq_gameplay/proc/overlay_states(atom/A)
	. = list()
	for(var/overlay in A.overlays)
		var/mutable_appearance/MA = new(overlay)
		. += "[MA.icon_state]"

/// How many overlays `A` shows, counting the ones inside the ones it shows (a belt's contents are drawn into the belt's own image).
/datum/unit_test/dq_gameplay/proc/overlay_count(atom/A)
	var/total = 0
	var/list/todo = list()
	for(var/overlay in A.overlays)
		todo += new /mutable_appearance(overlay)
	while(length(todo))
		var/mutable_appearance/MA = todo[length(todo)]
		todo.len--
		total++
		for(var/inner in MA.overlays)
			todo += new /mutable_appearance(inner)
	return total

/// TRUE when one of `A`'s drawn overlays is the state `state`.
/datum/unit_test/dq_gameplay/proc/overlay_state_shown(atom/A, state)
	return (state in overlay_states(A))

#endif
