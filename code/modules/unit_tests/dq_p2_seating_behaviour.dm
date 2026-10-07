// Behaviour-preservation tests for seating and beds (phase 2, furniture): beds, double and psych beds, chairs, office chairs, wooden chairs, the electric
// chair, roller beds and their rack, the wheelchair, the dirty mattress, the holographic ones and the stool. They pin what a player observes through public
// inputs (clicks, the buckle entry points, time), so the same file passes before and after these types move onto the engine forms.
//
// Rules: input goes through p2_seat_click() and the adapters below; state is read through the adapter block and plain vars; every input is followed by
// settle(); nothing depends on message text or on a click result.
//
// Not pinned here and left on the old forms: dragging a person onto a seat (the mob drag belongs to the engine-gaps work), a person dragging themselves
// onto a roller bed or wheelchair to fold it, and the xenomorph nest's own buckling.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// A player's click on `target`, with `held` (when given) in the active hand: the click event a client sends, through the input inbox.
/proc/p2_seat_click(mob/living/actor, atom/target, obj/item/held)
	if(held && actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	else if(!held && actor.get_active_hand())
		actor.drop_item()
	actor.next_click = 0
	var/datum/input_event/click/E = new(actor, target, null, "mapwindow.map", "left=1")
	input_submit(E)
	return E.result

/// The actor uses the item it holds (a click on itself).
/proc/p2_seat_use_in_hand(mob/living/actor, obj/item/I)
	if(actor.get_active_hand() != I)
		actor.drop_item()
		actor.put_in_active_hand(I)
	actor.next_click = 0
	return test_click(actor, I, I, GESTURE_SELF)

/// The material the seat or stool is padded with, or null.
/proc/p2_seat_padding(atom/S)
	var/obj/structure/bed/B = S
	if(istype(B))
		return B.padding_material
	var/obj/item/stool/T = S
	return T.padding_material

/// The people buckled to the seat.
/proc/p2_seat_occupants(obj/structure/S)
	return S.buckled_mob_list()

/// Somebody is buckled to the seat as a person sitting down would be (no wait, no grab).
/proc/p2_seat_buckle(obj/structure/S, mob/living/M)
	M.forceMove(S.loc)
	return S.buckle_mob(M, TRUE)

// ---------------------------------------------------------------------------------------------------------------------
// The base
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_seat
	abstract_type = /datum/unit_test/dq_p2_seat

/datum/unit_test/dq_p2_seat/Run()
	test_driver_begin()
	test_rng(1)
	run_gate()
	for(var/dx in 0 to 3)
		for(var/dy in 0 to 3)
			var/turf/T = floor_at(dx, dy)
			if(T)
				own_turf_contents(T)
	test_driver_end()

/datum/unit_test/dq_p2_seat/proc/run_gate()
	return

/datum/unit_test/dq_p2_seat/proc/floor_at(dx, dy)
	var/turf/origin = run_loc_floor_bottom_left
	return locate(origin.x + dx, origin.y + dy, origin.z)

/datum/unit_test/dq_p2_seat/proc/actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || floor_at(0, 0))
	H.enable_godmode()
	return H

/// A person who can be moved and buckled (no godmode needed, but no hurt either).
/datum/unit_test/dq_p2_seat/proc/patient(turf/T)
	return allocate(/mob/living/carbon/human, T || floor_at(1, 1))

/datum/unit_test/dq_p2_seat/proc/settle()
	test_time(10 SECONDS)

/datum/unit_test/dq_p2_seat/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	p2_seat_click(H, target, held)
	settle()

/datum/unit_test/dq_p2_seat/proc/tool(path, turf/T)
	return dq_fast_tool(path, T || floor_at(0, 0))

/datum/unit_test/dq_p2_seat/proc/sheets(path, n, turf/T)
	return allocate(path, T || floor_at(0, 0), n)

/datum/unit_test/dq_p2_seat/proc/sheet_total(turf/T, path)
	var/n = 0
	for(var/obj/item/stack/S in T)
		if(istype(S, path))
			n += S.get_amount()
	return n

