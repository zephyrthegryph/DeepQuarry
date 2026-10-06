// Behaviour-preservation tests for tables (phase 2, furniture): the plain table, the plated and reinforced tables, the carpeted gambling table, the
// benches and the racks that share the table's code. They pin what a player can observe through public inputs (clicks, drags, the context menu,
// damage entry points, movement checks, time), so the same file passes before and after the table moves onto the engine forms.
//
// Rules the tests keep:
//   - Input goes through p2_table_click(), the adapters below (a drag and a menu pick differ between the old and the new input path) and the damage entry
//     points; never an op key.
//   - State is read through the adapter block (the only place that names today's accessors) and plain vars (loc, density, name, flipped, dir).
//   - Every input is followed by settle() (10 seconds of kernel time) unless the test is about the wait itself; those assert state at explicit times.
//   - Nothing depends on message text or on a click result's outcome: the tests assert the state that results.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: today's accessors, wrapped. After the conversion only these bodies change.
// ---------------------------------------------------------------------------------------------------------------------

/// The display name of the material with this id ("steel").
/proc/p2_material_name(id)
	var/datum/material/M = get_material_by_name(id)
	return M.display_name

/// The material the table is plated with (a /datum/material), or null for a frame.
/proc/p2_table_material(obj/structure/table/T)
	return T.material()

/// The material the table is reinforced with, or null.
/proc/p2_table_reinforcement(obj/structure/table/T)
	return T.reinforced()

/// The table has a carpet on it.
/proc/p2_table_carpeted(obj/structure/table/T)
	return !!T.carpeted

/// The table is flipped on its side.
/proc/p2_table_flipped(obj/structure/table/T)
	return T.flipped == 1

/// Reinforces the table with `M` as a spell or a theme leaves it (no sheet, no wait): the layer is there and the strength follows.
/proc/p2_table_reinforce_directly(obj/structure/table/T, datum/material/M)
	T.set_layers(T.material(), M)
	T.refresh_layers()

/// The shards the last break produced (a list, possibly empty).
/proc/p2_table_last_shards(obj/structure/table/T)
	return T.last_break_shards

/// How far the frame is built: "frame", "plated" or "reinforced".
/proc/p2_table_stage(obj/structure/table/T)
	if(T.reinforced())
		return "reinforced"
	if(T.material())
		return "plated"
	return "frame"

/// A player's click on `target`, with `held` (when given) in the active hand: the click event a client sends, through the input inbox. It runs the
/// mob's own click handling on a type that has no engine ops yet and the resolver on one that has, so one adapter drives both.
/proc/p2_table_click(mob/living/actor, atom/target, obj/item/held)
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

/// The actor drags `O` onto the table (a mouse drag: the dragged thing is what the table works with).
/proc/p2_table_drag(mob/living/actor, obj/structure/table/T, atom/movable/O)
	actor.next_click = 0
	test_click(actor, T, O, GESTURE_DRAG)

/// The actor picks the entry named `label` ("Flip table", "Put table back") from the table's context menu. TRUE when the menu offered it (it ran).
/proc/p2_table_menu(mob/living/actor, obj/structure/table/T, label)
	var/datum/op_result/result = test_menu(actor, T, label == "Flip table" ? "flip" : "put_back")
	return result?.outcome == ACT_COMMITTED

/// The context menu offers the entry (available or greyed out) to this actor.
/proc/p2_table_menu_offers(mob/living/actor, obj/structure/table/T, label)
	for(var/list/row as anything in action_options(actor, T, actor.get_active_hand()))
		if(row["name"] == label)
			return TRUE
	return FALSE

/// The mob drags itself onto the table (the climb capability's drag).
/proc/p2_table_climb(mob/living/climber, obj/structure/table/T)
	climber.next_click = 0
	test_drag(climber, climber, T)

/// The number of overlay images the table draws now (its layers: frame, plating, reinforcement, carpet).
/proc/p2_table_layers(obj/structure/table/T)
	return length(T.appearance_overlays())

/// The actor takes a grab on `victim` and holds it at `state`.
/proc/p2_table_grab(mob/living/carbon/human/grabber, mob/living/victim, state)
	run_chosen_interaction(grabber, victim, "grab")
	var/obj/item/grab/G = grabber.get_active_hand()
	if(istype(G))
		G.state = state
	return G

/// A mob wearing down a table the way a claw or a bite does: `damage` of generic attack.
/proc/p2_table_mob_attack(mob/living/attacker, obj/structure/table/T, damage)
	return generic_hit(T, attacker, damage)

// ---------------------------------------------------------------------------------------------------------------------
// The base
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_table
	abstract_type = /datum/unit_test/dq_p2_table

/datum/unit_test/dq_p2_table/Run()
	test_driver_begin()
	test_rng(1)
	run_gate()
	for(var/dx in 0 to 3)
		for(var/dy in 0 to 3)
			var/turf/T = floor_at(dx, dy)
			if(T)
				own_turf_contents(T)
	test_driver_end()

/datum/unit_test/dq_p2_table/proc/run_gate()
	return

/// The floor `dx` east and `dy` north of the block's bottom left corner.
/datum/unit_test/dq_p2_table/proc/floor_at(dx, dy)
	var/turf/origin = run_loc_floor_bottom_left
	return locate(origin.x + dx, origin.y + dy, origin.z)

/// A conscious person with hands, who cannot be knocked out by the test's passing time.
/datum/unit_test/dq_p2_table/proc/actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || floor_at(0, 0))
	H.enable_godmode()
	return H

/// The actor grabs `victim` and holds the grab at `state` (both need a zone selector to grab and to be hit).
/datum/unit_test/dq_p2_table/proc/grab(mob/living/carbon/human/grabber, mob/living/carbon/human/victim, state)
	dq_give_zone_sel(grabber)
	dq_give_zone_sel(victim)
	return p2_table_grab(grabber, victim, state)

/// Time for any wait a tool or a drag may start.
/datum/unit_test/dq_p2_table/proc/settle()
	test_time(10 SECONDS)

/// The actor puts `held` in the active hand (an empty hand when null), clicks the target and waits.
/datum/unit_test/dq_p2_table/proc/touch(mob/living/carbon/human/H, atom/target, obj/item/held)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	p2_table_click(H, target, held)
	settle()

/// A tool with no speed penalty.
/datum/unit_test/dq_p2_table/proc/tool(path, turf/T)
	return dq_fast_tool(path, T || floor_at(0, 0))

/// A tool at normal speed, for the tests that check how long a job takes.
/datum/unit_test/dq_p2_table/proc/slow_tool(path, turf/T)
	return allocate(path, T || floor_at(0, 0))

