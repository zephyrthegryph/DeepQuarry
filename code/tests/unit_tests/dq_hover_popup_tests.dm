// The hover popup's ordering (code/engine/kernel/inbox.dm, code/content/tooltip/tooltip.dm): a close is never lost to lateness or shedding, an exit that
// beats a waiting show leaves it hidden, and an exit replaces the enter still queued behind it.

/datum/unit_test/dq_hover_popup
/// An event built as the client's own and stamped as arrived now.
/datum/unit_test/dq_hover_popup/proc/hover_event(mob/user, atom/over, entering)
	var/datum/input_event/click/hover/E = new(user, over, null, null, "", entering)
	E.arrived_clock = op_now()
	return E

/datum/unit_test/dq_hover_popup/exit_never_expires/Run()
	test_driver_begin()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_input_probe/P = allocate(/obj/item/dq_input_probe, T)
	var/datum/input_event/click/hover/enter = hover_event(user, P, TRUE)
	var/datum/input_event/click/hover/leave = hover_event(user, P, FALSE)
	var/datum/input_event/click/pressed/press = new(user, P, null, null, "")
	press.arrived_clock = op_now()
	test_time(5 SECONDS)
	TEST_ASSERT(enter.expired(), "an enter that waited past its limit is too late")
	TEST_ASSERT(!leave.expired(), "an exit is run however late it is")
	TEST_ASSERT(!press.expired(), "a press that closes the popup is run however late it is")
	TEST_ASSERT(enter.sheddable(), "a full inbox may shed an enter")
	TEST_ASSERT(!leave.sheddable(), "a full inbox never sheds an exit")
	test_driver_end()

/// An exit queued behind a backlog that grew old still runs; the enter it replaced does not.
/datum/unit_test/dq_hover_popup/late_exit_runs/Run()
	test_driver_begin()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_input_probe/P = allocate(/obj/item/dq_input_probe, T)
	input_force_room(FALSE)
	with_actor(user, P, "MouseEntered", T, null, "")
	with_actor(user, P, "MouseExited", T, null, "")
	for(var/source in SSinput.inboxes)
		for(var/datum/input_event/E as anything in SSinput.inboxes[source])
			E.arrived_clock -= 5 SECONDS
	SSinput.drain_step(1, TRUE)
	input_force_room(null)
	TEST_ASSERT_EQUAL(jointext(P.hovers, ","), "0", "the exit replaced the enter still queued and ran though it waited long: the popup is closed, never opened")
	test_driver_end()

/// An exit between an enter and the show that waited for it makes that show stale.
/datum/unit_test/dq_hover_popup/exit_beats_show/Run()
	var/datum/tooltip/T = new /datum/tooltip(null)
	own(T)
	var/seen = T.epoch
	TEST_ASSERT(!tooltip_show_stale(T, seen), "a show whose mouse is still on the target is current")
	TEST_ASSERT(!tooltip_show_stale(T, null), "a show that did not wait is never stale")
	T.hide()
	TEST_ASSERT(tooltip_show_stale(T, seen), "an exit that arrives before the waiting show leaves it hidden")
	T.hide()
	TEST_ASSERT(tooltip_show_stale(T, seen), "a second close does not revive it")
	TEST_ASSERT(!tooltip_show_stale(T, T.epoch), "a later hover starts from the new count")
