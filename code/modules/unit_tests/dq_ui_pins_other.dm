// Window-data pin drivers for the other window hosts (dq_ui_pins.dm): the agent card, the appearance changer, the vore panel and the
// private / OOC notes panels. No client exists in a unit test, so a handler that asks a question is driven by opening it (the real
// ui_act_* proc) and answering the open request directly; a handler that reaches a client (preferences) has its state change made by hand,
// as its answer would, and says so in a comment.

/// A bare op context of `actor`, as the op engine hands a handler.
/datum/ui_pin/proc/op_ctx(mob/actor)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = actor
	return A

/// Answers the user's open request with `value` as a window answer would. The request's usable check wants an open window, which a unit
/// test has none of, so the check is dropped; the rest of the answer path (the kernel, the handler) is the real one.
/datum/ui_pin/proc/answer_open(value)
	var/datum/request/R = SSrequests.open_for(user, null)
	if(!R)
		rows += "no open request"
		return
	R.valid = null
	var/why = request_submit(R, value)
	if(why)
		rows += "answer refused: [why]"

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
	module.ui_act_name(A)
	answer_open("Jane Doe")
	snap("name set")
	module.ui_act_age(A)
	answer_open(42)
	snap("age set")
	module.ui_act_assignment(A)
	answer_open("Janitor")
	snap("assignment set")
	module.ui_act_bloodtype(A)
	answer_open("AB-")
	snap("blood type set")
	module.ui_act_dnahash(A)
	answer_open("DEADBEEF")
	snap("dna hash set")
	module.ui_act_fingerprinthash(A)
	answer_open("CAFEBABE")
	snap("fingerprint hash set")
	module.ui_act_sex(A)
	answer_open("Female")
	snap("sex set")
	module.ui_act_species(A)
	answer_open("Skrell")
	snap("species set")
	module.ui_act_factoryreset(A)
	answer_open(TRUE)
	snap("factory reset")
	A.release()

// ---- Appearance changer ---------------------------------------------------

/datum/ui_pin/appearance_changer
	host_type = /datum/tgui_module/appearance_changer

/datum/ui_pin/appearance_changer/script(turf/T)
	make_user(T)
	user.real_name = "Pin Tester"
	user.name = "Pin Tester"
	var/datum/tgui_module/appearance_changer/module = new(user, user)
	module.flags = APPEARANCE_ALL
	host = module
	watch_host()
	snap("initial")
	var/datum/act/op/A = op_ctx(user)
	// The custom species name, the size, the species sound set, a flavor text and the colour prompts all end in an update_uis() call.
	module.ui_act_race_name(A)
	answer_open("Pinfolk")
	snap("custom species name")
	module.ui_act_size_scale(A)
	answer_open(60)
	snap("size set")
	module.ui_act_species_sound(A)
	answer_open("Canine")
	snap("species sound")
	module.ui_act_flavor_text(A, "general")
	answer_open("A tidy test subject.")
	snap("general flavor text")
	module.ui_act_flavor_text(A, "head")
	answer_open("Short hair.")
	snap("head flavor text")
	module.ui_act_hair_color(A)
	answer_open("#336699")
	snap("hair colour")
	module.ui_act_eye_color(A)
	answer_open("#00ff00")
	snap("eye colour")
	module.ui_act_skin_color(A)
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
	user.real_name = "Pin Tester"
	user.name = "Pin Tester"
	var/obj/belly/B = test.allocate(/obj/belly, user)
	B.name = "Stomach"
	rel_set(user, nameof(user.vore_selected), B)
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
	user.real_name = "Pin Tester"
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
	user.real_name = "Pin Tester"
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
