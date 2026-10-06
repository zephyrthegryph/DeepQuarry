// Input with an actor (code/engine/lifeforms/input.dm): click_on(), drag_onto(), hover(), tooltip() and with_actor(). The native overrides
// are generated (analyze gen declare); the test drives them through with_actor(), as a client's input would arrive with its usr.

/obj/item/dq_input_probe
	name = "input probe"
	var/mob/clicked_by = null
	var/atom/dropped_on = null
	var/mob/dragged_by = null
	var/list/hovers = null
	var/mob/tip_for = null
	var/pokes = 0

CAPABILITIES(/obj/item/dq_input_probe)
	click_on(PROC_REF(clicked))
	drag_onto(PROC_REF(dragged), onto = /obj/structure)
	hover(PROC_REF(hovered))
	tooltip(PROC_REF(tip))
	op("poke", hand(), label("Poke"), then(PROC_REF(poked)))

/obj/item/dq_input_probe/proc/clicked(datum/act/input/A)
	clicked_by = A.actor

/obj/item/dq_input_probe/proc/dragged(datum/act/input/A)
	dropped_on = A.over
	dragged_by = A.actor

/obj/item/dq_input_probe/proc/hovered(datum/act/input/A)
	LAZYADD(hovers, A.entered)

/obj/item/dq_input_probe/proc/tip(mob/user)
	tip_for = user
	return list("Probe", "a probe")

/obj/item/dq_input_probe/proc/poked(datum/act/op/A)
	pokes++

/// A click bound to an op key: the click performs the op with the clicking mob as its actor.
/obj/item/dq_input_probe/op_bound

CAPABILITIES(/obj/item/dq_input_probe/op_bound)
	click_on("poke")

/obj/structure/dq_input_target
	name = "input target"

/datum/unit_test/dq_lifeform_input

/datum/unit_test/dq_lifeform_input/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_input_probe/P = allocate(/obj/item/dq_input_probe, T)
	var/obj/structure/dq_input_target/target = allocate(/obj/structure/dq_input_target, T)

	with_actor(user, P, "Click", T, null, "")
	TEST_ASSERT_EQUAL(P.clicked_by, user, "click_on() hands the handler the clicking mob")
	with_actor(user, P, "MouseDrop", target, T, T, null, null, "")
	TEST_ASSERT_EQUAL(P.dropped_on, target, "drag_onto() hands the handler the drop target")
	TEST_ASSERT_EQUAL(P.dragged_by, user, "and the dragging mob")
	with_actor(user, P, "MouseEntered", T, null, "")
	with_actor(user, P, "MouseExited", T, null, "")
	TEST_ASSERT_EQUAL(jointext(P.hovers, ","), "1,0", "hover() runs on enter and on exit")
	TEST_ASSERT_EQUAL(P.tip_for, user, "tooltip() asks its proc for the hovering mob")
	TEST_ASSERT_NULL(usr, "with_actor() restores the acting mob")

	var/obj/item/dq_input_probe/op_bound/B = allocate(/obj/item/dq_input_probe/op_bound, T)
	with_actor(user, B, "Click", T, null, "")
	TEST_ASSERT_EQUAL(B.pokes, 1, "a click bound to an op key performs the op")
