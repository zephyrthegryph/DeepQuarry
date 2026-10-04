ADMIN_VERB(change_human_appearance_admin, R_FUN, "Change Mob Appearance - Admin", "Allows you to change the mob appearance.", ADMIN_CATEGORY_EVENTS)
	if(QDELETED(user.mob))
		return
	open_request(src, /datum/prompt/choice/admin_appearance_target, PROC_REF(appearance_target_answered), answerer = user.mob, choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))

ADMIN_VERB(change_human_appearance_self, R_FUN, "Change Mob Appearance - Self", "Allows the mob to change its appearance.", ADMIN_CATEGORY_EVENTS)
	var/mob/living/carbon/human/human_target = verb_ask(user, "a2", args, /datum/om/prompt/choice, message = "Select mob.", title = "Change Mob Appearance - Self", choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))
	if(isnull(human_target))
		return
	if(!human_target)
		return

	if(!human_target.client)
		to_chat(human_target, span_filter_warning("Only mobs with clients can alter their own appearance."))
		return
	var/whitelist_answer = verb_ask(user, "whitelist", args, /datum/om/prompt/choice/alert, message = "Do you wish for [human_target] to be allowed to select non-whitelisted races?", title = "Alter Mob Appearance", choices = list("Yes","No","Cancel"))
	switch(whitelist_answer)
		if("Yes")
			log_and_message_admins("has allowed [human_target] to change [human_target.p_their()] appearance, without whitelisting of races.")
			human_target.change_appearance(APPEARANCE_ALL, human_target, check_species_whitelist = 0)
		if("No")
			log_and_message_admins("has allowed [human_target] to change [human_target.p_their()] appearance, with whitelisting of races.")
			human_target.change_appearance(APPEARANCE_ALL, human_target, check_species_whitelist = 1)
	feedback_add_details("admin_verb","CMAS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(editappear, R_FUN, "Edit Appearance", "Edit a human's apperance.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	var/datum/admin_edit_appearance_review/review = new
	rel_set(review, nameof(review.actor), answerer)
	review.client_ckey = user.ckey
	review.ask_next()

/datum/admin_edit_appearance_review
	var/mob/actor
	var/mob/living/carbon/human/target
	var/client_ckey
	var/stage = 0
	var/new_facial
	var/new_hair
	var/new_eyes
	var/new_skin
	var/new_tone
	var/new_hstyle
	var/new_fstyle
	var/new_gender

CAPABILITIES(/datum/admin_edit_appearance_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(target), /mob/living/carbon/human)

/datum/admin_edit_appearance_review/proc/refusal()
	if(QDELETED(actor) || !GLOB.directory[client_ckey])
		return "participant is gone"
	return stage && QDELETED(target) ? "target is gone" : null

/datum/admin_edit_appearance_review/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial request state has no inventory release contract.

/datum/admin_edit_appearance_review/proc/ask_next()
	var/client/user = GLOB.directory[client_ckey]
	rel_set(src, nameof(actor), user.mob)
	switch(stage)
		if(0)
			open_request(src, /datum/prompt/choice/admin_edit_target, PROC_REF(answered), answerer = actor, choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))
		if(1)
			open_request(src, /datum/prompt/choice/admin_edit_confirm, PROC_REF(answered), answerer = actor)
		if(2)
			open_request(src, /datum/prompt/color/admin_edit_new_facial, PROC_REF(answered), answerer = actor)
		if(3)
			open_request(src, /datum/prompt/color/admin_edit_new_hair, PROC_REF(answered), answerer = actor)
		if(4)
			open_request(src, /datum/prompt/color/admin_edit_new_eyes, PROC_REF(answered), answerer = actor)
		if(5)
			open_request(src, /datum/prompt/color/admin_edit_new_skin, PROC_REF(answered), answerer = actor)
		if(6)
			open_request(src, /datum/prompt/number/admin_edit_new_tone, PROC_REF(answered), answerer = actor)
		if(7)
			open_request(src, /datum/prompt/choice/admin_edit_new_hstyle, PROC_REF(answered), answerer = actor, choices = GLOB.hair_styles_list)
		if(8)
			open_request(src, /datum/prompt/choice/admin_edit_new_fstyle, PROC_REF(answered), answerer = actor, choices = GLOB.facial_hair_styles_list)
		if(9)
			open_request(src, /datum/prompt/choice/admin_edit_new_gender, PROC_REF(answered), answerer = actor)

/datum/admin_edit_appearance_review/proc/answered(datum/act/request/context)
	var/datum/result/result = safe_call(PROC_REF(continue_edit), context)
	if(!result.ok)
		stack_trace("[type] continue_edit: [result.error]")
		retire()

/datum/admin_edit_appearance_review/proc/continue_edit(datum/act/request/context)
	if(!context.answer)
		retire()
		return
	switch(stage)
		if(0)
			rel_set(src, nameof(target), context.request.answer_value)
		if(1)
			if(context.request.answer_value != "Yes")
				retire()
				return
		if(2)
			new_facial = context.request.answer_value
		if(3)
			new_hair = context.request.answer_value
		if(4)
			new_eyes = context.request.answer_value
		if(5)
			new_skin = context.request.answer_value
		if(6)
			new_tone = context.request.answer_value
		if(7)
			new_hstyle = context.request.answer_value
		if(8)
			new_fstyle = context.request.answer_value
		if(9)
			new_gender = context.request.answer_value
	stage++
	replay_prefix()
	if(stage < 10)
		ask_next()
		return
	finish_edit()
	retire()

