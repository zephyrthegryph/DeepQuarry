// One input path (code/engine/kernel/entry.dm, code/engine/lifeforms/input.dm): the events BYOND's callbacks build resolve through the same code whether the inbox
// resolves them on the spot or they wait for phase K's drain. Each test sends the same input both ways and reads, from the handlers and the actor's hooks, what ran:
// a declared handler runs exactly once, as the sending actor, and what no handler takes goes on to the default handling exactly once.

/// The acting mob: records the default handling an input reached.
/mob/living/carbon/human/dq_one_path_actor
	var/list/path_seen

/mob/living/carbon/human/dq_one_path_actor/proc/path_note(what, atom/target, atom/extra = null)
	LAZYADD(path_seen, list(list(what, target, extra)))

/mob/living/carbon/human/dq_one_path_actor/op_compatibility_click(atom/target, params)
	path_note("default_click", target)

/mob/living/carbon/human/dq_one_path_actor/input_double_click(atom/target, params)
	path_note("default_double", target)

/mob/living/carbon/human/dq_one_path_actor/input_hover(atom/target, params)
	path_note("default_hover", target)

/mob/living/carbon/human/dq_one_path_actor/input_client_mouse(kind, atom/target, atom/over, params)
	path_note("default_[kind]", target, over)

/// Something the probe is dragged onto.
/obj/structure/dq_one_path_target
	name = "one path target"

/// A type that declares every input form, and records which handler ran and as whom.
/obj/structure/dq_one_path_probe
	name = "one path probe"
	var/list/path_seen

CAPABILITIES(/obj/structure/dq_one_path_probe)
	click_on(PROC_REF(probe_click))
	double_click_on(PROC_REF(probe_double))
	drag_onto(PROC_REF(probe_drag), onto = /obj/structure/dq_one_path_target)
	drag_over(PROC_REF(probe_drag_over))
	hover(PROC_REF(probe_hover))

/obj/structure/dq_one_path_probe/proc/path_note(what, mob/actor, atom/extra = null)
	LAZYADD(path_seen, list(list(what, actor, extra)))

/obj/structure/dq_one_path_probe/proc/probe_click(datum/act/input/A)
	path_note("click", A.actor)
	return TRUE

/obj/structure/dq_one_path_probe/proc/probe_double(datum/act/input/A)
	path_note("double", A.actor)
	return TRUE

/obj/structure/dq_one_path_probe/proc/probe_drag(datum/act/input/A)
	path_note("drag", A.actor, A.over)
	return TRUE

/obj/structure/dq_one_path_probe/proc/probe_drag_over(datum/act/input/A)
	path_note("drag_over", A.actor, A.over)
	return TRUE

/obj/structure/dq_one_path_probe/proc/probe_hover(datum/act/input/A)
	path_note(A.entered ? "hover_enter" : "hover_exit", A.actor)
	return TRUE

/// The same, with handlers that decline: the input goes on to the default handling.
/obj/structure/dq_one_path_probe/declining

CAPABILITIES(/obj/structure/dq_one_path_probe/declining)
	click_on(PROC_REF(declining_click))
	double_click_on(PROC_REF(declining_double))
	drag_onto(PROC_REF(declining_drag), onto = /obj/structure/dq_one_path_target)

/obj/structure/dq_one_path_probe/declining/proc/declining_click(datum/act/input/A)
	path_note("click", A.actor)
	return INPUT_FALLTHROUGH

/obj/structure/dq_one_path_probe/declining/proc/declining_double(datum/act/input/A)
	path_note("double", A.actor)
	return INPUT_FALLTHROUGH

/obj/structure/dq_one_path_probe/declining/proc/declining_drag(datum/act/input/A)
	path_note("drag", A.actor, A.over)
	return INPUT_FALLTHROUGH

/// A type with no declared input at all.
/obj/structure/dq_one_path_plain
	name = "one path plain"

/datum/unit_test/dq_input_one_path
	abstract_type = /datum/unit_test/dq_input_one_path

/// Rows of `seen` with this first element.
/datum/unit_test/dq_input_one_path/proc/path_rows(list/seen, what)
	. = list()
	for(var/list/row as anything in seen)
		if(row[1] == what)
			. += list(row)

/// Hands `E` to the inbox: on the spot (`queued` FALSE), or waiting for the drain (the test checks it waited, then phase K serves it).
/datum/unit_test/dq_input_one_path/proc/path_send(mob/actor, datum/input_event/E, queued)
	input_force_room(!queued)
	input_submit(E)
	if(!queued)
		return
	TEST_ASSERT_EQUAL(length(SSinput.waiting(actor.client || actor)), 1, "the input waits in the inbox")
	test_phase(KERNEL_PHASE_K)
	TEST_ASSERT_EQUAL(length(SSinput.waiting(actor.client || actor)), 0, "the drain served it")