/datum/unit_test/dq_p2_seat/proc/grab(mob/living/carbon/human/grabber, mob/living/carbon/human/victim, state)
	dq_give_zone_sel(grabber)
	dq_give_zone_sel(victim)
	run_chosen_interaction(grabber, victim, "grab")
	var/obj/item/grab/G = grabber.get_active_hand()
	if(istype(G))
		G.state = state
	return G

// ---------------------------------------------------------------------------------------------------------------------
// Padding a bed, a chair or a stool
// ---------------------------------------------------------------------------------------------------------------------

/// A sheet of cloth clicked on a bed pads it, using one sheet.
/datum/unit_test/dq_p2_seat/cloth_pads_a_bed

/datum/unit_test/dq_p2_seat/cloth_pads_a_bed/run_gate()
	var/obj/structure/bed/B = allocate(/obj/structure/bed, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/cloth/C = sheets(/obj/item/stack/material/cloth, 5, H.loc)
	touch(H, B, C)
	TEST_ASSERT_EQUAL(p2_seat_padding(B), get_material_by_name(MAT_CLOTH), "padded with cloth")
	TEST_ASSERT_EQUAL(C.get_amount(), 4, "one sheet used")

/// A padded bed takes no more padding.
/datum/unit_test/dq_p2_seat/a_padded_bed_takes_no_more_padding

/datum/unit_test/dq_p2_seat/a_padded_bed_takes_no_more_padding/run_gate()
	var/obj/structure/bed/B = allocate(/obj/structure/bed/padded, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/cloth/C = sheets(/obj/item/stack/material/cloth, 5, H.loc)
	touch(H, B, C)
	TEST_ASSERT_EQUAL(C.get_amount(), 5, "no sheet used")

/// A stack that is not padding is refused.
/datum/unit_test/dq_p2_seat/steel_is_not_padding

/datum/unit_test/dq_p2_seat/steel_is_not_padding/run_gate()
	var/obj/structure/bed/B = allocate(/obj/structure/bed, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	touch(H, B, S)
	TEST_ASSERT_NULL(p2_seat_padding(B), "not padded")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet used")

/// A chair is padded the same way.
/datum/unit_test/dq_p2_seat/cloth_pads_a_chair

/datum/unit_test/dq_p2_seat/cloth_pads_a_chair/run_gate()
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/cloth/S = sheets(/obj/item/stack/material/cloth, 5, H.loc)
	touch(H, C, S)
	TEST_ASSERT_EQUAL(p2_seat_padding(C), get_material_by_name(MAT_CLOTH), "padded")
	TEST_ASSERT_EQUAL(S.get_amount(), 4, "one sheet used")

/// Some seats take no padding and swallow the stack: roller beds, office chairs, wooden chairs, wheelchairs, the alien bed. (Their own overrides of the bed's
/// stack handling never ran before: they pad now no more: doc/rewrite/intended_changes.md.)
/datum/unit_test/dq_p2_seat/some_seats_take_no_padding

/datum/unit_test/dq_p2_seat/some_seats_take_no_padding/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	for(var/path in list(/obj/structure/bed/roller, /obj/structure/bed/chair/office, /obj/structure/bed/chair/wood, /obj/structure/bed/chair/wheelchair, /obj/structure/bed/alien))
		var/obj/structure/bed/B = allocate(path, floor_at(1, 1))
		var/obj/item/stack/material/cloth/S = sheets(/obj/item/stack/material/cloth, 5, H.loc)
		touch(H, B, S)
		TEST_ASSERT_NULL(p2_seat_padding(B), "[path] was not padded")
		TEST_ASSERT_EQUAL(S.get_amount(), 5, "[path] used no sheet")
		qdel(S)
		qdel(B)

/// Wirecutters take the padding off a padded bed and give the sheet back.
/datum/unit_test/dq_p2_seat/wirecutters_take_the_padding_off

/datum/unit_test/dq_p2_seat/wirecutters_take_the_padding_off/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/B = allocate(/obj/structure/bed/padded, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, B, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_NULL(p2_seat_padding(B), "unpadded")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/cloth), 1, "the cloth lies on the tile")

/// Wirecutters on an unpadded bed change nothing.
/datum/unit_test/dq_p2_seat/wirecutters_on_a_bare_bed_change_nothing

/datum/unit_test/dq_p2_seat/wirecutters_on_a_bare_bed_change_nothing/run_gate()
	var/obj/structure/bed/B = allocate(/obj/structure/bed, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, B, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT(!QDELETED(B), "still there")
	TEST_ASSERT_NULL(p2_seat_padding(B), "still bare")

/// Wirecutters unpad a chair that came padded.
/datum/unit_test/dq_p2_seat/wirecutters_unpad_a_padded_chair

/datum/unit_test/dq_p2_seat/wirecutters_unpad_a_padded_chair/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/structure/bed/chair/comfy/brown/B = allocate(/obj/structure/bed/chair/comfy/brown, floor_at(1, 1))
	TEST_ASSERT_NOTNULL(p2_seat_padding(B), "it starts padded")
	touch(H, B, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_NULL(p2_seat_padding(B), "the cutters took it off")

/// An office chair and a wooden chair keep their padding under wirecutters (the cutters do nothing).
/datum/unit_test/dq_p2_seat/some_seats_keep_their_padding

/datum/unit_test/dq_p2_seat/some_seats_keep_their_padding/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	for(var/path in list(/obj/structure/bed/chair/office, /obj/structure/bed/chair/wood, /obj/structure/bed/roller))
		var/obj/structure/bed/B = allocate(path, floor_at(1, 1))
		B.padding_material = get_material_by_name(MAT_CLOTH)
		touch(H, B, tool(/obj/item/tool/wirecutters))
		TEST_ASSERT_NOTNULL(p2_seat_padding(B), "[path] kept its padding")
		qdel(B)

// ---------------------------------------------------------------------------------------------------------------------
// Taking a seat apart
// ---------------------------------------------------------------------------------------------------------------------

/// A wrench takes a bed down into its material (and the padding).
/datum/unit_test/dq_p2_seat/wrench_dismantles_a_bed

/datum/unit_test/dq_p2_seat/wrench_dismantles_a_bed/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/B = allocate(/obj/structure/bed/padded, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, B, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(B), "the bed is gone")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/plastic), 1, "a sheet of its material")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/cloth), 1, "and a sheet of its padding")

