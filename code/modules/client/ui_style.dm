/proc/ui_style2icon(ui_style)
	if(ui_style in GLOB.all_ui_styles)
		return GLOB.all_ui_styles[ui_style]
	return GLOB.all_ui_styles["White"]


/client/verb/change_ui()
	set name = "Change UI"
	set category = VERB_CAT_PREFERENCES_GAME
	set desc = "Configure your user interface"

	if(!ishuman(usr))
		if(!isrobot(usr))
			to_chat(src, span_warning("You must be a human or a robot to use this verb."))
			return

	var/current_style = prefs.read_preference(/datum/preference/choiced/ui_style)
	var/current_alpha = prefs.read_preference(/datum/preference/numeric/ui_style_alpha)
	var/current_color = prefs.read_preference(/datum/preference/color/ui_style_color)
	var/UI_style_new = client_ask("a1", VERB_REF(change_ui), args, 0, /datum/om/prompt/choice, message = "Select a style. White is recommended for customization", title = "UI Style Choice", choices = GLOB.all_ui_styles, default = current_style)
	if(isnull(UI_style_new))
		return
	if(!UI_style_new) return

	var/UI_style_alpha_new = client_ask("a2", VERB_REF(change_ui), args, 0, /datum/om/prompt/number, message = "Select a new alpha (transparency) parameter for your UI, between 50 and 255", default = current_alpha, max = 255, min = 50)
	if(isnull(UI_style_alpha_new))
		return
	if(!UI_style_alpha_new || !(UI_style_alpha_new <= 255 && UI_style_alpha_new >= 50)) return

	om_ask(src, /datum/om/prompt/color/ui_style, PROC_REF(ui_color_picked), default = current_color, style = UI_style_new, alpha = UI_style_alpha_new, old_style = current_style, old_alpha = current_alpha, old_color = current_color)

/// The UI colour pick of Change UI; the state is the style and alpha already picked, and the old
/// look to go back to.
/datum/om/prompt/color/ui_style
	message = "Choose your UI color. Dark colors are not recommended!"
	var/style
	var/alpha
	var/old_style
	var/old_alpha
	var/old_color

/client/proc/ui_color_picked(datum/om/prompt/color/ui_style/ask)
	//update UI
	ask.answerer.update_ui_style(ask.style, ask.alpha, ask.picked_color)
	om_ask(ask.answerer, /datum/om/prompt/confirm/ui_style_save, PROC_REF(ui_style_saved), style = ask.style, alpha = ask.alpha, color = ask.picked_color, old_style = ask.old_style, old_alpha = ask.old_alpha, old_color = ask.old_color)

/// Keep the new UI look? No (or a closed window) puts the old one back.
/datum/om/prompt/confirm/ui_style_save
	title = "Save?"
	message = "Like it? Save changes?"
	answer_on_no = TRUE
	cancel_answer = "No"
	var/style
	var/alpha
	var/color
	var/old_style
	var/old_alpha
	var/old_color

/client/proc/ui_style_saved(datum/om/prompt/confirm/ui_style_save/ask)
	var/mob/user = ask.answerer
	if(ask.yes)
		user.write_preference_directly(/datum/preference/choiced/ui_style, ask.style, WRITE_PREF_MANUAL)
		user.write_preference_directly(/datum/preference/numeric/ui_style_alpha, ask.alpha, WRITE_PREF_MANUAL)
		user.write_preference_directly(/datum/preference/color/ui_style_color, ask.color, WRITE_PREF_MANUAL)
		GLOB.character_setup_service.queue_preferences_save(prefs)
		to_chat(src, "UI was saved")
		return

	user.update_ui_style(ask.old_style, ask.old_alpha, ask.old_color)