/// A declared handler takes each input once, as the sender, and nothing reaches the default handling.
/datum/unit_test/dq_input_one_path/declared

/datum/unit_test/dq_input_one_path/declared/Run()
	test_driver_begin()
	for(var/queued in list(FALSE, TRUE))
		var/mode = queued ? "queued" : "on the spot"
		var/turf/T = dq_containment_floor()
		var/mob/living/carbon/human/dq_one_path_actor/user = allocate(/mob/living/carbon/human/dq_one_path_actor, T)
		var/mob/living/carbon/human/dq_one_path_actor/other = allocate(/mob/living/carbon/human/dq_one_path_actor, T)
		var/obj/structure/dq_one_path_probe/probe = allocate(/obj/structure/dq_one_path_probe, T)
		var/obj/structure/dq_one_path_target/target = allocate(/obj/structure/dq_one_path_target, T)

		path_send(user, new /datum/input_event/click(user, probe, T, "mapwindow.map", "left=1"), queued)
		var/list/rows = path_rows(probe.path_seen, "click")
		TEST_ASSERT_EQUAL(length(rows), 1, "a click runs click_on() exactly once ([mode])")
		TEST_ASSERT_EQUAL(rows[1][2], user, "as the mob that clicked ([mode])")
		TEST_ASSERT_NULL(user.path_seen, "and the default click handling does not run after it ([mode])")

		path_send(user, new /datum/input_event/click/double(user, probe, T, "mapwindow.map", "left=1"), queued)
		rows = path_rows(probe.path_seen, "double")
		TEST_ASSERT_EQUAL(length(rows), 1, "a double click runs double_click_on() exactly once ([mode])")
		TEST_ASSERT_EQUAL(rows[1][2], user, "as the mob that clicked ([mode])")
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_double")), 0, "and the default double click does not run ([mode])")

		path_send(user, new /datum/input_event/drag(user, probe, target, list(T, T, "mapwindow.map", "mapwindow.map", "left=1"), TRUE), queued)
		rows = path_rows(probe.path_seen, "drag")
		TEST_ASSERT_EQUAL(length(rows), 1, "a drop runs drag_onto() exactly once ([mode])")
		TEST_ASSERT_EQUAL(rows[1][2], user, "as the mob that dragged ([mode])")
		TEST_ASSERT_EQUAL(rows[1][3], target, "with what it was dropped on ([mode])")

		path_send(user, new /datum/input_event/click/client_mouse(user, INPUT_MOUSE_DRAG, probe, target, T, "mapwindow.map", "left=1"), queued)
		rows = path_rows(probe.path_seen, "drag_over")
		TEST_ASSERT_EQUAL(length(rows), 1, "a drag runs drag_over() exactly once ([mode])")
		TEST_ASSERT_EQUAL(rows[1][2], user, "as the mob that dragged ([mode])")
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_[INPUT_MOUSE_DRAG]")), 1, "and goes on to the mob's own drag hook once ([mode])")

		path_send(user, new /datum/input_event/click/hover(user, probe, T, "mapwindow.map", "", TRUE), queued)
		rows = path_rows(probe.path_seen, "hover_enter")
		TEST_ASSERT_EQUAL(length(rows), 1, "entering runs hover() exactly once ([mode])")
		TEST_ASSERT_EQUAL(rows[1][2], user, "as the mob whose mouse entered ([mode])")
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_hover")), 1, "and the mob's hover tracking follows it once ([mode])")
		path_send(user, new /datum/input_event/click/hover(user, probe, T, "mapwindow.map", "", FALSE), queued)
		rows = path_rows(probe.path_seen, "hover_exit")
		TEST_ASSERT_EQUAL(length(rows), 1, "leaving runs hover() exactly once ([mode])")
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_hover")), 1, "and is not a hover for the mob's tracking ([mode])")

		TEST_ASSERT_NULL(other.path_seen, "no other mob was involved ([mode])")
	input_force_room(null)
	test_driver_end()

/// A handler that declines, and a type with none: the input takes the default handling, once, for the same actor.
/datum/unit_test/dq_input_one_path/default