/// A wrench takes a chair down too.
/datum/unit_test/dq_p2_seat/wrench_dismantles_a_chair

/datum/unit_test/dq_p2_seat/wrench_dismantles_a_chair/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, C, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(C), "the chair is gone")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 1, "a sheet of steel")

/// A roller bed, an alien bed, a wheelchair and the holographic seats cannot be taken apart with a wrench.
/datum/unit_test/dq_p2_seat/some_seats_cannot_be_dismantled

/datum/unit_test/dq_p2_seat/some_seats_cannot_be_dismantled/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	for(var/path in list(/obj/structure/bed/roller, /obj/structure/bed/alien, /obj/structure/bed/chair/wheelchair, /obj/structure/bed/chair/holochair, /obj/structure/bed/holobed))
		var/obj/structure/bed/B = allocate(path, floor_at(1, 1))
		touch(H, B, tool(/obj/item/tool/wrench))
		TEST_ASSERT(!QDELETED(B), "[path] is still there")
		qdel(B)

/// A wrench on an electric chair makes it a plain chair again.
/datum/unit_test/dq_p2_seat/wrench_turns_an_electric_chair_into_a_chair

/datum/unit_test/dq_p2_seat/wrench_turns_an_electric_chair_into_a_chair/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/chair/e_chair/E = allocate(/obj/structure/bed/chair/e_chair, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, E, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(E), "the electric chair is gone")
	var/obj/structure/bed/chair/found = locate(/obj/structure/bed/chair) in at
	TEST_ASSERT_NOTNULL(found, "a chair stands there")
	TEST_ASSERT(!istype(found, /obj/structure/bed/chair/e_chair), "and it is a plain one")

/// A secured shock kit clicked on an unpadded chair makes it an electric chair; an unsecured one is refused. (The chair's own stack and kit handling never
/// ran before: doc/rewrite/intended_changes.md.)
/datum/unit_test/dq_p2_seat/a_shock_kit_makes_an_electric_chair

