// A living mob's one drag_onto() handler (drop_input(), code/modules/mob/living/inventory.dm) dispatches the scoop, the micro-carry scoop and the inventory
// panel in that order. Before it was one handler the type declared three, and the table kept only the last (code/modules/mob/holder.dm,
// species/station/teshari.dm), so the first two never ran.

/datum/unit_test/dq_living_drag_onto
	abstract_type = /datum/unit_test/dq_living_drag_onto

/datum/unit_test/dq_living_drag_onto/Run()
	test_driver_begin()
	run_drag()
	test_driver_end()

/datum/unit_test/dq_living_drag_onto/proc/run_drag()
	return

/// A player's drag of `dragged` onto `over` by `actor` (the adapter's path, which builds the same input event the native drop does).
/datum/unit_test/dq_living_drag_onto/proc/drag(mob/actor, atom/dragged, atom/over)
	actor.input_adapter().drag(actor, dragged, over, null, null, null, null, "")
	test_time(1)

/// A grown human with hands, not in combat mode.
/datum/unit_test/dq_living_drag_onto/proc/grabber(turf/T, species = null)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T, species)
	H.set_combat_mode(FALSE)
	return H

/// The type declares one drag_onto() entry: a second would replace the first in its table.
/datum/unit_test/dq_living_drag_onto/single_entry

/datum/unit_test/dq_living_drag_onto/single_entry/run_drag()
	var/mob/living/carbon/human/H = grabber(run_loc_floor_bottom_left)
	var/datum/lifeform_plan/P = input_plan_of(H)
	TEST_ASSERT_NOTNULL(P, "a human has a lifeform plan")
	var/count = 0
	for(var/datum/centry/C as anything in P.inputs)
		var/datum/entry/E = C.item
		if(E.args["input"] == INPUT_DRAG_ONTO)
			count++
	TEST_ASSERT_EQUAL(count, 1, "a living mob declares exactly one drag_onto() entry")

/// A small mob dragged onto an adjacent human is scooped up into their hands.
/datum/unit_test/dq_living_drag_onto/scoop_small_mob

/datum/unit_test/dq_living_drag_onto/scoop_small_mob/run_drag()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/lifter = grabber(T)
	var/mob/living/simple_mob/animal/passive/cat/pet = allocate(/mob/living/simple_mob/animal/passive/cat, T)
	pet.set_holder_type(/obj/item/holder)
	pet.set_combat_mode(FALSE)
	TEST_ASSERT(issmall(pet) && pet.Adjacent(lifter), "the pet is small and beside the lifter")
	drag(lifter, pet, lifter)
	var/obj/item/holder/H = pet.loc
	TEST_ASSERT(istype(H), "dragging a small mob onto an adjacent human scoops it into a holder")
	own(H)
	TEST_ASSERT(lifter.item_is_in_hands(H), "the holder is in the lifter's hands")

/// A combat-mode lifter does not scoop, and the drag then falls through to the next case, which has nothing to do for a pet.
/datum/unit_test/dq_living_drag_onto/scoop_refused_in_combat

/datum/unit_test/dq_living_drag_onto/scoop_refused_in_combat/run_drag()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/lifter = grabber(T)
	lifter.set_combat_mode(TRUE)
	var/mob/living/simple_mob/animal/passive/cat/pet = allocate(/mob/living/simple_mob/animal/passive/cat, T)
	pet.set_holder_type(/obj/item/holder)
	drag(lifter, pet, lifter)
	TEST_ASSERT_EQUAL(pet.loc, T, "a lifter in combat mode does not scoop the pet")

/// A micro-carry species (teshari) dragged onto the dragger is scooped through the handler.
/datum/unit_test/dq_living_drag_onto/micro_carry

/datum/unit_test/dq_living_drag_onto/micro_carry/run_drag()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/lifter = grabber(T)
	var/mob/living/carbon/human/micro = grabber(T, SPECIES_TESHARI)
	TEST_ASSERT(micro.species.is_micro_carry(micro) && micro.holder_type, "the teshari has micro-carry and a holder type")
	drag(lifter, micro, lifter)
	var/obj/item/holder/H = micro.loc
	TEST_ASSERT(istype(H), "dragging a micro-carry mob onto an adjacent person scoops it")
	own(H)
	TEST_ASSERT(lifter.item_is_in_hands(H), "the micro's holder is in the dragger's hands")

/// A mob dragged onto its dragger opens its inventory panel for them, and a drag onto anything else does not.
/datum/unit_test/dq_living_drag_onto/inventory_panel

/datum/unit_test/dq_living_drag_onto/inventory_panel/run_drag()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/viewer = grabber(T)
	var/mob/living/carbon/human/source = grabber(T)
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	drag(viewer, source, paper)
	TEST_ASSERT_NULL(source.inventory_panel, "dragging a mob onto a paper opens no panel")
	drag(viewer, source, viewer)
	TEST_ASSERT(istype(source.inventory_panel, /datum/inventory_panel), "dragging a mob onto its dragger builds its inventory panel")
	TEST_ASSERT_EQUAL(source.loc, T, "the drag does not move the mob")
