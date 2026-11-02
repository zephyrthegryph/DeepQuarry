// Window-data pin drivers for the other window hosts (dq_ui_pins.dm): the agent card, the appearance changer, the vore panel and the
// private / OOC notes panels. No client exists in a unit test, so a handler that asks a question is driven by opening it (the real
// ui_act_* proc) and answering the open request directly; a handler that reaches a client (preferences) has its state change made by hand,
// as its answer would, and says so in a comment.

/// A bare op context of `actor`, as the op engine hands a handler.
/datum/ui_pin/proc/op_ctx(mob/actor)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = actor
	return A

/// Presses a window button of the host as the user, through a live window as a player's would be (a test person has no client, so its state is always-interactive).
/datum/ui_pin
	/// Real deciseconds to wait after a press.
	var/press_gap = 0

/datum/ui_pin/proc/press(action, list/args)
	var/datum/tgui/ui = SStgui.get_open_ui(user, host)
	if(!ui)
		ui = new(user, host, "HcTest")
		ui.status = STATUS_INTERACTIVE
		ui.set_state(GLOB.tgui_always_state)
		SStgui.on_open(ui)
		test.own(ui)
		test_time(10 SECONDS) // a window opening takes its first press only after it has settled
	if(press_gap)
		sleep(press_gap) // a window that rate-limits its buttons on world.time (an answer is a press too), which the test clock does not move
	var/datum/op_result/pressed = test_ui(user, host, action, args)
	if(pressed?.outcome && pressed.outcome != ACT_COMMITTED)
		rows += "press refused: [action] [pressed.reason]"
	test_time(10 SECONDS) // a converted op may wait

/// Answers the user's open request with `value` as a window answer would. The request's usable check wants an open window, which a unit
/// test has none of, so the check is dropped; the rest of the answer path (the kernel, the handler) is the real one.
/datum/ui_pin/proc/answer_open(value)
	var/datum/request/R = SSrequests.open_for(user, null)
	if(!R)
		rows += "no open request"
		return
	R.valid = null
	var/datum/op_result/done = test_answer(user, value)
	if(done?.outcome && done.outcome != ACT_COMMITTED)
		rows += "answer refused: [done.outcome] [done.reason]"
	test_time(10 SECONDS) // a converted op may wait

/// Drops whatever the user is still being asked.
/datum/ui_pin/proc/cancel_open()
	var/datum/request/R = SSrequests.open_for(user, null)
	if(R)
		request_end(R, REQ_CANCELLED, null)

// ---- Agent card -----------------------------------------------------------

/datum/ui_pin/agentcard
	host_type = /datum/tgui_module/agentcard

/datum/ui_pin/agentcard/script(turf/T)
	make_user(T)
	var/obj/item/card/id/syndicate/card = test.allocate(/obj/item/card/id/syndicate, T)
	var/datum/tgui_module/agentcard/module = new(card)
	host = module
	watch_host()
	snap("initial")
	var/datum/act/op/A = op_ctx(user)
	module.ui_act_electronic_warfare(A)
	snap("electronic warfare on")
	module.ui_act_electronic_warfare(A)
	snap("electronic warfare off")
	press("name", list())
	answer_open("Jane Doe")
	snap("name set")
	press("age", list())
	answer_open(42)
	snap("age set")
	press("assignment", list())
	answer_open("Janitor")
	snap("assignment set")
	press("bloodtype", list())
	answer_open("AB-")
	snap("blood type set")
	press("dnahash", list())
	answer_open("DEADBEEF")
	snap("dna hash set")
	press("fingerprinthash", list())
	answer_open("CAFEBABE")
	snap("fingerprint hash set")
	press("sex", list())
	answer_open("Female")
	snap("sex set")
	press("species", list())
	answer_open("Skrell")
	snap("species set")
	press("factoryreset", list())
	answer_open(TRUE)
	snap("factory reset")
	A.release()

// ---- Appearance changer ---------------------------------------------------

/datum/ui_pin/appearance_changer
	host_type = /datum/tgui_module/appearance_changer

/datum/ui_pin/appearance_changer/script(turf/T)
	make_user(T)
	test.interim_keep_awake(user) // a body nobody plays falls asleep, and its questions are dropped
	press_gap = 6 // its buttons answer at most twice a second (ui_cooled())
	user.set_real_name("Pin Tester")
	user.name = "Pin Tester"
	var/datum/tgui_module/appearance_changer/module = new(user, user)
	module.set_flags(APPEARANCE_ALL)
	host = module
	watch_host()
	snap("initial")
	var/datum/act/op/A = op_ctx(user)
	// The custom species name, the size, the species sound set, a flavor text and the colour prompts all end in an update_uis() call.
	press("race_name", list())
	answer_open("Pinfolk")
	snap("custom species name")
	press("size_scale", list())
	answer_open(60)
	snap("size set")
	press("species_sound", list())
	answer_open("Canine")
	snap("species sound")
	press("flavor_text", list("target" = "general"))
	answer_open("A tidy test subject.")
	snap("general flavor text")
	press("flavor_text", list("target" = "face"))
	answer_open("Short hair.")
	snap("head flavor text")
	press("hair_color", list())
	answer_open("#336699")
	snap("hair colour")
	press("eye_color", list())
	answer_open("#00ff00")
	snap("eye colour")
	press("skin_color", list())
	answer_open("#aa8866")
	snap("skin colour")
	cancel_open()
	A.release()