/datum/unit_test/dq_p2_seat/a_shock_kit_makes_an_electric_chair/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/assembly/shock_kit/kit = allocate(/obj/item/assembly/shock_kit, H.loc)
	touch(H, C, kit)
	TEST_ASSERT(!QDELETED(C), "an unsecured kit is refused: the chair stays")
	kit.status = 1
	touch(H, C, kit)
	TEST_ASSERT_NOTNULL(locate(/obj/structure/bed/chair/e_chair) in at, "a secured one makes an electric chair")
	TEST_ASSERT(QDELETED(C), "the chair is gone")

// ---------------------------------------------------------------------------------------------------------------------
// Buckling
// ---------------------------------------------------------------------------------------------------------------------

/// A grab clicked on a bed buckles the grabbed person to it after two seconds. (The old code tried to buckle while the grab was still held, which a
/// grabbed person cannot be: it only moved them onto the tile. doc/rewrite/intended_changes.md.)
/datum/unit_test/dq_p2_seat/a_grab_buckles_a_person_after_two_seconds

/datum/unit_test/dq_p2_seat/a_grab_buckles_a_person_after_two_seconds/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/B = allocate(/obj/structure/bed, at)
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/victim = patient(floor_at(0, 0))
	var/obj/item/grab/G = grab(grabber, victim, GRAB_AGGRESSIVE)
	TEST_ASSERT(istype(G), "the grabber holds a grab")
	p2_seat_click(grabber, B, G)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(victim.loc, floor_at(0, 0), "not moved after a second")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(victim.loc, at, "on the bed's tile after three")
	TEST_ASSERT(victim in p2_seat_occupants(B), "and buckled")

/// A bed with somebody on it takes nobody else.
/datum/unit_test/dq_p2_seat/an_occupied_bed_takes_nobody_else

/datum/unit_test/dq_p2_seat/an_occupied_bed_takes_nobody_else/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/B = allocate(/obj/structure/bed, at)
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/first = patient(floor_at(0, 0))
	var/mob/living/carbon/human/second = patient(floor_at(2, 0))
	TEST_ASSERT(p2_seat_buckle(B, first), "the first is buckled")
	var/obj/item/grab/G = grab(grabber, second, GRAB_AGGRESSIVE)
	p2_seat_click(grabber, B, G)
	settle()
	TEST_ASSERT(!(second in p2_seat_occupants(B)), "the second is not")
	TEST_ASSERT(first in p2_seat_occupants(B), "the first stays")

/// An empty hand on an occupied bed unbuckles the person.
/datum/unit_test/dq_p2_seat/an_empty_hand_unbuckles

/datum/unit_test/dq_p2_seat/an_empty_hand_unbuckles/run_gate()
	var/obj/structure/bed/B = allocate(/obj/structure/bed, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/mob/living/carbon/human/sleeper = patient(floor_at(1, 1))
	TEST_ASSERT(p2_seat_buckle(B, sleeper), "buckled")
	touch(H, B, null)
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(B)), 0, "nobody is buckled any more")

/// A person unbuckles themselves by touching what they sit on.
/datum/unit_test/dq_p2_seat/a_person_unbuckles_themselves

/datum/unit_test/dq_p2_seat/a_person_unbuckles_themselves/run_gate()
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 1))
	TEST_ASSERT(p2_seat_buckle(C, H), "buckled")
	touch(H, C, null)
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(C)), 0, "free")

/// A chair holds the person sitting up; a bed lies them down; the double bed raises them.
/datum/unit_test/dq_p2_seat/what_the_seat_does_to_the_person

