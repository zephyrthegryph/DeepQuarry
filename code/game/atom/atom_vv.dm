/**
 * Return the markup to for the dropdown list for the VV panel for this atom
 *
 * Override in subtypes to add custom VV handling in the VV panel
 */
/atom/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---------")
	if(!ismovable(src))
		var/turf/curturf = get_turf(src)
		if(curturf)
			. += "<option value='?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[curturf.x];Y=[curturf.y];Z=[curturf.z]'>Jump To</option>"
	VV_DROPDOWN_OPTION(VV_HK_MODIFY_TRANSFORM, "Modify Transform")
	VV_DROPDOWN_OPTION(VV_HK_SPIN_ANIMATION, "SpinAnimation")
	VV_DROPDOWN_OPTION(VV_HK_STOP_ALL_ANIMATIONS, "Stop All Animations")
	VV_DROPDOWN_OPTION(VV_HK_TRIGGER_EMP, "EMP Pulse")
	VV_DROPDOWN_OPTION(VV_HK_TRIGGER_EXPLOSION, "Explosion")
	VV_DROPDOWN_OPTION(VV_HK_EDIT_FILTERS, "Edit Filters")
	//VV_DROPDOWN_OPTION(VV_HK_EDIT_COLOR_MATRIX, "Edit Color as Matrix")
	VV_DROPDOWN_OPTION(VV_HK_TEST_MATRIXES, "Test Matrices")
	//if(greyscale_colors)
	//	VV_DROPDOWN_OPTION(VV_HK_MODIFY_GREYSCALE, "Modify greyscale colors")

/// Admin var-edit questions about an atom (vv_do_topic()).
/datum/om/prompt/number/vv_edit
	requires = PROMPT_ADMIN(R_VAREDIT)
	min = -INFINITY

/datum/om/prompt/choice/vv_edit
	requires = PROMPT_ADMIN(R_VAREDIT)

/datum/om/prompt/confirm/vv_edit
	requires = PROMPT_ADMIN(R_VAREDIT)

/datum/om/prompt/text/vv_edit
	requires = PROMPT_ADMIN(R_VAREDIT)

/// "Modify Transform": the kind, then the x (and for all but a rotation, the y) mod.
/datum/om/flow/vv_transform
	requires = PROMPT_ADMIN(R_VAREDIT)
	var/transform_kind
	var/x_mod

/datum/om/flow/vv_transform/start()
	om_ask(actor, /datum/om/prompt/choice/vv_edit, PROC_REF(kind_chosen), title = "Transform Mod", message = "Choose the transformation to apply", choices = list("Scale","Translate","Rotate","Shear"))

/datum/om/flow/vv_transform/proc/kind_chosen(datum/om/prompt/choice/vv_edit/ask)
	transform_kind = ask.choice
	var/question
	switch(transform_kind)
		if("Scale", "Shear")
			question = "Choose x mod"
		if("Translate")
			question = "Choose x mod (negative = left, positive = right)"
		if("Rotate")
			question = "Choose angle to rotate"
		else
			return
	om_ask(actor, /datum/om/prompt/number/vv_edit, PROC_REF(x_entered), title = "Transform Mod", message = question)

/datum/om/flow/vv_transform/proc/x_entered(datum/om/prompt/number/vv_edit/ask)
	x_mod = ask.number
	var/question
	switch(transform_kind)
		if("Scale", "Shear")
			question = "Choose y mod"
		if("Translate")
			question = "Choose y mod (negative = down, positive = up)"
		else
			apply()
			return
	om_ask(actor, /datum/om/prompt/number/vv_edit, PROC_REF(y_entered), title = "Transform Mod", message = question)

/datum/om/flow/vv_transform/proc/y_entered(datum/om/prompt/number/vv_edit/ask)
	apply(ask.number)

/datum/om/flow/vv_transform/proc/apply(y_mod)
	var/atom/A = target
	var/matrix/M = A.transform
	switch(transform_kind)
		if("Scale")
			A.transform = M.Scale(x_mod, y_mod)
		if("Translate")
			A.transform = M.Translate(x_mod, y_mod)
		if("Shear")
			A.transform = M.Shear(x_mod, y_mod)
		if("Rotate")
			A.transform = M.Turn(x_mod)

/// "Spin Animation": infinite or a count, the rate, and the direction.
/datum/om/flow/vv_spin
	requires = PROMPT_ADMIN(R_VAREDIT)
	var/num_spins = -1
	var/spins_per_sec

/datum/om/flow/vv_spin/start()
	om_ask(actor, /datum/om/prompt/confirm/vv_edit, PROC_REF(infinite_answered), title = "Spin Animation", message = "Do you want infinite spins?", answer_on_no = TRUE)

/datum/om/flow/vv_spin/proc/infinite_answered(datum/om/prompt/confirm/vv_edit/ask)
	if(ask.yes)
		ask_rate()
		return
	om_ask(actor, /datum/om/prompt/number/vv_edit, PROC_REF(count_entered), title = "Spin Animation", message = "How many spins?", min = 0)

/datum/om/flow/vv_spin/proc/count_entered(datum/om/prompt/number/vv_edit/ask)
	num_spins = ask.number
	ask_rate()

/datum/om/flow/vv_spin/proc/ask_rate()
	om_ask(actor, /datum/om/prompt/number/vv_edit, PROC_REF(rate_entered), title = "Spin Animation", message = "How many spins per second?", min = 0)

/datum/om/flow/vv_spin/proc/rate_entered(datum/om/prompt/number/vv_edit/ask)
	spins_per_sec = ask.number
	om_ask(actor, /datum/om/prompt/choice/vv_edit, PROC_REF(direction_chosen), title = "Spin Animation", message = "Which direction?", choices = list("Clockwise", "Counter-clockwise"), buttons = TRUE)