/// A stack of `n` sheets of the material.
/datum/unit_test/dq_p2_table/proc/sheets(path, n, turf/T)
	return allocate(path, T || floor_at(0, 0), n)

/// A table frame (steel stack recipe), plated and reinforced as asked: made the way a builder makes it, not by a preset.
/datum/unit_test/dq_p2_table/proc/frame(turf/T)
	return allocate(/obj/structure/table, T || floor_at(1, 1))

/// The number of `path` things lying on the turf.
/datum/unit_test/dq_p2_table/proc/count_on(turf/T, path)
	var/n = 0
	for(var/obj/O in T)
		if(istype(O, path))
			n++
	return n

/// Total sheets of a stack type lying on the turf.
/datum/unit_test/dq_p2_table/proc/sheet_total(turf/T, path)
	var/n = 0
	for(var/obj/item/stack/S in T)
		if(istype(S, path))
			n += S.get_amount()
	return n

/// Plates a frame by the builder's way: steel sheet clicked on the frame.
/datum/unit_test/dq_p2_table/proc/plate(mob/living/carbon/human/H, obj/structure/table/T, path = /obj/item/stack/material/steel)
	touch(H, T, sheets(path, 5, H.loc))

// ---------------------------------------------------------------------------------------------------------------------
// Placing things on a table
// ---------------------------------------------------------------------------------------------------------------------

/// A held item clicked on a plated table is put on it.
/datum/unit_test/dq_p2_table/click_places_the_held_item

/datum/unit_test/dq_p2_table/click_places_the_held_item/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/pen = allocate(/obj/item/pen, H.loc)
	touch(H, T, pen)
	TEST_ASSERT_EQUAL(pen.loc, at, "the item went onto the table's tile")
	TEST_ASSERT_NULL(H.get_active_hand(), "and out of the hand")

/// A bare frame has nothing to put things on: the item stays in the hand.
/datum/unit_test/dq_p2_table/frame_refuses_items

/datum/unit_test/dq_p2_table/frame_refuses_items/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/pen = allocate(/obj/item/pen, H.loc)
	touch(H, T, pen)
	TEST_ASSERT_EQUAL(H.get_active_hand(), pen, "the pen stays in the hand")
	TEST_ASSERT_EQUAL(pen.loc, H, "and in the actor")

/// An item dragged from the hand onto the table lands on it.
/datum/unit_test/dq_p2_table/drag_from_the_hand_places_the_item

/datum/unit_test/dq_p2_table/drag_from_the_hand_places_the_item/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/pen = allocate(/obj/item/pen, H.loc)
	H.put_in_active_hand(pen)
	p2_table_drag(H, T, pen)
	settle()
	TEST_ASSERT_NULL(H.get_active_hand(), "the pen left the hand")
	TEST_ASSERT_EQUAL(pen.loc, at, "and lies on the table")

/// A small item lying beside the table, dragged onto it, is pushed onto it.
/datum/unit_test/dq_p2_table/drag_pushes_a_floor_item_onto_the_table

/datum/unit_test/dq_p2_table/drag_pushes_a_floor_item_onto_the_table/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/pen = allocate(/obj/item/pen, floor_at(2, 1))
	p2_table_drag(H, T, pen)
	settle()
	TEST_ASSERT_EQUAL(pen.loc, at, "the pen was pushed onto the table")

/// Someone knocked out can't push things around.
/datum/unit_test/dq_p2_table/drag_by_the_incapacitated_does_nothing

/datum/unit_test/dq_p2_table/drag_by_the_incapacitated_does_nothing/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/pen = allocate(/obj/item/pen, floor_at(2, 1))
	H.set_stat(UNCONSCIOUS)
	p2_table_drag(H, T, pen)
	settle()
	TEST_ASSERT_EQUAL(pen.loc, floor_at(2, 1), "the pen did not move")

// ---------------------------------------------------------------------------------------------------------------------
// Plating
// ---------------------------------------------------------------------------------------------------------------------

/// A sheet of steel clicked on a frame plates it with steel, using one sheet.
/datum/unit_test/dq_p2_table/steel_plates_a_frame

/datum/unit_test/dq_p2_table/steel_plates_a_frame/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	touch(H, T, S)
	TEST_ASSERT_EQUAL(p2_table_material(T), get_material_by_name(MAT_STEEL), "plated with steel")
	TEST_ASSERT_EQUAL(S.get_amount(), 4, "one sheet was used")
	TEST_ASSERT_EQUAL(T.name, "[p2_material_name(MAT_STEEL)] table", "it is named for its material")
	TEST_ASSERT_EQUAL(p2_table_stage(T), "plated", "a plated table")

/// The plating takes two seconds.
/datum/unit_test/dq_p2_table/plating_takes_two_seconds

/datum/unit_test/dq_p2_table/plating_takes_two_seconds/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	H.put_in_active_hand(S)
	p2_table_click(H, T, S)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(p2_table_material(T), "not plated after a second")
	test_time(2 SECONDS)
	TEST_ASSERT_NOTNULL(p2_table_material(T), "plated after three")

/// Plating raises the table's strength to half the material's integrity, keeping the damage it had.
/datum/unit_test/dq_p2_table/plating_sets_strength_and_keeps_damage

/datum/unit_test/dq_p2_table/plating_sets_strength_and_keeps_damage/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT_EQUAL(T.max_integrity, 10, "a frame is flimsy")
	T.take_damage(4, BRUTE, MELEE)
	var/lost = T.max_integrity - T.get_integrity()
	TEST_ASSERT(lost > 0, "the frame took damage")
	plate(H, T)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	TEST_ASSERT_EQUAL(T.max_integrity, steel.integrity / 2, "half the steel's integrity")
	TEST_ASSERT_EQUAL(T.max_integrity - T.get_integrity(), lost, "the damage it had is kept")

/// A plated table is not plated again: the stack is only put on it.
/datum/unit_test/dq_p2_table/a_plated_table_is_not_plated_again

/datum/unit_test/dq_p2_table/a_plated_table_is_not_plated_again/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	touch(H, T, S)
	TEST_ASSERT_EQUAL(p2_table_material(T), get_material_by_name(MAT_WOOD), "still wood")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet was used")

/// A table that cannot be plated (a rack) takes no plating.
/datum/unit_test/dq_p2_table/a_rack_takes_no_plating

