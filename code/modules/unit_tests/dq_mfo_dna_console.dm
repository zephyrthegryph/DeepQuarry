// Behaviour pins for rewrite/missing-forms: the DNA modifier console's window. Its buttons (the old UI_ACT rows) and its two modals (the buffer
// label and the block injector's block) are driven the way the client drives them: a button through the window (hc_ui), a modal's answer
// through act_modal_answer(). Written against DECLARE_UI/UI_ACT and tgui_modal_input/tgui_modal_choice, and pinned green on them before the
// window moved onto interface(), ops and asks().

/datum/unit_test/dq_mfo_dna
	abstract_type = /datum/unit_test/dq_mfo_dna
	var/obj/machinery/dna_scannernew/scanner
	var/obj/machinery/computer/scan_consolenew/console
	var/mob/living/carbon/human/user

/datum/unit_test/dq_mfo_dna/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	scanner = allocate(/obj/machinery/dna_scannernew, T)
	console = allocate(/obj/machinery/computer/scan_consolenew, get_step(T, EAST))
	user = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	user.enable_godmode()
	run_dna()
	test_driver_end()
	for(var/turf/F in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		for(var/obj/item/I in F.contents.Copy())
			qdel(I)

/datum/unit_test/dq_mfo_dna/proc/run_dna()
	return

/datum/unit_test/dq_mfo_dna/proc/press(action, list/args)
	hc_ui(user, console, action, args || list())
	test_time(1)

/datum/unit_test/dq_mfo_dna/proc/answer(id, value, list/arguments)
	console.act_modal_answer(user, id, value, arguments || list())
	test_time(1)

/datum/unit_test/dq_mfo_dna/proc/injectors_here()
	. = list()
	for(var/obj/item/dnainjector/I in console.loc)
		. += I

/datum/unit_test/dq_mfo_dna/connected

/datum/unit_test/dq_mfo_dna/connected/run_dna()
	TEST_ASSERT_EQUAL(console.connected(), scanner, "the console finds the scanner beside it")

/// The page tabs and the emitter's two settings.
/datum/unit_test/dq_mfo_dna/buttons_set_the_console

/datum/unit_test/dq_mfo_dna/buttons_set_the_console/run_dna()
	press("selectMenuKey", list("key" = "buffer"))
	TEST_ASSERT_EQUAL(console.selected_menu_key, "buffer", "the buffer page")
	press("selectMenuKey", list("key" = "nonsense"))
	TEST_ASSERT_EQUAL(console.selected_menu_key, "buffer", "an unknown page is ignored")
	press("radiationDuration", list("value" = 7))
	TEST_ASSERT_EQUAL(console.radiation_duration, 7, "the duration")
	press("radiationIntensity", list("value" = 4))
	TEST_ASSERT_EQUAL(console.radiation_intensity, 4, "the intensity")
	press("selectSEBlock", list("block" = 3, "subblock" = 2))
	TEST_ASSERT_EQUAL(console.selected_se_block, 3, "the SE block")
	TEST_ASSERT_EQUAL(console.selected_se_subblock, 2, "and sub-block")

/// The label modal names a buffer; clearing the buffer forgets it.
/datum/unit_test/dq_mfo_dna/buffer_label_and_clear

/datum/unit_test/dq_mfo_dna/buffer_label_and_clear/run_dna()
	press("bufferOption", list("option" = "changeLabel", "id" = 2, "block" = 0))
	var/list/modal = tgui_modal_data(console)
	TEST_ASSERT_NOTNULL(modal, "the label question is the window's modal")
	answer("changeBufferLabel", "Alpha", list("id" = 2))
	var/datum/transhuman/body_record/buf = console.buffers[2]
	TEST_ASSERT_EQUAL(buf.mydna.name, "Alpha", "the buffer takes the label")
	TEST_ASSERT_NULL(tgui_modal_data(console), "and the modal closed")
	press("bufferOption", list("option" = "clear", "id" = 2, "block" = 0))
	buf = console.buffers[2]
	TEST_ASSERT_EQUAL(buf.mydna.name, "Empty", "a cleared buffer is empty")

/// An injector of the whole buffer is made at once; a block injector asks for its block first. Either starts the console's cooldown.
/datum/unit_test/dq_mfo_dna/injectors

/datum/unit_test/dq_mfo_dna/injectors/run_dna()
	console.injector_ready = FALSE
	press("bufferOption", list("option" = "createInjector", "id" = 1, "block" = 0))
	TEST_ASSERT_EQUAL(length(injectors_here()), 0, "not ready: nothing is made")
	console.injector_ready = TRUE
	press("bufferOption", list("option" = "createInjector", "id" = 1, "block" = 0))
	TEST_ASSERT_EQUAL(length(injectors_here()), 1, "a whole-buffer injector")
	TEST_ASSERT(!console.injector_ready, "the console cools down")
	test_time(6 SECONDS)
	TEST_ASSERT(console.injector_ready, "and is ready five seconds on")
	press("bufferOption", list("option" = "createInjector", "id" = 1, "block" = 1))
	var/list/modal = tgui_modal_data(console)
	TEST_ASSERT_NOTNULL(modal, "a block injector asks for its block")
	TEST_ASSERT_EQUAL(length(injectors_here()), 1, "nothing made yet")
	var/list/choices = modal["choices"]
	TEST_ASSERT(length(choices) >= 3, "the blocks are offered")
	answer("createInjectorBlock", choices[3], list("id" = 1))
	var/list/made = injectors_here()
	TEST_ASSERT_EQUAL(length(made), 2, "the block injector is made on the answer")
	var/obj/item/dnainjector/block_one
	for(var/obj/item/dnainjector/I in made)
		if(I.block)
			block_one = I
	TEST_ASSERT_NOTNULL(block_one, "with a block")
	TEST_ASSERT_EQUAL(block_one?.block, 3, "the block answered")

/// A disk goes in by hand and comes out by the button.
/datum/unit_test/dq_mfo_dna/disk_in_and_out

/datum/unit_test/dq_mfo_dna/disk_in_and_out/run_dna()
	var/obj/item/disk/body_record/D = allocate(/obj/item/disk/body_record, user.loc)
	user.put_in_active_hand(D)
	test_click(user, console, D)
	test_time(1)
	TEST_ASSERT_EQUAL(console.disk, D, "the disk is in")
	press("ejectDisk")
	TEST_ASSERT_NULL(console.disk, "ejected")
	TEST_ASSERT_EQUAL(D.loc, console.loc, "onto the console's tile")