/datum/om/flow/vv_spin/proc/direction_chosen(datum/om/prompt/choice/vv_edit/ask)
	if(!num_spins || !spins_per_sec)
		return
	var/atom/A = target
	A.SpinAnimation(1 SECONDS / spins_per_sec, num_spins, ask.choice == "Clockwise" ? 1 : 0)

/atom/proc/vv_stop_animations_answered(datum/om/prompt/confirm/vv_edit/ask)
	animate(src, transform = null, flags = ANIMATION_END_NOW) // Literally just fucking stop animating entirely because admin said so

/atom/proc/vv_auto_rename_entered(datum/om/prompt/text/vv_edit/ask)
	if(ask.text)
		vv_auto_rename(src, ask.text)

/atom/vv_do_topic(list/href_list)
	. = ..()

	if(!.)
		return

	if(href_list[VV_HK_TRIGGER_EXPLOSION])
		return SSadmin_verbs.dynamic_invoke_verb(usr, /datum/admin_verb/admin_explosion, src)

	if(href_list[VV_HK_TRIGGER_EMP])
		return SSadmin_verbs.dynamic_invoke_verb(usr, /datum/admin_verb/admin_emp, src)

	if(href_list[VV_HK_MODIFY_TRANSFORM])
		if(!check_rights(R_VAREDIT))
			return
		om_flow_start(/datum/om/flow/vv_transform, usr, src)

	if(href_list[VV_HK_SPIN_ANIMATION])
		if(!check_rights(R_VAREDIT))
			return
		om_flow_start(/datum/om/flow/vv_spin, usr, src)

	if(href_list[VV_HK_STOP_ALL_ANIMATIONS])
		if(!check_rights(R_VAREDIT))
			return
		om_ask(usr, /datum/om/prompt/confirm/vv_edit, TYPE_PROC_REF(/atom, vv_stop_animations_answered), title = "Stop Animating", message = "Are you sure?")
		return

	if(href_list[VV_HK_AUTO_RENAME])
		if(!check_rights(R_VAREDIT))
			return
		om_ask(usr, /datum/om/prompt/text/vv_edit, TYPE_PROC_REF(/atom, vv_auto_rename_entered), title = "Automatic Rename", message = "What do you want to rename this to?")
		// Check the new name against the chat filter. If it triggers the IC chat filter, give an option to confirm.
		//if(newname && !(is_ic_filtered(newname) || is_soft_ic_filtered(newname) && tgui_alert(usr, "Your selected name contains words restricted by IC chat filters. Confirm this new name?", "IC Chat Filter Conflict", list("Confirm", "Cancel")) != "Confirm"))

	if(href_list[VV_HK_EDIT_FILTERS])
		if(!check_rights(R_VAREDIT))
			return
		usr.client?.open_filter_editor(src)

	if(href_list[VV_HK_TEST_MATRIXES])
		if(!check_rights(R_VAREDIT))
			return
		usr.client?.open_matrix_tester(src)

/atom/vv_get_header()
	. = ..()
	var/refid = REF(src)
	. += "[VV_HREF_TARGETREF(refid, VV_HK_AUTO_RENAME, span_bold("<span id='name'>[src]</span>"))]"
	. += "<br>" + span_small("<a href='byond://?_src_=vars;[HrefToken()];rotatedatum=[refid];rotatedir=left'><<</a> <a href='byond://?_src_=vars;[HrefToken()];datumedit=[refid];varnameedit=dir' id='dir'>[dir2text(dir) || dir]</a> <a href='byond://?_src_=vars;[HrefToken()];rotatedatum=[refid];rotatedir=right'>>></a>")

/**
 * call back when a var is edited on this atom
 *
 * Can be used to implement special handling of vars
 *
 * At the atom level, if you edit a var named "color" it will add the atom colour with
 * admin level priority to the atom colours list
 *
 * Also, if GLOB.Debug2 is FALSE, it sets the [ADMIN_SPAWNED_1] flag on [flags_1][/atom/var/flags_1], which signifies
 * the object has been admin edited
 */
/atom/vv_edit_var(var_name, var_value)
	//var/old_light_flags = light_flags
	// Disable frozen lights for now, so we can actually modify it
	switch(var_name)
		if(NAMEOF(src, light_range))
			if(light_system == STATIC_LIGHT)
				set_light(l_range = var_value)
			else
				set_light_range(var_value)
			. =  TRUE
		if(NAMEOF(src, light_power))
			if(light_system == STATIC_LIGHT)
				set_light(l_power = var_value)
			else
				set_light_power(var_value)
			. =  TRUE
		if(NAMEOF(src, light_color))
			if(light_system == STATIC_LIGHT)
				set_light(l_color = var_value)
			else
				set_light_color(var_value)
			. =  TRUE
		if(NAMEOF(src, light_on))
			set_light_on(var_value)
			. =  TRUE
		if(NAMEOF(src, light_flags))
			set_light_flags(var_value)
			. =  TRUE
		if(NAMEOF(src, opacity))
			set_opacity(var_value)
			. =  TRUE

	//light_flags = old_light_flags
	if(!isnull(.))
		datum_flags |= DF_VAR_EDITED
		return

	//if(!GLOB.Debug2)
	//	flags_1 |= ADMIN_SPAWNED_1

	. = ..()

	switch(var_name)
		if(NAMEOF(src, color))
			add_atom_colour(color, ADMIN_COLOUR_PRIORITY)
			//update_appearance()
			update_icon()

/proc/vv_auto_rename(atom/target, newname)
	target.name = newname