/datum/unit_test/dq_p2_seat/what_the_seat_does_to_the_person/run_gate()
	var/obj/structure/bed/bed = allocate(/obj/structure/bed, floor_at(0, 0))
	var/obj/structure/bed/double/double = allocate(/obj/structure/bed/double, floor_at(1, 0))
	var/obj/structure/bed/chair/chair = allocate(/obj/structure/bed/chair, floor_at(2, 0))
	var/mob/living/carbon/human/a = patient(floor_at(0, 1))
	var/mob/living/carbon/human/b = patient(floor_at(1, 1))
	var/mob/living/carbon/human/c = patient(floor_at(2, 1))
	p2_seat_buckle(bed, a)
	p2_seat_buckle(double, b)
	p2_seat_buckle(chair, c)
	TEST_ASSERT(a.lying, "a bed lies the person down")
	TEST_ASSERT(!c.lying, "a chair sits them up")
	TEST_ASSERT_EQUAL(b.pixel_y, 13, "a double bed raises them")
	touch(actor(floor_at(1, 1)), double, null)
	TEST_ASSERT_EQUAL(b.pixel_y, 0, "and puts them down when they are freed")

// ---------------------------------------------------------------------------------------------------------------------
// Beds that are not fixed: roller beds and their rack
// ---------------------------------------------------------------------------------------------------------------------

/// A roller bed carrying someone is dense and drawn raised; empty, neither.
/datum/unit_test/dq_p2_seat/an_occupied_roller_bed_is_dense

/datum/unit_test/dq_p2_seat/an_occupied_roller_bed_is_dense/run_gate()
	var/obj/structure/bed/roller/R = allocate(/obj/structure/bed/roller, floor_at(1, 1))
	var/mob/living/carbon/human/M = patient(floor_at(1, 0))
	TEST_ASSERT(!R.density, "empty: not dense")
	p2_seat_buckle(R, M)
	TEST_ASSERT(R.density, "occupied: dense")
	TEST_ASSERT_EQUAL(M.pixel_y, 6, "the person is raised")
	R.unbuckle_mob(M)
	TEST_ASSERT(!R.density, "freed: not dense again")

/// The roller bed rack collapses an empty roller bed into its folded item; with somebody on it, it frees them and the bed stays. (The bed's own handling of
/// the rack never ran before: doc/rewrite/intended_changes.md.)
/datum/unit_test/dq_p2_seat/the_rack_collapses_a_roller_bed

/datum/unit_test/dq_p2_seat/the_rack_collapses_a_roller_bed/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/roller/R = allocate(/obj/structure/bed/roller, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/mob/living/carbon/human/M = patient(floor_at(1, 0))
	var/obj/item/roller_holder/rack = allocate(/obj/item/roller_holder, H.loc)
	p2_seat_buckle(R, M)
	touch(H, R, rack)
	TEST_ASSERT(!QDELETED(R), "with somebody on it the bed stays")
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(R)), 0, "and they are freed")
	touch(H, R, rack)
	TEST_ASSERT(QDELETED(R), "empty, it is collapsed")
	TEST_ASSERT_NOTNULL(locate(/obj/item/roller) in at, "into a folded roller bed")

/// A folded roller bed used in hand sets the bed up where the person stands, and is used up.
/datum/unit_test/dq_p2_seat/a_folded_roller_bed_deploys

/datum/unit_test/dq_p2_seat/a_folded_roller_bed_deploys/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/roller/folded = allocate(/obj/item/roller, H.loc)
	H.put_in_active_hand(folded)
	p2_seat_use_in_hand(H, folded)
	settle()
	TEST_ASSERT(QDELETED(folded), "the folded bed is used up")
	TEST_ASSERT_NOTNULL(locate(/obj/structure/bed/roller) in H.loc, "a bed stands where they are")

/// A folded roller bed clicked on the rack goes into it; a rack with a bed deploys it in hand.
/datum/unit_test/dq_p2_seat/the_rack_takes_a_folded_bed_and_deploys_it

/datum/unit_test/dq_p2_seat/the_rack_takes_a_folded_bed_and_deploys_it/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/roller_holder/rack = allocate(/obj/item/roller_holder, H.loc)
	var/obj/item/roller/folded = allocate(/obj/item/roller, H.loc)
	touch(H, folded, rack)
	TEST_ASSERT(istype(rack.held, /obj/item/roller), "the rack holds a folded bed")
	H.put_in_active_hand(rack)
	p2_seat_use_in_hand(H, rack)
	settle()
	TEST_ASSERT_NULL(rack.held, "the rack is empty again")
	TEST_ASSERT_NOTNULL(locate(/obj/structure/bed/roller) in H.loc, "a bed was set up")

