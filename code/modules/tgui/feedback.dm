/datum/tgui_feedback
	var/selected_window

CAPABILITIES(/datum/tgui_feedback)
	interface("TguiFeedback", title = "TGUI Feedback Submission", state = nameof(GLOB.tgui_always_state))
	op("pick_window", ui_act("pick_window", arg("win", schema_text(4096))), then(PROC_REF(ui_act_pick_window)))
	op("submit", ui_act("submit", arg("comment", schema_text(4096)), arg("rating", schema_text(4096))), then(PROC_REF(ui_act_submit)))

/datum/tgui_feedback/tgui_static_data(mob/user)
	var/list/data = list()

	data["open_windows"] = list()
	for(var/datum/tgui/ui in user.tgui_open_uis)
		data["open_windows"] += ui.title

	return data

/datum/tgui_feedback/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["selected_window"] = selected_window
	return data

/datum/tgui_feedback/proc/ui_act_pick_window(datum/act/op/A, win)
	if(!win)
		return

	selected_window = sanitize(win)
	. = TRUE

/datum/tgui_feedback/proc/ui_act_submit(datum/act/op/A, comment, rating)
	message_admins("TGUI Feedback: Rating [rating] - Comment: [comment]")
	. = TRUE

/client/verb/tgui_feedback()
	set name = "Submit TGUI Feedback"
	set category = VERB_CAT_OOC_DEBUG

	var/datum/tgui_feedback/feedback = new()
	feedback.tgui_interact(usr)
