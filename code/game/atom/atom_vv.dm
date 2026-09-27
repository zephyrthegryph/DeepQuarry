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

/atom/proc/vv_transform_question_x(mob/user, datum/om/prompt/ask)
	switch(ask.get("kind"))
		if("Scale", "Shear")
			return list("key" = "x", "kind" = "number", "message" = "Choose x mod", "title" = "Transform Mod", "min" = -INFINITY)
		if("Translate")
			return list("key" = "x", "kind" = "number", "message" = "Choose x mod (negative = left, positive = right)", "title" = "Transform Mod", "min" = -INFINITY)
		if("Rotate")
			return list("key" = "x", "kind" = "number", "message" = "Choose angle to rotate", "title" = "Transform Mod", "min" = -INFINITY)

/atom/proc/vv_transform_question_y(mob/user, datum/om/prompt/ask)
	switch(ask.get("kind"))
		if("Scale", "Shear")
			return list("key" = "y", "kind" = "number", "message" = "Choose y mod", "title" = "Transform Mod", "min" = -INFINITY)
		if("Translate")
			return list("key" = "y", "kind" = "number", "message" = "Choose y mod (negative = down, positive = up)", "title" = "Transform Mod", "min" = -INFINITY)

/atom/proc/vv_transform_chosen(mob/user, datum/om/prompt/ask)
	var/matrix/M = transform
	var/x = ask.get("x")
	var/y = ask.get("y")
	switch(ask.get("kind"))
		if("Scale")
			transform = M.Scale(x,y)
		if("Translate")
			transform = M.Translate(x,y)
		if("Shear")
			transform = M.Shear(x,y)
		if("Rotate")
			transform = M.Turn(x)

/atom/proc/vv_spin_question_count(mob/user, datum/om/prompt/ask)
	if(ask.get("infinite") == "No")
		return list("key" = "count", "kind" = "number", "message" = "How many spins?", "title" = "Spin Animation")

/atom/proc/vv_spin_chosen(mob/user, datum/om/prompt/ask)
	var/num_spins = ask.get("infinite") == "No" ? ask.get("count") : -1
	var/spins_per_sec = ask.get("rate")
	if(!num_spins || !spins_per_sec)
		return
	SpinAnimation(1 SECONDS / spins_per_sec, num_spins, ask.get("direction") == "Clockwise" ? 1 : 0)

/atom/proc/vv_stop_animations_answered(mob/user, result, datum/om/prompt/ask)
	if(result == "Yes")
		animate(src, transform = null, flags = ANIMATION_END_NOW) // Literally just fucking stop animating entirely because admin said so

/atom/proc/vv_auto_rename_entered(mob/user, newname, datum/om/prompt/ask)
	if(newname)
		vv_auto_rename(newname)

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
		om_prompt_sequence(src, usr, list(
			list("key" = "kind", "kind" = "list", "message" = "Choose the transformation to apply", "title" = "Transform Mod", "choices" = list("Scale","Translate","Rotate","Shear")),
			/atom/proc/vv_transform_question_x,
			/atom/proc/vv_transform_question_y,
		), /atom/proc/vv_transform_chosen, list("requires" = PROMPT_ADMIN(R_VAREDIT)))

	if(href_list[VV_HK_SPIN_ANIMATION])
		if(!check_rights(R_VAREDIT))
			return
		om_prompt_sequence(src, usr, list(
			list("key" = "infinite", "message" = "Do you want infinite spins?", "title" = "Spin Animation", "choices" = list("Yes", "No")),
			/atom/proc/vv_spin_question_count,
			list("key" = "rate", "kind" = "number", "message" = "How many spins per second?", "title" = "Spin Animation"),
			list("key" = "direction", "message" = "Which direction?", "title" = "Spin Animation", "choices" = list("Clockwise", "Counter-clockwise")),
		), /atom/proc/vv_spin_chosen, list("requires" = PROMPT_ADMIN(R_VAREDIT)))

	if(href_list[VV_HK_STOP_ALL_ANIMATIONS])
		if(!check_rights(R_VAREDIT))
			return
		om_prompt(src, usr, list("message" = "Are you sure?", "title" = "Stop Animating", "choices" = list("Yes", "No"), "requires" = PROMPT_ADMIN(R_VAREDIT)), /atom/proc/vv_stop_animations_answered)
		return

	if(href_list[VV_HK_AUTO_RENAME])
		if(!check_rights(R_VAREDIT))
			return
		om_prompt(src, usr, list("kind" = "text", "message" = "What do you want to rename this to?", "title" = "Automatic Rename", "requires" = PROMPT_ADMIN(R_VAREDIT)), /atom/proc/vv_auto_rename_entered)
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

/atom/proc/vv_auto_rename(newname)
	name = newname