/datum/unit_test/dq_p2_table/a_rack_takes_no_plating/run_gate()
	var/obj/structure/table/rack/R = allocate(/obj/structure/table/rack, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	touch(H, R, S)
	TEST_ASSERT_NULL(p2_table_material(R), "still bare")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet was used")

/// Glass is a material too: a glass table.
/datum/unit_test/dq_p2_table/glass_plates_a_frame

/datum/unit_test/dq_p2_table/glass_plates_a_frame/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	plate(H, T, /obj/item/stack/material/glass)
	TEST_ASSERT_EQUAL(p2_table_material(T), get_material_by_name(MAT_GLASS), "plated with glass")

/// Two people plating at once use one sheet between them: the second finds the table plated.
/datum/unit_test/dq_p2_table/plating_twice_at_once_uses_one_sheet

/datum/unit_test/dq_p2_table/plating_twice_at_once_uses_one_sheet/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/A = actor(floor_at(1, 0))
	var/mob/living/carbon/human/B = actor(floor_at(0, 1))
	var/obj/item/stack/material/steel/SA = sheets(/obj/item/stack/material/steel, 5, A.loc)
	var/obj/item/stack/material/steel/SB = sheets(/obj/item/stack/material/steel, 5, B.loc)
	A.put_in_active_hand(SA)
	B.put_in_active_hand(SB)
	p2_table_click(A, T, SA)
	p2_table_click(B, T, SB)
	settle()
	TEST_ASSERT_EQUAL(SA.get_amount() + SB.get_amount(), 9, "one sheet in all")

// ---------------------------------------------------------------------------------------------------------------------
// Reinforcing
// ---------------------------------------------------------------------------------------------------------------------

/// A steel stack held in the hand and dragged onto a plated table reinforces it.
/datum/unit_test/dq_p2_table/dragging_steel_reinforces_a_plated_table

/datum/unit_test/dq_p2_table/dragging_steel_reinforces_a_plated_table/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	H.put_in_active_hand(S)
	p2_table_drag(H, T, S)
	settle()
	TEST_ASSERT_EQUAL(p2_table_reinforcement(T), get_material_by_name(MAT_STEEL), "reinforced with steel")
	TEST_ASSERT_EQUAL(S.get_amount(), 4, "one sheet was used")
	TEST_ASSERT_EQUAL(p2_table_stage(T), "reinforced", "a reinforced table")
	var/datum/material/wood = get_material_by_name(MAT_WOOD)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	TEST_ASSERT_EQUAL(T.max_integrity, wood.integrity / 2 + steel.integrity / 2, "strength adds half the reinforcement's integrity")
	TEST_ASSERT_EQUAL(T.name, "reinforced [wood.display_name] table", "named for it")

/// The reinforcing takes two seconds.
/datum/unit_test/dq_p2_table/reinforcing_takes_two_seconds

/datum/unit_test/dq_p2_table/reinforcing_takes_two_seconds/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	H.put_in_active_hand(S)
	p2_table_drag(H, T, S)
	test_time(1 SECOND)
	TEST_ASSERT_NULL(p2_table_reinforcement(T), "not reinforced after a second")
	test_time(2 SECONDS)
	TEST_ASSERT_NOTNULL(p2_table_reinforcement(T), "reinforced after three")

/// Clicking the stack on a plated table does not reinforce it (it is put on the table).
/datum/unit_test/dq_p2_table/clicking_steel_on_a_plated_table_does_not_reinforce

/datum/unit_test/dq_p2_table/clicking_steel_on_a_plated_table_does_not_reinforce/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	touch(H, T, S)
	TEST_ASSERT_NULL(p2_table_reinforcement(T), "not reinforced")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet used")
	TEST_ASSERT_EQUAL(S.loc, at, "the stack lies on the table")

/// A frame has to be plated before it is reinforced.
/datum/unit_test/dq_p2_table/a_frame_is_not_reinforced

/datum/unit_test/dq_p2_table/a_frame_is_not_reinforced/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	H.put_in_active_hand(S)
	p2_table_drag(H, T, S)
	settle()
	TEST_ASSERT_NULL(p2_table_reinforcement(T), "not reinforced")
	TEST_ASSERT_NULL(p2_table_material(T), "not plated by a drag either")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet used")

/// A reinforced table takes no more reinforcement.
/datum/unit_test/dq_p2_table/a_reinforced_table_is_not_reinforced_again

/datum/unit_test/dq_p2_table/a_reinforced_table_is_not_reinforced_again/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/reinforced, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/material/plasteel/S = sheets(/obj/item/stack/material/plasteel, 5, H.loc)
	H.put_in_active_hand(S)
	p2_table_drag(H, T, S)
	settle()
	TEST_ASSERT_EQUAL(p2_table_reinforcement(T), get_material_by_name(MAT_STEEL), "still steel")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet used")

/// A flipped table is put back before it is reinforced.
/datum/unit_test/dq_p2_table/a_flipped_table_is_not_reinforced

/datum/unit_test/dq_p2_table/a_flipped_table_is_not_reinforced/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(H, T, "Flip table"), "flipped")
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	H.put_in_active_hand(S)
	p2_table_drag(H, T, S)
	settle()
	TEST_ASSERT_NULL(p2_table_reinforcement(T), "not reinforced")
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "no sheet used")

/// A bench, a rack and a pod table cannot be reinforced.
/datum/unit_test/dq_p2_table/benches_and_racks_are_not_reinforced

/datum/unit_test/dq_p2_table/benches_and_racks_are_not_reinforced/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/list/types = list(/obj/structure/table/bench/wooden, /obj/structure/table/rack/steel, /obj/structure/table/alien)
	for(var/path in types)
		var/obj/structure/table/T = allocate(path, floor_at(1, 1))
		var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
		H.drop_item()
		H.put_in_active_hand(S)
		var/had = p2_table_reinforcement(T)
		p2_table_drag(H, T, S)
		settle()
		TEST_ASSERT_EQUAL(p2_table_reinforcement(T), had, "[path] was not reinforced")
		TEST_ASSERT_EQUAL(S.get_amount(), 5, "[path] used no sheet")
		qdel(S)
		qdel(T)

// ---------------------------------------------------------------------------------------------------------------------
// Taking a table apart
// ---------------------------------------------------------------------------------------------------------------------

/// A screwdriver takes the reinforcement off a reinforced table and gives the sheet back.
/datum/unit_test/dq_p2_table/screwdriver_removes_the_reinforcement

/datum/unit_test/dq_p2_table/screwdriver_removes_the_reinforcement/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/reinforced, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, T, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_NULL(p2_table_reinforcement(T), "the reinforcement is off")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 1, "one steel sheet lies on the tile")
	TEST_ASSERT_NOTNULL(p2_table_material(T), "the plating stays")
	TEST_ASSERT_EQUAL(p2_table_stage(T), "plated", "a plated table again")

