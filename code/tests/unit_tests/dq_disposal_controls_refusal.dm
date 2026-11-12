/// The disposal bin's window buttons refuse through requirements (no message printed by the handler): from inside the bin nothing works,
/// with the power switched off only eject works, and an ordinary press from outside goes through.
/datum/unit_test/dq_disposal_controls_refusal

/datum/unit_test/dq_disposal_controls_refusal/Run()
	test_driver_begin()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/machinery/disposal/bin = allocate(/obj/machinery/disposal, surface)
	var/datum/tgui/window = allocate(/datum/tgui, user, bin, "DisposalBin")
	bin.set_mode(0) // DISPOSALMODE_OFF
	input_submit(new /datum/input_event/ui_act(user, window, "pumpOn", list(), window.state()))
	TEST_ASSERT_EQUAL(bin.mode, 1, "An ordinary pumpOn press from outside switches the pump on")
	bin.set_mode(-1) // DISPOSALMODE_EJECTONLY
	input_submit(new /datum/input_event/ui_act(user, window, "pumpOn", list(), window.state()))
	TEST_ASSERT_EQUAL(bin.mode, -1, "With the power switched off the pump button is refused")
	TEST_ASSERT(!isnull(bin.controls_power_refusal(new /datum/act/op)), "The power refusal is a reason, not a print")
	bin.set_mode(0)
	user.forceMove(bin)
	var/datum/act/op/probe = new
	probe.actor = user
	TEST_ASSERT(!isnull(bin.controls_reach_refusal(probe)), "From inside the bin the controls are refused")
	input_submit(new /datum/input_event/ui_act(user, window, "pumpOn", list(), window.state()))
	TEST_ASSERT_EQUAL(bin.mode, 0, "A press from inside the bin changes nothing")
	user.forceMove(surface)
	test_driver_end()