/datum/unit_test/dq_input_one_path/default/Run()
	test_driver_begin()
	for(var/queued in list(FALSE, TRUE))
		var/mode = queued ? "queued" : "on the spot"
		var/turf/T = dq_containment_floor()
		var/mob/living/carbon/human/dq_one_path_actor/user = allocate(/mob/living/carbon/human/dq_one_path_actor, T)
		var/obj/structure/dq_one_path_probe/declining/declining = allocate(/obj/structure/dq_one_path_probe/declining, T)
		var/obj/structure/dq_one_path_plain/plain = allocate(/obj/structure/dq_one_path_plain, T)

		path_send(user, new /datum/input_event/click(user, declining, T, "mapwindow.map", "left=1"), queued)
		TEST_ASSERT_EQUAL(length(path_rows(declining.path_seen, "click")), 1, "a declining click_on() runs once ([mode])")
		var/list/rows = path_rows(user.path_seen, "default_click")
		TEST_ASSERT_EQUAL(length(rows), 1, "and the click goes on to the default handling once ([mode])")
		TEST_ASSERT_EQUAL(rows[1][2], declining, "on the same target ([mode])")

		path_send(user, new /datum/input_event/click/double(user, declining, T, "mapwindow.map", "left=1"), queued)
		TEST_ASSERT_EQUAL(length(path_rows(declining.path_seen, "double")), 1, "a declining double_click_on() runs once ([mode])")
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_double")), 1, "and the double click goes on to the default handling once ([mode])")

		path_send(user, new /datum/input_event/click(user, plain, T, "mapwindow.map", "left=1"), queued)
		rows = path_rows(user.path_seen, "default_click")
		TEST_ASSERT_EQUAL(length(rows), 2, "a click on a type that declares nothing is the default handling, once ([mode])")
		TEST_ASSERT_EQUAL(rows[2][2], plain, "on that target ([mode])")

		path_send(user, new /datum/input_event/click/double(user, plain, T, "mapwindow.map", "left=1"), queued)
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_double")), 2, "and so is a double click ([mode])")

		path_send(user, new /datum/input_event/click/hover(user, plain, T, "mapwindow.map", "", TRUE), queued)
		TEST_ASSERT_EQUAL(length(path_rows(user.path_seen, "default_hover")), 1, "and a hover ([mode])")
	input_force_room(null)
	test_driver_end()

/datum/unit_test/dq_input_one_path/converted

/// Types that overrode a native mouse proc by hand, driven through the inbox both ways: a build-mode button turns its direction once per click, a radial
/// menu's centre lights up while hovered, an ability dropped on another swaps places once.
/datum/unit_test/dq_input_one_path/converted/Run()
	test_driver_begin()
	for(var/queued in list(FALSE, TRUE))
		var/mode = queued ? "queued" : "on the spot"
		var/turf/T = dq_containment_floor()
		var/mob/living/carbon/human/dq_one_path_actor/user = allocate(/mob/living/carbon/human/dq_one_path_actor, T)

		var/obj/effect/bmode/builddir/button = allocate(/obj/effect/bmode/builddir, T)
		button.set_dir(NORTH)
		path_send(user, new /datum/input_event/click(user, button, T, "mapwindow.map", "left=1"), queued)
		TEST_ASSERT_EQUAL(button.dir, EAST, "a click on the build direction button turns it once ([mode])")
		TEST_ASSERT_NULL(user.path_seen, "and takes no default click handling ([mode])")

		var/atom/movable/screen/radial/center/center = allocate(/atom/movable/screen/radial/center)
		path_send(user, new /datum/input_event/click/hover(user, center, T, "mapwindow.map", "", TRUE), queued)
		TEST_ASSERT_EQUAL(center.icon_state, "radial_center_focus", "entering the radial centre lights it up ([mode])")
		path_send(user, new /datum/input_event/click/hover(user, center, T, "mapwindow.map", "", FALSE), queued)
		TEST_ASSERT_EQUAL(center.icon_state, "radial_center", "leaving it puts it out ([mode])")

		var/atom/movable/screen/movable/ability_master/master = allocate(/atom/movable/screen/movable/ability_master, user)
		master.add_ability("one_path_a")
		master.add_ability("one_path_b")
		var/atom/movable/screen/ability/first = master.ability_objects[1]
		var/atom/movable/screen/ability/second = master.ability_objects[2]
		path_send(user, new /datum/input_event/drag(user, first, second, list(null, null, "mapwindow.map", "mapwindow.map", "left=1"), TRUE), queued)
		TEST_ASSERT_EQUAL(master.ability_objects[1], second, "an ability dropped on another swaps their places once ([mode])")
		TEST_ASSERT_EQUAL(master.ability_objects[2], first, "and not back again ([mode])")
	input_force_room(null)
	test_driver_end()
