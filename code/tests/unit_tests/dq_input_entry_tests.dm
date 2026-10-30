// BYOND's native input callbacks (code/engine/kernel/entry.dm): each reads the acting mob once, builds a typed /datum/input_event that carries it,
// and hands it to input_submit(); the hooks take the actor as src. The test drives the callbacks through with_actor(), as a client's input would
// arrive with its usr, and reads the actor back from what the hooks recorded.

/// A mob that records which hooks the inbox called on it, and with what.
/mob/living/carbon/human/dq_entry_probe
	var/list/entry_seen

/mob/living/carbon/human/dq_entry_probe/proc/entry_note(what, atom/target, extra = null)
	LAZYADD(entry_seen, list(list(what, target, extra)))

/mob/living/carbon/human/dq_entry_probe/input_double_click(atom/target, params)
	entry_note("double", target, params)

/mob/living/carbon/human/dq_entry_probe/input_wheel(atom/target, delta_x, delta_y, params)
	entry_note("wheel", target, "[delta_x],[delta_y]")

/mob/living/carbon/human/dq_entry_probe/input_hover(atom/target, params)
	entry_note("hover", target, params)

/mob/living/carbon/human/dq_entry_probe/input_pressed(atom/target, params)
	entry_note("pressed", target, params)

/mob/living/carbon/human/dq_entry_probe/input_client_mouse(kind, atom/target, atom/over, params)
	entry_note(kind, target, over)

/// Dragged onto something, it records what it was dropped on and by whom.
/obj/structure/dq_entry_target
	name = "entry target"
	var/atom/dropped = null
	var/mob/dropped_by = null

CAPABILITIES(/obj/structure/dq_entry_target)
	drag_onto(PROC_REF(entry_dropped))

/obj/structure/dq_entry_target/proc/entry_dropped(datum/act/input/A)
	dropped = A.over
	dropped_by = A.actor
	return TRUE

/datum/unit_test/proc/dq_entry_noted(mob/living/carbon/human/dq_entry_probe/user, what)
	for(var/list/row as anything in user.entry_seen)
		if(row[1] == what)
			return row
	return null

/datum/unit_test/dq_input_entry_actor

/datum/unit_test/dq_input_entry_actor/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/dq_entry_probe/user = allocate(/mob/living/carbon/human/dq_entry_probe, T)
	var/mob/living/carbon/human/dq_entry_probe/other = allocate(/mob/living/carbon/human/dq_entry_probe, T)
	var/obj/item/dq_input_probe/hovering = allocate(/obj/item/dq_input_probe, T)
	var/obj/structure/dq_input_target/plain = allocate(/obj/structure/dq_input_target, T)
	test_driver_begin()
	input_force_room(TRUE)

	with_actor(user, plain, "DblClick", T, null, "left=1")
	var/list/row = dq_entry_noted(user, "double")
	TEST_ASSERT(row, "a double click reaches the hook of the mob that sent it")
	TEST_ASSERT_EQUAL(row[2], plain, "with the atom it was on")
	TEST_ASSERT_NULL(other.entry_seen, "and no other mob's")

	with_actor(user, plain, "MouseWheel", 1, -2, T, null, "")
	row = dq_entry_noted(user, "wheel")
	TEST_ASSERT(row, "the wheel reaches the sender's hook")
	TEST_ASSERT_EQUAL(row[3], "1,-2", "with its deltas")

	with_actor(user, plain, "MouseEntered", T, null, "")
	TEST_ASSERT(dq_entry_noted(user, "hover"), "a hover reaches the sender's hook")

	with_actor(user, plain, "MouseDown", T, null, "")
	TEST_ASSERT_NULL(dq_entry_noted(user, "pressed"), "a press on an atom with no tooltip queues nothing")
	with_actor(user, hovering, "MouseDown", T, null, "")
	row = dq_entry_noted(user, "pressed")
	TEST_ASSERT(row, "a press on an atom that declares a tooltip reaches the sender's hook")
	TEST_ASSERT_EQUAL(row[2], hovering, "with that atom")

	// The client's own procs act as the client's mob: the same inbox, the same actor on the event.
	input_submit(new /datum/input_event/click/client_mouse(other, INPUT_MOUSE_DOWN, plain, null, T, null, ""))
	input_submit(new /datum/input_event/click/client_mouse(other, INPUT_MOUSE_DRAG, plain, hovering, T, null, ""))
	input_submit(new /datum/input_event/click/client_mouse(other, INPUT_MOUSE_UP, plain, null, T, null, ""))
	TEST_ASSERT_EQUAL(length(other.entry_seen), 3, "a press, a drag and a release all reach the client mob's hook")
	row = dq_entry_noted(other, INPUT_MOUSE_DRAG)
	TEST_ASSERT_EQUAL(row[3], hovering, "a drag names what the pointer is over")
	TEST_ASSERT_NULL(dq_entry_noted(user, INPUT_MOUSE_DOWN), "and none of it reached the other mob")

	// The inbox keeps only the latest hover of a lane and every wheel notch.
	input_force_room(FALSE)
	input_submit(new /datum/input_event/click/hover(user, plain, T, null, "a"))
	input_submit(new /datum/input_event/click/hover(user, plain, T, null, "b"))
	input_submit(new /datum/input_event/click/wheel(user, plain, T, null, "", 0, 1))
	input_submit(new /datum/input_event/click/wheel(user, plain, T, null, "", 0, 1))
	TEST_ASSERT_EQUAL(length(SSinput.waiting(user.client || user)), 3, "a repeated hover coalesces, wheel notches do not")
	test_driver_end()

/datum/unit_test/dq_input_entry_drop

/datum/unit_test/dq_input_entry_drop/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/dq_input_target/target = allocate(/obj/structure/dq_input_target, T)
	var/obj/structure/dq_entry_target/dragged = allocate(/obj/structure/dq_entry_target, T)
	test_driver_begin()
	input_force_room(TRUE)

	with_actor(user, dragged, "MouseDrop", target, T, T, null, null, "")
	TEST_ASSERT_EQUAL(dragged.dropped, target, "a drop resolves through the inbox to the dragged type's drag_onto() entry, with what it was dropped on")
	TEST_ASSERT_EQUAL(dragged.dropped_by, user, "as the mob that dragged")
	test_driver_end()
