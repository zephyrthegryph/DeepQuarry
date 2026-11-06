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

	open_request(src, /datum/prompt/choice, PROC_REF(ui_style_chosen), answerer = mob, title = "UI Style Choice", question = "Select a style. White is recommended for customization", choices = GLOB.all_ui_styles, default = prefs.read_preference(/datum/preference/choiced/ui_style), timeout = 0)

/client/proc/ui_style_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	if(!ishuman(user) && !istype(user, /mob/living/silicon/robot))
		to_chat(src, span_warning("You must be a human or a robot to use this verb."))
		return
	var/style = A.request.value
	if(!style)
		return
	open_request(src, /datum/prompt/number/ui_style_alpha, PROC_REF(ui_alpha_picked), answerer = mob, default = prefs.read_preference(/datum/preference/numeric/ui_style_alpha), style = style)

/datum/prompt/number/ui_style_alpha
	question = "Select a new alpha (transparency) parameter for your UI, between 50 and 255"
	timeout = 0
	min_value = 50
	max_value = 255
	step = 1
	var/style

/client/proc/ui_alpha_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	if(!ishuman(user) && !istype(user, /mob/living/silicon/robot))
		to_chat(src, span_warning("You must be a human or a robot to use this verb."))
		return
	var/datum/prompt/number/ui_style_alpha/ask = A.request
	var/alpha = ask.value
	if(!alpha || !(alpha <= 255 && alpha >= 50))
		return
	open_request(src, /datum/prompt/color/ui_style, PROC_REF(ui_color_picked), answerer = mob, default = prefs.read_preference(/datum/preference/color/ui_style_color), style = ask.style, alpha = alpha, old_style = prefs.read_preference(/datum/preference/choiced/ui_style), old_alpha = prefs.read_preference(/datum/preference/numeric/ui_style_alpha), old_color = prefs.read_preference(/datum/preference/color/ui_style_color))

/// The UI colour pick of Change UI; the state is the style and alpha already picked, and the old
/// look to go back to.
/datum/prompt/color/ui_style
	timeout = 0
	question = "Choose your UI color. Dark colors are not recommended!"
	var/style
	var/alpha
	var/old_style
	var/old_alpha
	var/old_color

/client/proc/ui_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/ui_style/ask = A.request
	var/mob/user = ask.answerer
	//update UI
	user.update_ui_style(ask.style, ask.alpha, ask.value)
	open_request(src, /datum/prompt/yes_no/ui_style_save, PROC_REF(ui_style_saved), answerer = user, style = ask.style, alpha = ask.alpha, color = ask.value, old_style = ask.old_style, old_alpha = ask.old_alpha, old_color = ask.old_color)

/// Keep the new UI look? No (or a closed window) puts the old one back.
/datum/prompt/yes_no/ui_style_save
	timeout = 0
	title = "Save?"
	question = "Like it? Save changes?"
	var/style
	var/alpha
	var/color
	var/old_style
	var/old_alpha
	var/old_color

/client/proc/ui_style_saved(datum/act/request/A)
	var/datum/prompt/yes_no/ui_style_save/ask = A.request
	if(!A.answer && !(ask.outcome == REQ_CANCELLED && isnull(ask.value)))
		return
	var/mob/user = ask.answerer
	if(QDELETED(user))
		return
	if(A.answer && ask.value)
		user.write_preference_directly(/datum/preference/choiced/ui_style, ask.style, WRITE_PREF_MANUAL)
		user.write_preference_directly(/datum/preference/numeric/ui_style_alpha, ask.alpha, WRITE_PREF_MANUAL)
		user.write_preference_directly(/datum/preference/color/ui_style_color, ask.color, WRITE_PREF_MANUAL)
		SScharacter_setup.queue_preferences_save(prefs)
		to_chat(src, "UI was saved")
		return

	user.update_ui_style(ask.old_style, ask.old_alpha, ask.old_color)