/datum/admin_edit_appearance_review/proc/replay_prefix()
	var/mob/living/carbon/human/target_human = target
	if(stage >= 3 && new_facial)
		target_human.r_facial = hex2num(copytext(new_facial, 2, 4))
		target_human.g_facial = hex2num(copytext(new_facial, 4, 6))
		target_human.b_facial = hex2num(copytext(new_facial, 6, 8))

	if(stage >= 4 && new_hair)
		target_human.r_hair = hex2num(copytext(new_hair, 2, 4))
		target_human.g_hair = hex2num(copytext(new_hair, 4, 6))
		target_human.b_hair = hex2num(copytext(new_hair, 6, 8))

	if(stage >= 5 && new_eyes)
		target_human.r_eyes = hex2num(copytext(new_eyes, 2, 4))
		target_human.g_eyes = hex2num(copytext(new_eyes, 4, 6))
		target_human.b_eyes = hex2num(copytext(new_eyes, 6, 8))
		target_human.update_eyes()

	if(stage >= 6 && new_skin)
		target_human.r_skin = hex2num(copytext(new_skin, 2, 4))
		target_human.g_skin = hex2num(copytext(new_skin, 4, 6))
		target_human.b_skin = hex2num(copytext(new_skin, 6, 8))

	if(stage >= 7 && new_tone)
		target_human.s_tone = max(min(round(text2num(new_tone)), 220), 1)
		target_human.s_tone =  -target_human.s_tone + 35

	// hair
	if(stage >= 8 && new_hstyle)
		target_human.h_style = new_hstyle

	// facial hair
	if(stage >= 9 && new_fstyle)
		target_human.f_style = new_fstyle

	if(stage >= 10 && new_gender)
		target_human.set_gender(new_gender)


/datum/admin_edit_appearance_review/proc/finish_edit()
	var/mob/living/carbon/human/target_human = target
	target_human.update_dna(target_human)
	target_human.update_hair(FALSE)
	target_human.update_icons_body()

/datum/prompt/choice/admin_edit_target
	rights = R_FUN
	timeout = 0
	question = "Select mob."
	title = "Edit Appearance"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_edit_target/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	var/reason = review.refusal()
	if(reason)
		return reason
	if(!isnull(answer_value))
		var/mob/living/carbon/human/picked = answer_value
		return QDELETED(picked) ? "target is gone" : null

/datum/prompt/choice/admin_edit_confirm
	rights = R_FUN
	timeout = 0
	question = "Are you sure you wish to edit this mob's appearance? Skrell, Unathi, Tajaran can result in unintended consequences."
	title = "Danger!"
	choices = list("Yes","No")
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/admin_edit_confirm/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/color/admin_edit_new_facial
	rights = R_FUN
	timeout = 0
	question = "Please select facial hair color."
	title = "Character Generation"
	recheck_on_open = TRUE

/datum/prompt/color/admin_edit_new_facial/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/color/admin_edit_new_hair
	rights = R_FUN
	timeout = 0
	question = "Please select hair color."
	title = "Character Generation"
	recheck_on_open = TRUE

/datum/prompt/color/admin_edit_new_hair/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/color/admin_edit_new_eyes
	rights = R_FUN
	timeout = 0
	question = "Please select eye color."
	title = "Character Generation"
	recheck_on_open = TRUE

/datum/prompt/color/admin_edit_new_eyes/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/color/admin_edit_new_skin
	rights = R_FUN
	timeout = 0
	question = "Please select body color. This is for Tajaran, Unathi, and Skrell only!"
	title = "Character Generation"
	recheck_on_open = TRUE

/datum/prompt/color/admin_edit_new_skin/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/number/admin_edit_new_tone
	rights = R_FUN
	timeout = 0
	question = "Please select skin tone level: 1-220 (1=albino, 35=caucasian, 150=black, 220='very' black)"
	title = "Character Generation"
	min_value = null
	max_value = null
	step = null
	recheck_on_open = TRUE

/datum/prompt/number/admin_edit_new_tone/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/number/admin_edit_new_tone/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, 220, 1, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/choice/admin_edit_new_hstyle
	rights = R_FUN
	timeout = 0
	question = "Select a hair style"
	title = "Grooming"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_edit_new_hstyle/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/choice/admin_edit_new_fstyle
	rights = R_FUN
	timeout = 0
	question = "Select a facial hair style"
	title = "Grooming"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_edit_new_fstyle/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/prompt/choice/admin_edit_new_gender
	rights = R_FUN
	timeout = 0
	question = "Please select gender."
	title = "Character Generation"
	choices = list("Male","Female","Neuter")
	buttons = TRUE
	recheck_on_open = TRUE

/datum/prompt/choice/admin_edit_new_gender/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_edit_appearance_review/review = owner
	return review.refusal()

/datum/admin_verb/change_human_appearance_admin/proc/appearance_target_answered(datum/act/request/context)
	if(!context.answer)
		return
	open_appearance_editor(context)

/datum/admin_verb/change_human_appearance_admin/proc/open_appearance_editor(datum/act/request/context)
	var/mob/living/carbon/human/target_human = context.request.answer_value
	var/mob/user = context.request.answerer
	log_and_message_admins("is altering the appearance of [target_human].", user)
	target_human.change_appearance(APPEARANCE_ALL, user, check_species_whitelist = 0, state = ADMIN_STATE(R_FUN))
	feedback_add_details("admin_verb","CHAA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/prompt/choice/admin_appearance_target
	rights = R_FUN
	timeout = 0
	title = "Change Mob Appearance - Admin"
	question = "Select mob."
	recheck_on_open = TRUE

/datum/prompt/choice/admin_appearance_target/recheck_extra()
	. = ..()
	if(.)
		return
	if(isnull(answer_value))
		return
	if(!istype(answer_value, /mob/living/carbon/human))
		return "The selected human is no longer available."
	var/mob/living/carbon/human/picked = answer_value
	if(QDELETED(picked))
		return "The selected human is no longer available."

