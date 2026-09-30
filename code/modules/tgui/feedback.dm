/datum/tgui_feedback
	var/selected_window

DECLARE_UI(/datum/tgui_feedback, "TguiFeedback", UI_TITLE("TGUI Feedback Submission"))

DECLARE_UI_STATE(/datum/tgui_feedback, GLOB.tgui_always_state)

/datum/tgui_feedback/tgui_static_data(mob/user)
	var/list/data = list()

	data["open_windows"] = list()
	for(var/datum/tgui/ui in user.tgui_open_uis)
		data["open_windows"] += ui.title

	return data

UI_DATA_REPLACE(/datum/tgui_feedback, "selected_window")

UI_ACT(/datum/tgui_feedback, "pick_window", ui_act_pick_window, UI_ARG_TEXT("win"))
UI_ACT_PROC(/datum/tgui_feedback, ui_act_pick_window)
	if(!params["win"])
		return

	selected_window = sanitize(params["win"])
	. = TRUE

UI_ACT(/datum/tgui_feedback, "submit", ui_act_submit, UI_ARG_TEXT("comment"), UI_ARG_TEXT("rating"))
UI_ACT_PROC(/datum/tgui_feedback, ui_act_submit)
	message_admins("TGUI Feedback: Rating [params["rating"]] - Comment: [params["comment"]]")
	. = TRUE

/client/verb/tgui_feedback()
	set name = "Submit TGUI Feedback"
	set category = VERB_CAT_OOC_DEBUG

	var/datum/tgui_feedback/feedback = new()
	feedback.tgui_interact(usr)