/// Taking the reinforcement off takes four seconds.
/datum/unit_test/dq_p2_table/unreinforcing_takes_four_seconds

/datum/unit_test/dq_p2_table/unreinforcing_takes_four_seconds/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/reinforced, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/tool/screwdriver/driver = slow_tool(/obj/item/tool/screwdriver)
	H.put_in_active_hand(driver)
	p2_table_click(H, T, driver)
	test_time(3 SECONDS)
	TEST_ASSERT_NOTNULL(p2_table_reinforcement(T), "still reinforced after three seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(p2_table_reinforcement(T), "off after five")

/// A screwdriver on a table with no reinforcement does nothing to it.
/datum/unit_test/dq_p2_table/screwdriver_on_an_unreinforced_table_changes_nothing

/datum/unit_test/dq_p2_table/screwdriver_on_an_unreinforced_table_changes_nothing/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, T, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_table_material(T), get_material_by_name(MAT_STEEL), "still plated")
	TEST_ASSERT(!QDELETED(T), "still there")

/// A wrench takes the plating off a plated table (two seconds) and gives the sheet back.
/datum/unit_test/dq_p2_table/wrench_removes_the_plating

/datum/unit_test/dq_p2_table/wrench_removes_the_plating/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/tool/wrench/wrench = slow_tool(/obj/item/tool/wrench)
	H.put_in_active_hand(wrench)
	p2_table_click(H, T, wrench)
	test_time(1 SECOND)
	TEST_ASSERT_NOTNULL(p2_table_material(T), "still plated after a second")
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(p2_table_material(T), "bare after four")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/wood), 1, "a sheet of wood lies on the tile")
	TEST_ASSERT_EQUAL(T.max_integrity, 10, "a frame's strength again")
	TEST_ASSERT_EQUAL(T.name, "table frame", "named a frame")

/// A wrench does not take the plating off a reinforced table.
/datum/unit_test/dq_p2_table/wrench_is_blocked_by_the_reinforcement

/datum/unit_test/dq_p2_table/wrench_is_blocked_by_the_reinforcement/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/reinforced, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, T, tool(/obj/item/tool/wrench))
	TEST_ASSERT_NOTNULL(p2_table_material(T), "still plated")
	TEST_ASSERT_NOTNULL(p2_table_reinforcement(T), "still reinforced")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material), 0, "nothing came off")

/// A wrench does not take the plating off a carpeted table.
/datum/unit_test/dq_p2_table/wrench_is_blocked_by_the_carpet

/datum/unit_test/dq_p2_table/wrench_is_blocked_by_the_carpet/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/gamblingtable, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, T, tool(/obj/item/tool/wrench))
	TEST_ASSERT_NOTNULL(p2_table_material(T), "still plated")
	TEST_ASSERT(p2_table_carpeted(T), "still carpeted")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material), 0, "nothing came off")

/// A wrench on a bare frame takes it down into a sheet of steel (two seconds).
/datum/unit_test/dq_p2_table/wrench_dismantles_a_frame

/datum/unit_test/dq_p2_table/wrench_dismantles_a_frame/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = frame(at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/tool/wrench/wrench = slow_tool(/obj/item/tool/wrench)
	H.put_in_active_hand(wrench)
	p2_table_click(H, T, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(T), "still standing after a second")
	test_time(3 SECONDS)
	TEST_ASSERT(QDELETED(T), "gone after four")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 1, "one steel sheet lies on the tile")

/// The whole way down: reinforced, then plated, then the frame, each by its own tool, ends in one sheet of each material.
/datum/unit_test/dq_p2_table/a_built_table_comes_apart_in_the_order_it_went_together

/datum/unit_test/dq_p2_table/a_built_table_comes_apart_in_the_order_it_went_together/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = frame(at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	plate(H, T, /obj/item/stack/material/wood)
	var/obj/item/stack/material/steel/S = sheets(/obj/item/stack/material/steel, 5, H.loc)
	H.drop_item()
	H.put_in_active_hand(S)
	p2_table_drag(H, T, S)
	settle()
	TEST_ASSERT_EQUAL(p2_table_stage(T), "reinforced", "built")
	touch(H, T, tool(/obj/item/tool/wrench))
	TEST_ASSERT_EQUAL(p2_table_stage(T), "reinforced", "the wrench is not the way in")
	touch(H, T, tool(/obj/item/tool/screwdriver))
	TEST_ASSERT_EQUAL(p2_table_stage(T), "plated", "the screwdriver took the reinforcement")
	touch(H, T, tool(/obj/item/tool/wrench))
	TEST_ASSERT_EQUAL(p2_table_stage(T), "frame", "the wrench took the plating")
	touch(H, T, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(T), "and then the frame")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/wood), 1, "a sheet of wood came back")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 2, "two sheets of steel: the reinforcement and the frame")

/// A table that cannot be dismantled (alien, dark glass, a survival pod) stays when a wrench is used on it.
/datum/unit_test/dq_p2_table/some_tables_cannot_be_dismantled

/datum/unit_test/dq_p2_table/some_tables_cannot_be_dismantled/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	for(var/path in list(/obj/structure/table/survival_pod, /obj/structure/table/darkglass, /obj/structure/table/fancyblack))
		var/obj/structure/table/T = allocate(path, floor_at(1, 1))
		touch(H, T, tool(/obj/item/tool/wrench))
		TEST_ASSERT(!QDELETED(T), "[path] is still there")
		qdel(T)

// ---------------------------------------------------------------------------------------------------------------------
// Carpet
// ---------------------------------------------------------------------------------------------------------------------

/// A carpet tile clicked on a plated table carpets it, using one tile.
/datum/unit_test/dq_p2_table/carpet_covers_a_plated_table

/datum/unit_test/dq_p2_table/carpet_covers_a_plated_table/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/tile/carpet/C = sheets(/obj/item/stack/tile/carpet, 5, H.loc)
	touch(H, T, C)
	TEST_ASSERT(p2_table_carpeted(T), "carpeted")
	TEST_ASSERT_EQUAL(C.get_amount(), 4, "one tile used")
	TEST_ASSERT_EQUAL(T.carpeted_type, /obj/item/stack/tile/carpet, "it remembers the kind of carpet")

/// The carpet goes on at once.
/datum/unit_test/dq_p2_table/carpeting_is_instant

/datum/unit_test/dq_p2_table/carpeting_is_instant/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/woodentable, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/tile/carpet/C = sheets(/obj/item/stack/tile/carpet, 5, H.loc)
	H.put_in_active_hand(C)
	p2_table_click(H, T, C)
	TEST_ASSERT(p2_table_carpeted(T), "carpeted with no time passing")