// ---------------------------------------------------------------------------------------------------------------------
// Small things
// ---------------------------------------------------------------------------------------------------------------------

/// A disk or a plushie clicked on a bed is put on it, offset to reach the pillow.
/datum/unit_test/dq_p2_seat/a_disk_is_tucked_in

/datum/unit_test/dq_p2_seat/a_disk_is_tucked_in/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/B = allocate(/obj/structure/bed, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/disk/D = allocate(/obj/item/disk, H.loc)
	touch(H, B, D)
	TEST_ASSERT_EQUAL(D.loc, at, "the disk lies on the bed")
	TEST_ASSERT_EQUAL(D.pixel_x, 10, "at the pillow")

/// The dirty mattress's wrench bolts it to the floor or frees it (two seconds), and an item clicked on a loose one only says it is not secured.
/datum/unit_test/dq_p2_seat/the_dirty_mattress_is_bolted_with_a_wrench

/datum/unit_test/dq_p2_seat/the_dirty_mattress_is_bolted_with_a_wrench/run_gate()
	var/obj/structure/dirtybed/D = allocate(/obj/structure/dirtybed, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, H.loc)
	H.put_in_active_hand(wrench)
	p2_seat_click(H, D, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(D.anchored, "still bolted after a second")
	test_time(3 SECONDS)
	TEST_ASSERT(!D.anchored, "freed after four")
	test_time(1 SECOND)
	p2_seat_click(H, D, wrench)
	test_time(5 SECONDS)
	TEST_ASSERT(D.anchored, "bolted again")

/// A stool is padded, unpadded and broken down like a bed.
/datum/unit_test/dq_p2_seat/a_stool_is_padded_and_taken_apart

/datum/unit_test/dq_p2_seat/a_stool_is_padded_and_taken_apart/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/item/stool/S = allocate(/obj/item/stool, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/cloth/C = sheets(/obj/item/stack/material/cloth, 5, H.loc)
	touch(H, S, C)
	TEST_ASSERT_EQUAL(p2_seat_padding(S), get_material_by_name(MAT_CLOTH), "padded")
	TEST_ASSERT_EQUAL(C.get_amount(), 4, "one sheet used")
	touch(H, S, tool(/obj/item/tool/wirecutters))
	TEST_ASSERT_NULL(p2_seat_padding(S), "unpadded")
	touch(H, S, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(S), "taken apart")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 1, "a sheet of steel")

// ---------------------------------------------------------------------------------------------------------------------
// The entries that stay on the old forms
// ---------------------------------------------------------------------------------------------------------------------

/// A person dragged onto a bed is buckled to it (the buckle capability's drag, ahead of every movable's default drag buckle).
/datum/unit_test/dq_p2_seat/a_person_dragged_onto_a_bed_is_buckled

/datum/unit_test/dq_p2_seat/a_person_dragged_onto_a_bed_is_buckled/run_gate()
	var/obj/structure/bed/B = allocate(/obj/structure/bed, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/mob/living/carbon/human/M = patient(floor_at(0, 1))
	test_drag(H, M, B)
	settle()
	TEST_ASSERT(M in p2_seat_occupants(B), "the dragged person is buckled")

// ---------------------------------------------------------------------------------------------------------------------
// buckle() on its own (a bare seat that declares nothing else)
// ---------------------------------------------------------------------------------------------------------------------

/// A seat with nothing but the buckle capability.
/obj/structure/p2_bare_seat
	name = "p2 bare seat"
	can_buckle = TRUE
	anchored = TRUE

CAPABILITIES(/obj/structure/p2_bare_seat)
	buckle()

/// buckle.grab waits its time, buckles the grabbed person and lets the grab go; a second grab on a taken seat is refused; an empty hand frees the occupant,
/// and a hand on a seat nobody sits on does nothing.
/datum/unit_test/dq_p2_seat/the_buckle_capability_works_on_a_bare_seat

/datum/unit_test/dq_p2_seat/the_buckle_capability_works_on_a_bare_seat/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/p2_bare_seat/seat = allocate(/obj/structure/p2_bare_seat, at)
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/first = patient(floor_at(0, 0))
	var/mob/living/carbon/human/second = patient(floor_at(2, 0))
	touch(grabber, seat, null)
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(seat)), 0, "an empty hand on an empty seat does nothing")
	var/obj/item/grab/G = grab(grabber, first, GRAB_AGGRESSIVE)
	p2_seat_click(grabber, seat, G)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(seat)), 0, "nobody is buckled before the wait is over")
	test_time(2 SECONDS)
	TEST_ASSERT(first in p2_seat_occupants(seat), "the grabbed person is buckled after it")
	TEST_ASSERT_EQUAL(first.loc, at, "on the seat's tile")
	TEST_ASSERT(!istype(grabber.get_active_hand(), /obj/item/grab), "and the grab let go")
	var/obj/item/grab/second_grab = grab(grabber, second, GRAB_AGGRESSIVE)
	p2_seat_click(grabber, seat, second_grab)
	settle()
	TEST_ASSERT(!(second in p2_seat_occupants(seat)), "a taken seat takes nobody else")
	touch(grabber, seat, null)
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(seat)), 0, "an empty hand frees the occupant")

