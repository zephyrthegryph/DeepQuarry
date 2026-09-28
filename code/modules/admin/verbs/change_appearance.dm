ADMIN_VERB(change_human_appearance_admin, R_FUN, "Change Mob Appearance - Admin", "Allows you to change the mob appearance.", ADMIN_CATEGORY_EVENTS)
	var/mob/living/carbon/human/target_human = verb_ask(user, "a1", args, /datum/om/prompt/choice, message = "Select mob.", title = "Change Mob Appearance - Admin", choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))
	if(isnull(target_human))
		return
	if(!target_human)
		return

	log_and_message_admins("is altering the appearance of [target_human].")
	target_human.change_appearance(APPEARANCE_ALL, usr, check_species_whitelist = 0, state = ADMIN_STATE(R_FUN))
	feedback_add_details("admin_verb","CHAA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

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
	var/mob/living/carbon/human/target_human = verb_ask(user, "a3", args, /datum/om/prompt/choice, message = "Select mob.", title = "Edit Appearance", choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))
	if(isnull(target_human))
		return

	if(!ishuman(target_human))
		to_chat(user, span_warning("You can only do this to humans!"))
		return
	var/_answer_a4 = verb_ask(user, "a4", args, /datum/om/prompt/choice/alert, message = "Are you sure you wish to edit this mob's appearance? Skrell, Unathi, Tajaran can result in unintended consequences.", title = "Danger!", choices = list("Yes","No"))
	if(isnull(_answer_a4))
		return
	if(_answer_a4 != "Yes")
		return
	var/new_facial = verb_ask(user, "a5", args, /datum/om/prompt/color, message = "Please select facial hair color.", title = "Character Generation")
	if(isnull(new_facial))
		return
	if(new_facial)
		target_human.r_facial = hex2num(copytext(new_facial, 2, 4))
		target_human.g_facial = hex2num(copytext(new_facial, 4, 6))
		target_human.b_facial = hex2num(copytext(new_facial, 6, 8))

	var/new_hair = verb_ask(user, "a6", args, /datum/om/prompt/color, message = "Please select hair color.", title = "Character Generation")
	if(isnull(new_hair))
		return
	if(new_hair)
		target_human.r_hair = hex2num(copytext(new_hair, 2, 4))
		target_human.g_hair = hex2num(copytext(new_hair, 4, 6))
		target_human.b_hair = hex2num(copytext(new_hair, 6, 8))

	var/new_eyes = verb_ask(user, "a7", args, /datum/om/prompt/color, message = "Please select eye color.", title = "Character Generation")
	if(isnull(new_eyes))
		return
	if(new_eyes)
		target_human.r_eyes = hex2num(copytext(new_eyes, 2, 4))
		target_human.g_eyes = hex2num(copytext(new_eyes, 4, 6))
		target_human.b_eyes = hex2num(copytext(new_eyes, 6, 8))
		target_human.update_eyes()

	var/new_skin = verb_ask(user, "a8", args, /datum/om/prompt/color, message = "Please select body color. This is for Tajaran, Unathi, and Skrell only!", title = "Character Generation")
	if(isnull(new_skin))
		return
	if(new_skin)
		target_human.r_skin = hex2num(copytext(new_skin, 2, 4))
		target_human.g_skin = hex2num(copytext(new_skin, 4, 6))
		target_human.b_skin = hex2num(copytext(new_skin, 6, 8))

	var/new_tone = verb_ask(user, "a9", args, /datum/om/prompt/number, message = "Please select skin tone level: 1-220 (1=albino, 35=caucasian, 150=black, 220='very' black)", title = "Character Generation", max = 220, min = 1)
	if(isnull(new_tone))
		return

	if (new_tone)
		target_human.s_tone = max(min(round(text2num(new_tone)), 220), 1)
		target_human.s_tone =  -target_human.s_tone + 35

	// hair
	var/new_hstyle = verb_ask(user, "a10", args, /datum/om/prompt/choice, message = "Select a hair style", title = "Grooming", choices = GLOB.hair_styles_list)
	if(isnull(new_hstyle))
		return
	if(new_hstyle)
		target_human.h_style = new_hstyle

	// facial hair
	var/new_fstyle = verb_ask(user, "a11", args, /datum/om/prompt/choice, message = "Select a facial hair style", title = "Grooming", choices = GLOB.facial_hair_styles_list)
	if(isnull(new_fstyle))
		return
	if(new_fstyle)
		target_human.f_style = new_fstyle

	var/new_gender = verb_ask(user, "a12", args, /datum/om/prompt/choice/alert, message = "Please select gender.", title = "Character Generation", choices = list("Male", "Female", "Neuter"))
	if(isnull(new_gender))
		return
	if (new_gender)
		target_human.set_gender(new_gender)

	target_human.update_dna(target_human)
	target_human.update_hair(FALSE)
	target_human.update_icons_body()