// ---- Vore panel -----------------------------------------------------------
// The mob-level SStgui.update_uis(src) calls in code/modules/vore/eating/living.dm (the escape / liquid / export / feed review answers)
// refresh windows whose source is the mob; the vore window's source is its /datum/vore_look, so that is the host pinned here, through the
// panel's own tab, picture and belly-setting handlers.

/datum/ui_pin/vore_look
	host_type = /datum/vore_look

/datum/ui_pin/vore_look/script(turf/T)
	make_user(T)
	user.set_real_name("Pin Tester")
	user.name = "Pin Tester"
	var/obj/belly/B = test.allocate(/obj/belly, user)
	B.name = "Stomach"
	set_vore_selected(user, B)
	var/datum/vore_look/panel = new(user)
	host = panel
	watch_host()
	snap("belly tab")
	var/datum/act/op/A = op_ctx(user)
	panel.ui_act_show_pictures(A)
	snap("pictures off")
	panel.ui_act_set_attribute(A, "b_name", "Gullet")
	snap("belly renamed")
	panel.ui_act_change_vore_tab(A, 2)
	snap("belly sub tab")
	panel.ui_act_change_tab(A, 1)
	snap("inside tab")
	panel.ui_act_change_tab(A, 2)
	snap("soulcatcher tab")
	panel.ui_act_change_tab(A, 3)
	snap("general tab")
	panel.ui_act_change_tab(A, 4)
	snap("preference tab")
	panel.ui_act_change_tab(A, 0)
	snap("back to belly tab")
	A.release()

// ---- Private notes --------------------------------------------------------

/datum/ui_pin/private_notes_panel
	host_type = /datum/private_notes_panel

/datum/ui_pin/private_notes_panel/script(turf/T)
	make_user(T)
	user.set_real_name("Pin Tester")
	user.name = "Pin Tester"
	user.private_notes = " "
	var/datum/private_notes_panel/panel = new(user)
	host = panel
	watch_host()
	snap("initial")
	var/datum/act/op/A = op_ctx(user)
	panel.ui_act_edit(A)
	snap("edit asked")
	// The answer handler (private_notes_entered) stores the text and saves the preference through the client; with no client the
	// stored text is set by hand, as the answer would, and the open question dropped.
	user.private_notes = "Remember the <b>keys</b> & the door code."
	cancel_open()
	snap("notes written")
	panel.ui_act_edit(A)
	user.private_notes = "Second line\nthird line"
	cancel_open()
	snap("notes rewritten")
	user.private_notes = ""
	snap("notes cleared")
	A.release()

// ---- OOC notes ------------------------------------------------------------

/datum/ui_pin/ooc_notes_panel
	host_type = /datum/ooc_notes_panel

/datum/ui_pin/ooc_notes_panel/script(turf/T)
	make_user(T)
	user.set_real_name("Pin Tester")
	user.name = "Pin Tester"
	var/datum/ooc_notes_panel/panel = new(user)
	host = panel
	watch_host()
	snap("initial")
	var/datum/act/op/A = op_ctx(user)
	// toggle_style (set_metainfo_ooc_style) and the field answers (metainfo_entered) go through the client's preferences, which a unit
	// test has none of: the identity field is set by hand, as the handler would after the toggle / the answer. Each edit op is still
	// driven to open its question, then the question is dropped.
	user.identity().ooc_notes_style = !user.identity().ooc_notes_style
	snap("style toggled")
	panel.ui_act_edit_notes(A)
	user.identity().ooc_notes = "Open to most scenes."
	cancel_open()
	snap("notes set")
	panel.ui_act_edit_favs(A)
	user.identity().ooc_notes_favs = "Cuddles"
	cancel_open()
	snap("favs set")
	panel.ui_act_edit_likes(A)
	user.identity().ooc_notes_likes = "Tea & biscuits"
	cancel_open()
	snap("likes set")
	panel.ui_act_edit_maybes(A)
	user.identity().ooc_notes_maybes = "Chases"
	cancel_open()
	snap("maybes set")
	panel.ui_act_edit_dislikes(A)
	user.identity().ooc_notes_dislikes = "Spoilers"
	cancel_open()
	snap("dislikes set")
	user.identity().ooc_notes_style = FALSE
	snap("style off")
	A.release()