// ---------------------------------------------------------------------------------------------------------------------
// The wheelchair, its folded item, the nest
// ---------------------------------------------------------------------------------------------------------------------

/// A folded wheelchair used in hand is set up where its carrier stands and keeps its name, and is used up.
/datum/unit_test/dq_p2_seat/a_folded_wheelchair_unfolds

/datum/unit_test/dq_p2_seat/a_folded_wheelchair_unfolds/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/wheelchair/motor/folded = allocate(/obj/item/wheelchair/motor, H.loc)
	p2_seat_use_in_hand(H, folded)
	settle()
	TEST_ASSERT(QDELETED(folded), "the folded chair is used up")
	var/obj/structure/bed/chair/wheelchair/W = locate(/obj/structure/bed/chair/wheelchair) in H.loc
	TEST_ASSERT_NOTNULL(W, "a wheelchair stands where they are")
	TEST_ASSERT(istype(W, /obj/structure/bed/chair/wheelchair/motor), "of the folded kind")

/// A nest takes no padding and no stack: it is hit instead, and a person is not unbuckled by an empty hand the bed's way.
/datum/unit_test/dq_p2_seat/a_nest_takes_no_padding

/datum/unit_test/dq_p2_seat/a_nest_takes_no_padding/run_gate()
	var/obj/structure/bed/nest/N = allocate(/obj/structure/bed/nest, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/cloth/S = sheets(/obj/item/stack/material/cloth, 5, H.loc)
	touch(H, N, S)
	TEST_ASSERT_NULL(p2_seat_padding(N), "not padded")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet used")

/// A wheelchair takes only the sizes its vars say (the small electric chair's range is narrower), and a person it was pulling is let go of when they sit in it.
/datum/unit_test/dq_p2_seat/a_wheelchair_takes_only_its_sizes

/datum/unit_test/dq_p2_seat/a_wheelchair_takes_only_its_sizes/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/bed/chair/wheelchair/small = allocate(/obj/structure/bed/chair/wheelchair/smallmotor, at)
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/big = patient(floor_at(0, 0))
	big.mob_size = MOB_LARGE
	var/obj/item/grab/G = grab(grabber, big, GRAB_AGGRESSIVE)
	p2_seat_click(grabber, small, G)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(length(p2_seat_occupants(small)), 0, "a large person is too large for the small electric chair")
	big.mob_size = MOB_MEDIUM
	if(!istype(grabber.get_active_hand(), /obj/item/grab))
		G = grab(grabber, big, GRAB_AGGRESSIVE)
	else
		G = grabber.get_active_hand()
	small.pull_link(big)
	TEST_ASSERT_EQUAL(small.pulling_target(), big, "the chair pulls them")
	p2_seat_click(grabber, small, G)
	test_time(5 SECONDS)
	TEST_ASSERT(big in p2_seat_occupants(small), "a medium one sits in it")
	TEST_ASSERT_NULL(small.pulling_target(), "and the chair lets go of them")
