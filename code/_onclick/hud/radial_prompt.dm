// The radial picker as a typed prompt (doc/rewrite/completion_plan.md, I-menu).
//
// An action picker is asked like any other om_ask() question and answered by a proc; nothing
// waits on the player's click:
//
//	om_ask(user, /datum/om/prompt/choice/radial, PROC_REF(mode_chosen), choices = choices, anchor = user, radius = 42, tooltips = TRUE)
//
//	/obj/item/rcd/proc/mode_chosen(datum/om/prompt/choice/radial/ask)
//		var/mob/living/user = ask.answerer
//		if(!check_menu(user))
//			return
//		switch(ask.choice)
//			...
//
// `choices` is the old show_radial_menu() list (key: the answer, a text or a movable; value: its
// icon, image or /datum/radial_menu_choice). The answer lands in `choice`. `anchor` is where the
// ring is drawn (default: the subject, else the answerer). `require_near` drops an answer given
// out of reach of the anchor. A single choice is answered at once unless autopick_single_option
// is FALSE. The answer proc re-checks anything else (the old custom_check callbacks).
//
// show_radial_menu() and its sleeping wait loop are gone; tools/ci/radial_lint.py keeps them gone.

/datum/om/prompt/choice/radial
	/// Where the ring is drawn; null: the subject, else the answerer.
	var/atom/anchor
	var/radius
	var/tooltips = FALSE
	var/radial_slice_icon = "radial_slice"
	var/autopick_single_option = TRUE
	var/entry_animation = TRUE
	var/click_on_hover = FALSE
	/// Draw the ring around the answerer, offset toward the anchor.
	var/user_space = FALSE
	/// Drop an answer given out of reach of the anchor.
	var/require_near = FALSE
	/// Menu key in GLOB.radial_menus; a second ask with the same key closes the open one.
	var/uniqueid

/datum/om/prompt/choice/radial/prepare()
	return length(choices) > 0

/datum/om/prompt/choice/radial/show_to(mob/user)
	var/atom/where = anchor || (isatom(subject) ? subject : null) || user
	if(!user?.client || !where)
		return FALSE
	if(length(choices) == 1 && autopick_single_option)
		// Nothing to pick: answer with the one choice (after om_ask_begin() finishes parking).
		after(src, 0, PROC_REF(autopick))
		return TRUE
	var/id = uniqueid || "defmenu_[REF(user)]_[REF(where)]"
	var/datum/radial_menu/om/open_menu = GLOB.radial_menus[id]
	if(open_menu)
		// Asking again while it is open toggles it shut.
		open_menu.close_menu()
		return FALSE
	var/datum/radial_menu/om/menu = new
	menu.menu_id = id
	GLOB.radial_menus[id] = menu
	menu.entry_animation = entry_animation
	if(radius)
		menu.radius = radius
	rel_set(menu, nameof(menu.anchor), user_space ? user : where)
	menu.radial_slice_icon = radial_slice_icon
	menu.check_screen_border(user)
	menu.set_choices(choices, tooltips, click_on_hover)
	var/offset_x = 0
	var/offset_y = 0
	if(user_space)
		var/turf/user_turf = get_turf(user)
		var/turf/anchor_turf = get_turf(where)
		offset_x = (anchor_turf.x - user_turf.x) * ICON_SIZE_X + where.pixel_x - user.pixel_x
		offset_y = (anchor_turf.y - user_turf.y) * ICON_SIZE_Y + where.pixel_y - user.pixel_y
	rel_set(src, nameof(ui), menu)
	menu.show_to(user, offset_x, offset_y)
	log_input("Input: [key_name(user)] was shown a radial menu ([type]) on [where].")
	return TRUE

/// after() target: the single choice answers itself.
/datum/om/prompt/choice/radial/proc/autopick()
	om_prompt_answer(src, choices[1])

/datum/om/prompt/choice/radial/valid()
	if(!require_near)
		return null
	var/mob/user = answerer
	var/atom/where = anchor || (isatom(subject) ? subject : null)
	if(where && user && !in_range(where, user))
		return "out of reach"
	return null

/// A radial ring that answers the typed prompt which opened it.
/datum/radial_menu/om
	var/datum/om/prompt/om_prompt
	var/menu_id

/datum/radial_menu/om/relations()
	. = ..()
	. += rel_one(nameof(om_prompt), back = nameof(/datum/om/prompt::ui))

/datum/radial_menu/om/element_chosen(choice_id, mob/user)
	var/answer = LAZYACCESS(choices_values, choice_id)
	if(isnull(answer))
		return
	var/datum/om/prompt/P = om_prompt
	rel_clear(src, nameof(om_prompt))
	dismiss()
	if(P)
		om_prompt_answer(P, answer)

/datum/radial_menu/om/close_menu()
	var/datum/om/prompt/P = om_prompt
	rel_clear(src, nameof(om_prompt))
	dismiss()
	if(P)
		om_prompt_closed(P)

/// Takes the ring off screen and deletes it.
/datum/radial_menu/om/proc/dismiss()
	if(menu_id && GLOB.radial_menus[menu_id] == src)
		GLOB.radial_menus -= menu_id
	hide()
	spent(src)