/// A frame has no surface to carpet.
/datum/unit_test/dq_p2_table/a_frame_is_not_carpeted

/datum/unit_test/dq_p2_table/a_frame_is_not_carpeted/run_gate()
	var/obj/structure/table/T = frame()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/tile/carpet/C = sheets(/obj/item/stack/tile/carpet, 5, H.loc)
	touch(H, T, C)
	TEST_ASSERT(!p2_table_carpeted(T), "not carpeted")
	TEST_ASSERT_EQUAL(C.get_amount(), 5, "no tile used")

/// A carpeted table takes no second carpet.
/datum/unit_test/dq_p2_table/a_carpeted_table_takes_no_second_carpet

/datum/unit_test/dq_p2_table/a_carpeted_table_takes_no_second_carpet/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/gamblingtable, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/stack/tile/carpet/C = sheets(/obj/item/stack/tile/carpet, 5, H.loc)
	touch(H, T, C)
	TEST_ASSERT_EQUAL(C.get_amount(), 5, "no tile used")

/// A crowbar lifts the carpet and leaves the tile on the table's tile.
/datum/unit_test/dq_p2_table/crowbar_lifts_the_carpet

/datum/unit_test/dq_p2_table/crowbar_lifts_the_carpet/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/gamblingtable, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, T, tool(/obj/item/tool/crowbar))
	TEST_ASSERT(!p2_table_carpeted(T), "the carpet is off")
	TEST_ASSERT_EQUAL(count_on(at, /obj/item/stack/tile/carpet), 1, "a carpet tile lies on the tile")

/// A crowbar on an uncarpeted table changes nothing.
/datum/unit_test/dq_p2_table/crowbar_on_an_uncarpeted_table_changes_nothing

/datum/unit_test/dq_p2_table/crowbar_on_an_uncarpeted_table_changes_nothing/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	touch(H, T, tool(/obj/item/tool/crowbar))
	TEST_ASSERT_EQUAL(p2_table_material(T), get_material_by_name(MAT_STEEL), "still plated")
	TEST_ASSERT(!QDELETED(T), "still there")

// ---------------------------------------------------------------------------------------------------------------------
// Repair, damage and breaking
// ---------------------------------------------------------------------------------------------------------------------

/// A lit welder repairs a fifth of the table's strength in two seconds.
/datum/unit_test/dq_p2_table/welder_repairs_a_fifth

/datum/unit_test/dq_p2_table/welder_repairs_a_fifth/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	T.take_damage(T.max_integrity / 2, BRUTE, MELEE)
	var/before = T.get_integrity()
	TEST_ASSERT(before < T.max_integrity, "damaged")
	touch(H, T, dq_fueled_welder(H.loc))
	TEST_ASSERT_EQUAL(T.get_integrity(), min(T.max_integrity, before + T.max_integrity / 5), "a fifth of the strength came back")

/// A welder on an undamaged table does nothing.
/datum/unit_test/dq_p2_table/welder_on_an_undamaged_table_changes_nothing

/datum/unit_test/dq_p2_table/welder_on_an_undamaged_table_changes_nothing/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/weldingtool/welder = dq_fueled_welder(H.loc)
	var/fuel = welder.get_fuel()
	touch(H, T, welder)
	TEST_ASSERT_EQUAL(welder.get_fuel(), fuel, "no fuel used")
	TEST_ASSERT_EQUAL(T.get_integrity(), T.max_integrity, "still whole")

/// Enough damage breaks a table into what it was made of.
/datum/unit_test/dq_p2_table/enough_damage_breaks_a_table

/datum/unit_test/dq_p2_table/enough_damage_breaks_a_table/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	T.take_damage(T.max_integrity * 3, BRUTE, MELEE)
	TEST_ASSERT(QDELETED(T), "the table broke")
	var/pieces = 0
	for(var/obj/item/I in at)
		pieces++
	TEST_ASSERT(pieces > 0, "it left something behind")

/// A full break returns every layer: the plating, the reinforcement, the carpet and the frame's steel.
/datum/unit_test/dq_p2_table/a_full_break_returns_every_layer

/datum/unit_test/dq_p2_table/a_full_break_returns_every_layer/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/gamblingtable, at)
	p2_table_reinforce_directly(T, get_material_by_name(MAT_STEEL))
	var/list/shards = T.break_to_parts(TRUE)
	TEST_ASSERT(QDELETED(T), "broken")
	TEST_ASSERT_EQUAL(length(shards), 0, "a full return makes no shards")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 2, "steel: the reinforcement and the frame")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/wood), 1, "wood: the plating")
	TEST_ASSERT_EQUAL(count_on(at, /obj/item/stack/tile/carpet), 1, "and the carpet")

/// A table broken on a turf that already has one comes apart entirely: only one table stands on a tile.
/datum/unit_test/dq_p2_table/one_table_per_tile

/datum/unit_test/dq_p2_table/one_table_per_tile/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/first = allocate(/obj/structure/table/steel, at)
	var/obj/structure/table/second = new /obj/structure/table/steel(at)
	TEST_ASSERT(QDELETED(second), "the newcomer broke")
	TEST_ASSERT(!QDELETED(first), "the first stands")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 2, "its steel plating and its frame came back whole")

/// Brittle plating (glass) multiplies the damage, unless the table is reinforced with something that is not brittle.
/datum/unit_test/dq_p2_table/brittle_tables_take_more_damage

/datum/unit_test/dq_p2_table/brittle_tables_take_more_damage/run_gate()
	var/obj/structure/table/glass = allocate(/obj/structure/table/glass, floor_at(1, 1))
	var/obj/structure/table/hardened = allocate(/obj/structure/table/glass, floor_at(2, 1))
	p2_table_reinforce_directly(hardened, get_material_by_name(MAT_STEEL))
	glass.take_damage(5, BRUTE, MELEE)
	hardened.take_damage(5, BRUTE, MELEE)
	var/glass_lost = glass.max_integrity - glass.get_integrity()
	var/hardened_lost = hardened.max_integrity - hardened.get_integrity()
	TEST_ASSERT(hardened_lost > 0, "the reinforced table took damage")
	TEST_ASSERT_EQUAL(glass_lost, hardened_lost * TABLE_BRITTLE_MATERIAL_MULTIPLIER, "the glass one took the multiplier more")

/// A mob that hits hard tears an unreinforced table apart; a weak one only scratches it.
/datum/unit_test/dq_p2_table/a_hard_hitting_mob_tears_a_table_apart

