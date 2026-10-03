/// A real unopened atmos console must create and subvert its actual lazily-owned controller through its declared emag, spend one card use, and preserve that controller on repeat refusal.
/datum/unit_test/interim_atmos_console_unopened_emag/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/atmoscontrol/console = allocate(/obj/machinery/computer/atmoscontrol, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	card.uses = 3
	TEST_ASSERT(user.put_in_active_hand(card), "the actual actor holds its real charged emag")
	TEST_ASSERT_NULL(console.atmos_control, "the actual unopened console has not created its lazy controller")
	TEST_ASSERT(!console.emagged, "the actual unopened console starts unsubverted")
	var/list/access_before = console.req_access
	var/datum/interaction/emag_entry = emag_interaction_for(console)
	TEST_ASSERT_NOTNULL(emag_entry, "the actual console exposes its declared emag interaction")
	TEST_ASSERT(emag_entry.perform(user, console, card), "the actual declared interaction subverts the unopened console")
	TEST_ASSERT_EQUAL(card.uses, 2, "the actual first accepted emag spends exactly one card use")
	var/datum/tgui_module/atmos_control/controller = console.atmos_control
	TEST_ASSERT_NOTNULL(controller, "the actual first emag creates the real owned atmosphere controller without opening a client window")
	TEST_ASSERT(controller.emagged && console.emagged, "actual accepted emag subverts both the console and its controller")
	TEST_ASSERT_EQUAL(controller.access.req_access, access_before, "actual subversion preserves the original controller access configuration")
	TEST_ASSERT_EQUAL(console.ui_redirect(user), controller, "subsequent actual interface routing reuses the same subverted controller")
	emag_entry.perform(user, console, card)
	TEST_ASSERT_EQUAL(card.uses, 2, "the actual repeated declared emag spends no extra card use")
	TEST_ASSERT_EQUAL(console.atmos_control, controller, "repeat refusal preserves the original owned controller")
	TEST_ASSERT(controller.emagged && console.emagged, "repeat refusal preserves the actual bypass state")
	TEST_ASSERT_EQUAL(user.get_active_hand(), card, "the actual accepted and refused interactions retain the actor's card")
