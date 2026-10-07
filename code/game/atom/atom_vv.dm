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
	VV_DROPDOWN_OPTION(VV_HK_TEST_MATRIXES, "Test Matrices")

/// Native VV transform/spin questions retain the original actor and captured target.
/datum/prompt/choice/vv_edit
	rights = R_VAREDIT
	timeout = 0
	var/transform_kind
	var/x_mod
	var/num_spins = -1
	var/spins_per_sec
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/vv_edit)
	ref_one(nameof(subject), /atom)

/datum/prompt/choice/vv_edit/prepare(datum/act/A)
	..()
	var/datum/request/request = src
	var/atom/captured_subject = subject
	rel_clear(request, nameof(request.subject))
	rel_set(request, nameof(request.subject), captured_subject)

/datum/prompt/choice/vv_edit/recheck_extra()
	return QDELETED(subject) ? "gone" : null

/// Native VV transform/spin questions retain the original actor and captured target.
/datum/prompt/number/vv_edit
	rights = R_VAREDIT
	timeout = 0
	min_value = -INFINITY
	max_value = INFINITY
	step = 1
	var/transform_kind
	var/x_mod
	var/num_spins = -1
	var/spins_per_sec
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/number/vv_edit)
	ref_one(nameof(subject), /atom)

/datum/prompt/number/vv_edit/prepare(datum/act/A)
	..()
	var/datum/request/request = src
	var/atom/captured_subject = subject
	rel_clear(request, nameof(request.subject))
	rel_set(request, nameof(request.subject), captured_subject)

/datum/prompt/number/vv_edit/recheck_extra()
	return QDELETED(subject) ? "gone" : null

/// Native VV transform/spin questions retain the original actor and captured target.
/datum/prompt/yes_no/vv_edit
	rights = R_VAREDIT
	timeout = 0
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/yes_no/vv_edit)
	ref_one(nameof(subject), /atom)

/datum/prompt/yes_no/vv_edit/prepare(datum/act/A)
	..()
	var/datum/request/request = src
	var/atom/captured_subject = subject
	rel_clear(request, nameof(request.subject))
	rel_set(request, nameof(request.subject), captured_subject)

/datum/prompt/yes_no/vv_edit/recheck_extra()
	return QDELETED(subject) ? "gone" : null

/mob/proc/vv_transform_begin(atom/target)
	open_request(src, /datum/prompt/choice/vv_edit, PROC_REF(vv_transform_kind_chosen), answerer = src, subject = target, title = "Transform Mod", question = "Choose the transformation to apply", choices = list("Scale","Translate","Rotate","Shear"))

/mob/proc/vv_transform_kind_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/transform_kind = context.answer.value
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
	open_request(src, /datum/prompt/number/vv_edit, PROC_REF(vv_transform_x_entered), answerer = src, subject = context.request.subject, title = "Transform Mod", question = question, transform_kind = transform_kind)

/mob/proc/vv_transform_x_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/vv_edit/ask = context.answer
	var/x_mod = ask.value
	var/question
	switch(ask.transform_kind)
		if("Scale", "Shear")
			question = "Choose y mod"
		if("Translate")
			question = "Choose y mod (negative = down, positive = up)"
		else
			vv_transform_apply(ask.subject, ask.transform_kind, x_mod)
			return
	open_request(src, /datum/prompt/number/vv_edit, PROC_REF(vv_transform_y_entered), answerer = src, subject = ask.subject, title = "Transform Mod", question = question, transform_kind = ask.transform_kind, x_mod = x_mod)

/mob/proc/vv_transform_y_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/vv_edit/ask = context.answer
	vv_transform_apply(ask.subject, ask.transform_kind, ask.x_mod, ask.value)

/mob/proc/vv_transform_apply(atom/A, transform_kind, x_mod, y_mod)
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

/mob/proc/vv_spin_begin(atom/target)
	open_request(src, /datum/prompt/yes_no/vv_edit, PROC_REF(vv_spin_infinite_answered), answerer = src, subject = target, title = "Spin Animation", question = "Do you want infinite spins?")