/datum/unit_test/dq_p2_table/a_hard_hitting_mob_tears_a_table_apart/run_gate()
	var/obj/structure/table/weak = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/obj/structure/table/strong = allocate(/obj/structure/table/steel, floor_at(2, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	p2_table_mob_attack(H, weak, 5)
	TEST_ASSERT(!QDELETED(weak), "a weak blow leaves it")
	p2_table_mob_attack(H, strong, 20)
	TEST_ASSERT(QDELETED(strong), "a hard one tears it apart")

// ---------------------------------------------------------------------------------------------------------------------
// Flipping
// ---------------------------------------------------------------------------------------------------------------------

/// The menu's Flip table flips an unflipped table away from the person.
/datum/unit_test/dq_p2_table/flip_turns_a_table_on_its_side

/datum/unit_test/dq_p2_table/flip_turns_a_table_on_its_side/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/before = T.get_integrity()
	TEST_ASSERT(p2_table_menu(H, T, "Flip table"), "the flip ran")
	TEST_ASSERT(p2_table_flipped(T), "flipped")
	TEST_ASSERT_EQUAL(T.dir, NORTH, "facing away from the person who flipped it")
	TEST_ASSERT(T.flags & ON_BORDER, "a flipped table is a border")
	TEST_ASSERT(T.get_integrity() < before, "the flip damaged it")
	TEST_ASSERT(!p2_table_menu_offers(H, T, "Flip table") || !p2_table_menu(H, T, "Flip table"), "it can't be flipped twice")

/// Put table back stands a flipped table up again.
/datum/unit_test/dq_p2_table/put_back_stands_it_up

/datum/unit_test/dq_p2_table/put_back_stands_it_up/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(H, T, "Flip table"), "flipped")
	TEST_ASSERT(p2_table_menu(H, T, "Put table back"), "put back")
	TEST_ASSERT(!p2_table_flipped(T), "upright")
	TEST_ASSERT(!(T.flags & ON_BORDER), "no longer a border")

/// An upright table has no Put table back, and a flipped one has no Flip table.
/datum/unit_test/dq_p2_table/each_menu_entry_answers_its_state

/datum/unit_test/dq_p2_table/each_menu_entry_answers_its_state/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(!p2_table_menu(H, T, "Put table back"), "nothing to put back")
	TEST_ASSERT(!p2_table_flipped(T), "still upright")
	TEST_ASSERT(p2_table_menu(H, T, "Flip table"), "flipped")
	TEST_ASSERT(!p2_table_menu(H, T, "Flip table"), "can't flip it twice")
	TEST_ASSERT(p2_table_flipped(T), "still flipped")

/// A table flips with the whole straight row beside it.
/datum/unit_test/dq_p2_table/a_row_flips_together

/datum/unit_test/dq_p2_table/a_row_flips_together/run_gate()
	var/obj/structure/table/left = allocate(/obj/structure/table/steel, floor_at(0, 1))
	var/obj/structure/table/middle = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/obj/structure/table/right = allocate(/obj/structure/table/steel, floor_at(2, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(H, middle, "Flip table"), "flipped the middle one")
	TEST_ASSERT(p2_table_flipped(left) && p2_table_flipped(middle) && p2_table_flipped(right), "the whole row went over")
	TEST_ASSERT_EQUAL(left.dir, middle.dir, "facing the same way")
	TEST_ASSERT_EQUAL(right.dir, middle.dir, "all of them")
	TEST_ASSERT(p2_table_menu(H, middle, "Put table back"), "put the middle one back")
	TEST_ASSERT(!p2_table_flipped(left) && !p2_table_flipped(middle) && !p2_table_flipped(right), "the row came back together")

/// Tables of a different material in the row stay where they are.
/datum/unit_test/dq_p2_table/a_row_of_another_material_stays

/datum/unit_test/dq_p2_table/a_row_of_another_material_stays/run_gate()
	var/obj/structure/table/steel = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/obj/structure/table/wood = allocate(/obj/structure/table/woodentable, floor_at(2, 1))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(H, steel, "Flip table"), "flipped")
	TEST_ASSERT(p2_table_flipped(steel), "the steel table flipped")
	TEST_ASSERT(!p2_table_flipped(wood), "the wooden one beside it did not")

/// A table with a table behind it (not in a straight row across) won't budge.
/datum/unit_test/dq_p2_table/a_table_in_an_l_shape_wont_flip

/datum/unit_test/dq_p2_table/a_table_in_an_l_shape_wont_flip/run_gate()
	var/obj/structure/table/corner = allocate(/obj/structure/table/steel, floor_at(1, 1))
	allocate(/obj/structure/table/steel, floor_at(2, 1))
	allocate(/obj/structure/table/steel, floor_at(1, 2))
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(!p2_table_menu(H, corner, "Flip table"), "it won't budge")
	TEST_ASSERT(!p2_table_flipped(corner), "still upright")

/// A rack, a pod table and the other fixed tables can't be flipped.
/datum/unit_test/dq_p2_table/fixed_tables_cannot_be_flipped

/datum/unit_test/dq_p2_table/fixed_tables_cannot_be_flipped/run_gate()
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	for(var/path in list(/obj/structure/table/rack/steel, /obj/structure/table/bench/steel, /obj/structure/table/survival_pod, /obj/structure/table/alien, /obj/structure/table/darkglass))
		var/obj/structure/table/T = allocate(path, floor_at(1, 1))
		TEST_ASSERT(!p2_table_menu(H, T, "Flip table"), "[path] did not flip")
		TEST_ASSERT(!p2_table_flipped(T), "[path] is still flat")
		qdel(T)

/// Somebody standing on a flipped table's tile does not stop it being put back: the old check looked for mobs with oview(src, 0), which never sees
/// the tile's own contents, so it never refused. Pinned as it is, not fixed.
/datum/unit_test/dq_p2_table/someone_on_the_tile_does_not_stop_the_put_back

/datum/unit_test/dq_p2_table/someone_on_the_tile_does_not_stop_the_put_back/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(H, T, "Flip table"), "flipped")
	var/mob/living/carbon/human/other = actor(at)
	TEST_ASSERT_EQUAL(other.loc, at, "somebody is standing on its tile")
	TEST_ASSERT(p2_table_menu(H, T, "Put table back"), "the menu offers the put back")
	TEST_ASSERT(!p2_table_flipped(T), "and it stood up")

/// A flipped table blocks what comes at it from the front and lets everything leave behind it; an upright one stops those who are not on a table.
/datum/unit_test/dq_p2_table/tables_block_movement_by_side