/mob/proc/vv_spin_infinite_answered(datum/act/request/context)
	if(!context.answer)
		return
	if(context.answer.value)
		vv_spin_ask_rate(context.request.subject)
		return
	open_request(src, /datum/prompt/number/vv_edit, PROC_REF(vv_spin_count_entered), answerer = src, subject = context.request.subject, title = "Spin Animation", question = "How many spins?", min_value = 0)

/mob/proc/vv_spin_count_entered(datum/act/request/context)
	if(!context.answer)
		return
	vv_spin_ask_rate(context.request.subject, context.answer.value)

/mob/proc/vv_spin_ask_rate(atom/target, num_spins = -1)
	open_request(src, /datum/prompt/number/vv_edit, PROC_REF(vv_spin_rate_entered), answerer = src, subject = target, title = "Spin Animation", question = "How many spins per second?", min_value = 0, num_spins = num_spins)

/mob/proc/vv_spin_rate_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/vv_edit/ask = context.answer
	open_request(src, /datum/prompt/choice/vv_edit, PROC_REF(vv_spin_direction_chosen), answerer = src, subject = ask.subject, title = "Spin Animation", question = "Which direction?", choices = list("Clockwise", "Counter-clockwise"), buttons = TRUE, num_spins = ask.num_spins, spins_per_sec = ask.value)

/mob/proc/vv_spin_direction_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/vv_edit/ask = context.answer
	if(!ask.num_spins || !ask.spins_per_sec)
		return
	var/atom/A = ask.subject
	A.SpinAnimation(1 SECONDS / ask.spins_per_sec, ask.num_spins, ask.value == "Clockwise" ? 1 : 0)


/atom/proc/vv_topic_explosion(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/admin_explosion, src)
	return TRUE

/atom/proc/vv_topic_emp(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/admin_emp, src)
	return TRUE

/atom/proc/vv_topic_modify_transform(datum/act/op/A)
	var/mob/user = A.actor
	user?.vv_transform_begin(src)
	return TRUE

/atom/proc/vv_topic_spin_animation(datum/act/op/A)
	var/mob/user = A.actor
	user?.vv_spin_begin(src)
	return TRUE

/atom/proc/vv_topic_stop_animations(datum/act/op/A)
	animate(src, transform = null, flags = ANIMATION_END_NOW) // Literally just fucking stop animating entirely because admin said so

/atom/proc/vv_topic_auto_rename(datum/act/op/A)
	var/new_name = A.step_value("name")
	if(new_name)
		vv_auto_rename(src, new_name)

/atom/proc/vv_topic_edit_filters(datum/act/op/A)
	var/mob/user = A.actor
	user.client?.open_filter_editor(src)
	return TRUE

/atom/proc/vv_topic_test_matrixes(datum/act/op/A)
	var/mob/user = A.actor
	user.client?.open_matrix_tester(src)
	return TRUE

/atom/vv_get_header()
	. = ..()
	var/refid = REF(src)
	. += "[VV_HREF_TARGETREF(refid, VV_HK_AUTO_RENAME, span_bold("<span id='name'>[src]</span>"))]"
	. += "<br>" + span_small("<a href='byond://?_src_=vars;[HrefToken()];rotatedatum=[refid];rotatedir=left'><<</a> [VV_HREF_TARGETREF_1V(refid, VV_HK_BASIC_EDIT, "[dir2text(dir) || dir]", "dir")] <a href='byond://?_src_=vars;[HrefToken()];rotatedatum=[refid];rotatedir=right'>>></a>")

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

	if(!isnull(.))
		datum_flags |= DF_VAR_EDITED
		return


	. = ..()

	switch(var_name)
		if(NAMEOF(src, color))
			add_atom_colour(color, ADMIN_COLOUR_PRIORITY)
			update_icon()

/proc/vv_auto_rename(atom/target, newname)
	target.name = newname