/datum/unit_test/dq_p2_table/tables_block_movement_by_side/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/walker = actor(floor_at(1, 2))
	TEST_ASSERT(!T.CanPass(walker, at), "an upright table stops a walker")
	var/obj/structure/table/other = allocate(/obj/structure/table/steel, floor_at(2, 2))
	var/mob/living/carbon/human/on_table = actor(floor_at(2, 2))
	TEST_ASSERT(T.CanPass(on_table, at), "somebody standing on a table steps across")
	qdel(on_table)
	qdel(other)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(H, T, "Flip table"), "flipped")
	TEST_ASSERT_EQUAL(T.dir, NORTH, "facing north")
	var/mob/living/carbon/human/from_front = actor(floor_at(1, 2))
	TEST_ASSERT(!T.CanPass(from_front, at), "coming at it from the front is stopped")
	var/mob/living/carbon/human/from_behind = actor(floor_at(1, 0))
	TEST_ASSERT(T.CanPass(from_behind, at), "coming from behind is fine")
	TEST_ASSERT(T.CanPass(from_front, floor_at(0, 2)), "a move that doesn't cross it is fine")
	TEST_ASSERT(!T.Uncross(from_behind, floor_at(1, 2)), "leaving it forward is stopped")
	TEST_ASSERT(T.Uncross(from_front, floor_at(1, 0)), "leaving backward is fine")

/// A bench lets everyone through.
/datum/unit_test/dq_p2_table/a_bench_is_passable

/datum/unit_test/dq_p2_table/a_bench_is_passable/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/bench/B = allocate(/obj/structure/table/bench/steel, at)
	var/mob/living/carbon/human/walker = actor(floor_at(1, 2))
	TEST_ASSERT(B.CanPass(walker, at), "a bench does not stop a walker")
	TEST_ASSERT(!B.density, "and is not dense")

// ---------------------------------------------------------------------------------------------------------------------
// Names, presets and the rack
// ---------------------------------------------------------------------------------------------------------------------

/// The presets come with their layers.
/datum/unit_test/dq_p2_table/presets_have_their_layers

/datum/unit_test/dq_p2_table/presets_have_their_layers/run_gate()
	var/obj/structure/table/steel = allocate(/obj/structure/table/steel, floor_at(0, 0))
	var/obj/structure/table/reinforced = allocate(/obj/structure/table/reinforced, floor_at(1, 0))
	var/obj/structure/table/gambling = allocate(/obj/structure/table/gamblingtable, floor_at(2, 0))
	var/obj/structure/table/bench = allocate(/obj/structure/table/bench/wooden, floor_at(3, 0))
	TEST_ASSERT_EQUAL(p2_table_stage(steel), "plated", "steel is plated")
	TEST_ASSERT_EQUAL(p2_table_material(steel), get_material_by_name(MAT_STEEL), "with steel")
	TEST_ASSERT_EQUAL(p2_table_stage(reinforced), "reinforced", "reinforced is reinforced")
	TEST_ASSERT_EQUAL(p2_table_reinforcement(reinforced), get_material_by_name(MAT_STEEL), "with steel")
	TEST_ASSERT(p2_table_carpeted(gambling), "a gambling table is carpeted")
	TEST_ASSERT_EQUAL(p2_table_material(bench), get_material_by_name(MAT_WOOD), "a wooden bench is wooden")
	TEST_ASSERT_EQUAL(reinforced.name, "reinforced [p2_material_name(DEFAULT_TABLE_MATERIAL)] table", "a reinforced table says so")

/// A rack takes things put on it, can't be plated, and a wrench takes it down to steel.
/datum/unit_test/dq_p2_table/a_rack_holds_things_and_comes_down_to_steel

/datum/unit_test/dq_p2_table/a_rack_holds_things_and_comes_down_to_steel/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/rack/R = allocate(/obj/structure/table/rack, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/pen = allocate(/obj/item/pen, H.loc)
	touch(H, R, pen)
	TEST_ASSERT_EQUAL(pen.loc, at, "the pen went on the rack")
	touch(H, R, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(R), "a wrench took the rack down")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 1, "to a sheet of steel")

/// A steel shelf's wrench takes its plating first (it is a plated rack), then it comes down.
/datum/unit_test/dq_p2_table/a_plated_rack_loses_its_plating_first

/datum/unit_test/dq_p2_table/a_plated_rack_loses_its_plating_first/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/rack/R = allocate(/obj/structure/table/rack/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT_NOTNULL(p2_table_material(R), "a steel rack is plated with steel")
	touch(H, R, tool(/obj/item/tool/wrench))
	TEST_ASSERT_NULL(p2_table_material(R), "the first wrench took the plating")
	TEST_ASSERT(!QDELETED(R), "the rack stands")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 1, "a sheet of steel lies there")
	touch(H, R, tool(/obj/item/tool/wrench))
	TEST_ASSERT(QDELETED(R), "the second took the rack down")
	TEST_ASSERT_EQUAL(sheet_total(at, /obj/item/stack/material/steel), 2, "a second sheet")

// ---------------------------------------------------------------------------------------------------------------------
// Grabs: putting a person on a table, and slamming one
// ---------------------------------------------------------------------------------------------------------------------

/// A firm grab clicked on a table puts the grabbed person on it and knocks them down.
/datum/unit_test/dq_p2_table/a_firm_grab_puts_a_person_on_the_table

/datum/unit_test/dq_p2_table/a_firm_grab_puts_a_person_on_the_table/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, floor_at(0, 0))
	var/obj/item/grab/G = grab(grabber, victim, GRAB_AGGRESSIVE)
	TEST_ASSERT(istype(G), "the grabber holds a grab")
	p2_table_click(grabber, T, G)
	settle()
	TEST_ASSERT_EQUAL(victim.loc, at, "the victim is on the table")
	TEST_ASSERT(victim.status_units(STAT_WEAKENED) > 0, "and knocked down")

/// A loose grab does not put anyone on a table: it needs a better grip.
/datum/unit_test/dq_p2_table/a_loose_grab_does_not_put_a_person_on_the_table

/datum/unit_test/dq_p2_table/a_loose_grab_does_not_put_a_person_on_the_table/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, floor_at(0, 0))
	var/obj/item/grab/G = grab(grabber, victim, GRAB_PASSIVE)
	TEST_ASSERT(istype(G), "the grabber holds a grab")
	p2_table_click(grabber, T, G)
	settle()
	TEST_ASSERT_EQUAL(victim.loc, floor_at(0, 0), "the victim stays where they were")

/// In combat mode a loose grab slams the victim's face into the table: they are hurt, and the table takes a knock.
/datum/unit_test/dq_p2_table/a_loose_grab_in_combat_mode_slams

/datum/unit_test/dq_p2_table/a_loose_grab_in_combat_mode_slams/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/grabber = actor(floor_at(1, 0))
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, floor_at(0, 0))
	var/obj/item/grab/G = grab(grabber, victim, GRAB_PASSIVE)
	TEST_ASSERT(istype(G), "the grabber holds a grab")
	grabber.combat_mode_key("on")
	var/hurt = victim.injury_load(INJURY_CATEGORY_PHYSICAL)
	var/intact = T.get_integrity()
	p2_table_click(grabber, T, G)
	settle()
	TEST_ASSERT(victim.injury_load(INJURY_CATEGORY_PHYSICAL) > hurt, "the victim was hurt")
	TEST_ASSERT(T.get_integrity() < intact, "the table took a knock")
	TEST_ASSERT_EQUAL(victim.loc, floor_at(0, 0), "the victim was not moved")

// ---------------------------------------------------------------------------------------------------------------------
// Climbing
// ---------------------------------------------------------------------------------------------------------------------

/// Climbing takes three and a half seconds and ends with the climber on the table's tile.
/datum/unit_test/dq_p2_table/climbing_takes_three_and_a_half_seconds

/datum/unit_test/dq_p2_table/climbing_takes_three_and_a_half_seconds/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	p2_table_climb(H, T)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "still at the foot of the table after three seconds")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(H.loc, at, "on the table after four")

/// A table that is shaken knocks its climbers off: they never arrive.
/datum/unit_test/dq_p2_table/flipping_a_table_shakes_off_its_climbers

/datum/unit_test/dq_p2_table/flipping_a_table_shakes_off_its_climbers/run_gate()
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, floor_at(1, 1))
	var/mob/living/carbon/human/climber = allocate(/mob/living/carbon/human, floor_at(0, 1)) // no godmode: it can be knocked down
	var/mob/living/carbon/human/flipper = actor(floor_at(1, 0))
	p2_table_climb(climber, T)
	test_time(1 SECOND)
	TEST_ASSERT(p2_table_menu(flipper, T, "Flip table"), "someone flipped it")
	TEST_ASSERT(climber.status_units(STAT_WEAKENED) > 0, "the climber was knocked down")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(climber.loc, floor_at(0, 1), "and never made it up")

/// A flipped table can be climbed onto from the side it faces away from.
/datum/unit_test/dq_p2_table/a_flipped_table_is_climbed

/datum/unit_test/dq_p2_table/a_flipped_table_is_climbed/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/flipper = actor(floor_at(1, 0))
	TEST_ASSERT(p2_table_menu(flipper, T, "Flip table"), "flipped")
	TEST_ASSERT_EQUAL(T.dir, NORTH, "facing north")
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	p2_table_climb(H, T)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "the climber is on the table's tile")

// ---------------------------------------------------------------------------------------------------------------------
// What the table looks like
// ---------------------------------------------------------------------------------------------------------------------

/// A table draws a layer per thing it is made of: the frame, the plating, the reinforcement, the carpet.
/datum/unit_test/dq_p2_table/the_look_follows_the_layers

/datum/unit_test/dq_p2_table/the_look_follows_the_layers/run_gate()
	var/obj/structure/table/frame = allocate(/obj/structure/table, floor_at(0, 0))
	var/obj/structure/table/plated = allocate(/obj/structure/table/steel, floor_at(1, 0))
	var/obj/structure/table/reinforced = allocate(/obj/structure/table/reinforced, floor_at(2, 0))
	var/obj/structure/table/gambling = allocate(/obj/structure/table/gamblingtable, floor_at(3, 0))
	var/frame_layers = p2_table_layers(frame)
	TEST_ASSERT(p2_table_layers(plated) > frame_layers, "plating adds a layer")
	TEST_ASSERT(p2_table_layers(reinforced) > p2_table_layers(plated), "reinforcement adds one")
	TEST_ASSERT(p2_table_layers(gambling) > p2_table_layers(plated), "carpet adds one")

/// A reinforced table says what it is reinforced with.
/datum/unit_test/dq_p2_table/the_description_names_the_reinforcement

/datum/unit_test/dq_p2_table/the_description_names_the_reinforcement/run_gate()
	var/obj/structure/table/reinforced = allocate(/obj/structure/table/reinforced, floor_at(1, 1))
	var/obj/structure/table/plain = allocate(/obj/structure/table/steel, floor_at(2, 1))
	TEST_ASSERT(findtext(reinforced.desc, p2_material_name(MAT_STEEL)), "it names the steel")
	TEST_ASSERT(!findtext(plain.desc, "reinforced"), "a plain one does not say reinforced")
	TEST_ASSERT_EQUAL(plain.name, "[p2_material_name(MAT_STEEL)] table", "named for its plating")

// ---------------------------------------------------------------------------------------------------------------------
// Combat mode
// ---------------------------------------------------------------------------------------------------------------------

/// In combat mode a weapon clicked on a table is still put on it: the placing is the click's use, and nothing else takes the click (pinned).
/datum/unit_test/dq_p2_table/a_weapon_in_combat_mode_is_put_on_the_table

/datum/unit_test/dq_p2_table/a_weapon_in_combat_mode_is_put_on_the_table/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	dq_give_zone_sel(H)
	H.combat_mode_key("on")
	var/obj/item/material/twohanded/fireaxe/axe = allocate(/obj/item/material/twohanded/fireaxe, H.loc)
	var/before = T.get_integrity()
	touch(H, T, axe)
	TEST_ASSERT_EQUAL(axe.loc, at, "the axe is on the table")
	TEST_ASSERT_EQUAL(T.get_integrity(), before, "the table was not hit")

/// Out of combat mode the same click puts the weapon on the table.
/datum/unit_test/dq_p2_table/a_weapon_out_of_combat_mode_is_put_on_the_table

/datum/unit_test/dq_p2_table/a_weapon_out_of_combat_mode_is_put_on_the_table/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/material/twohanded/fireaxe/axe = allocate(/obj/item/material/twohanded/fireaxe, H.loc)
	var/before = T.get_integrity()
	touch(H, T, axe)
	TEST_ASSERT_EQUAL(axe.loc, at, "the axe is on the table")
	TEST_ASSERT_EQUAL(T.get_integrity(), before, "the table was not hit")

/// A tool with no job on the table (a crowbar on an uncarpeted one) is put on it like any item. (The old tool handler swallowed the click and the tool
/// stayed in the hand: doc/rewrite/intended_changes.md.)
/datum/unit_test/dq_p2_table/a_crowbar_with_no_job_is_put_on_the_table

/datum/unit_test/dq_p2_table/a_crowbar_with_no_job_is_put_on_the_table/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	touch(H, T, bar)
	TEST_ASSERT_EQUAL(bar.loc, at, "the crowbar is on the table")
