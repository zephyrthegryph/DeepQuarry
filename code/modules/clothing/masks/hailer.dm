/obj/item/clothing/mask/gas/sechailer
	name = "hailer face mask"
	desc = "A compact, durable gas mask that can be connected to an air supply. This one possesses a security hailer."
	icon_state = "halfgas"
	armor_spec = "melee=10;bullet=10;laser=10;bio=55"
	actions_types = list(/datum/action/item_action/halt)
	body_parts_covered = FACE
	var/obj/item/hailer/hailer
	COOLDOWN_DECLARE(hail_cooldown)
	var/phrase = 1
	var/aggressiveness = 1
	var/safety = 1
	var/static/list/phrase_list = list(
		"halt" 			= "HALT! HALT! HALT! HALT!",
		"bobby" 		= "Stop in the name of the Law.",
		"compliance" 	= "Compliance is in your best interest.",
		"justice"		= "Prepare for justice!",
		"running"		= "Running will only increase your sentence.",
		"dontmove"		= "Don't move, Creep!",
		"floor"			= "Down on the floor, Creep!",
		"robocop"		= "Dead or alive you're coming with me.",
		"god"			= "God made today for the crooks we could not catch yesterday.",
		"freeze"		= "Freeze, Scum Bag!",
		"imperial"		= "Stop right there, criminal scum!",
		"bash"			= "Stop or I'll bash you.",
		"harry"			= "Go ahead, make my day.",
		"asshole"		= "Stop breaking the law, asshole.",
		"stfu"			= "You have the right to shut the fuck up",
		"shutup"		= "Shut up crime!",
		"super"			= "Face the wrath of the golden bolt.",
		"dredd"			= "I am, the LAW!"
		)

/obj/item/clothing/mask/gas/sechailer/swat/hos
	name = "\improper HOS SWAT mask"
	desc = "A close-fitting tactical mask with an especially aggressive Compli-o-nator 3000. It has a tan stripe."
	icon_state = "hosmask"


/obj/item/clothing/mask/gas/sechailer/swat/warden
	name = "\improper " + JOB_WARDEN + " SWAT mask"
	desc = "A close-fitting tactical mask with an especially aggressive Compli-o-nator 3000. It has a blue stripe."
	icon_state = "wardenmask"

/obj/item/clothing/mask/gas/sechailer/swat
	name = "\improper SWAT mask"
	desc = "A close-fitting tactical mask with an especially aggressive Compli-o-nator 3000."
	icon_state = "officermask"
	body_parts_covered = HEAD|FACE|EYES
	flags_inv = HIDEFACE|BLOCKHAIR
	aggressiveness = 3
	phrase = 12


/obj/item/clothing/mask/gas/sechailer/ui_action_click(mob/user, actiontype)
	sechailer_halt_verb(user)

CAPABILITIES(/obj/item/clothing/mask/gas/sechailer)
	op("sechailer_phrase_alt", hand(), ungated(), gesture(GESTURE_ALT), label("Select phrase"), then(PROC_REF(sechailer_phrase_alt)))
	op("sechailer_selectphrase_verb", menu(), label("Select gas mask phrase"), needs(carried()), then(PROC_REF(sechailer_selectphrase_verb_op)))
	op("sechailer_halt_verb", menu(), label("HALT!"), needs(carried()), then(PROC_REF(sechailer_halt_verb_op)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/// The sechailer_selectphrase_verb op: the verb's effect, as the old resolver ran it.
/obj/item/clothing/mask/gas/sechailer/proc/sechailer_selectphrase_verb_op(datum/act/op/A)
	sechailer_selectphrase_verb(A.actor, A.held)
	return OP_OK

/// The sechailer_halt_verb op: the verb's effect, as the old resolver ran it.
/obj/item/clothing/mask/gas/sechailer/proc/sechailer_halt_verb_op(datum/act/op/A)
	sechailer_halt_verb(A.actor, A.held)
	return OP_OK

/// Old click_alt. It never reached the clothing alt-click.
/obj/item/clothing/mask/gas/sechailer/proc/sechailer_phrase_alt(datum/act/op/A)
	var/mob/user = A.actor
	sechailer_selectphrase_verb(user)
	return TRUE

/// Old verb "Select gas mask phrase".
/obj/item/clothing/mask/gas/sechailer/proc/sechailer_selectphrase_verb(mob/user, obj/item/held)
	var/key = phrase_list[phrase]
	var/message = phrase_list[key]

	if(!safety) // a fried vocal circuit reads out its one remaining phrase
		to_chat(user, span_notice("You set the restrictor to: FUCK YOUR CUNT YOU SHIT EATING COCKSUCKER MAN EAT A DONG FUCKING ASS RAMMING SHIT FUCK EAT PENISES IN YOUR FUCK FACE AND SHIT OUT ABORTIONS OF FUCK AND DO SHIT IN YOUR ASS YOU COCK FUCK SHIT MONKEY FUCK ASS WANKER FROM THE DEPTHS OF SHIT."))
	else
		switch(aggressiveness)
			if(1)
				phrase = (phrase < 6) ? (phrase + 1) : 1
				key = phrase_list[phrase]
				message = phrase_list[key]
				to_chat(user,span_notice("You set the restrictor to: [message]"))
			if(2)
				phrase = (phrase < 11 && phrase >= 7) ? (phrase + 1) : 7
				key = phrase_list[phrase]
				message = phrase_list[key]
				to_chat(user,span_notice("You set the restrictor to: [message]"))
			if(3)
				phrase = (phrase < 18 && phrase >= 12 ) ? (phrase + 1) : 12
				key = phrase_list[phrase]
				message = phrase_list[key]
				to_chat(user,span_notice("You set the restrictor to: [message]"))
			if(4)
				phrase = (phrase < 18 && phrase >= 1 ) ? (phrase + 1) : 1
				key = phrase_list[phrase]
				message = phrase_list[key]
				to_chat(user,span_notice("You set the restrictor to: [message]"))
			else
				to_chat(user, span_notice("It's broken."))

/obj/item/clothing/mask/gas/sechailer/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(safety)
		safety = 0
		to_chat(user, span_warning("You silently fry [src]'s vocal circuit with the cryptographic sequencer."))
	else
		return OP_DECLINE
	return OP_OK

/obj/item/clothing/mask/gas/sechailer/screwdriver_act(mob/user, obj/item/tool)
	switch(aggressiveness)
		if(1)
			to_chat(user, span_notice("You set the aggressiveness restrictor to the second position."))
			aggressiveness = 2
			phrase = 7
		if(2)
			to_chat(user, span_notice("You set the aggressiveness restrictor to the third position."))
			aggressiveness = 3
			phrase = 13
		if(3)
			to_chat(user, span_notice("You set the aggressiveness restrictor to the fourth position."))
			aggressiveness = 4
			phrase = 1
		if(4)
			to_chat(user, span_notice("You set the aggressiveness restrictor to the first position."))
			aggressiveness = 1
			phrase = 1
		if(5)
			to_chat(user, span_warning("You adjust the restrictor but nothing happens, probably because its broken."))
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/mask/gas/sechailer/wirecutter_act(mob/user, obj/item/tool)
	if(aggressiveness == 5)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_warning("You broke it!"))
	aggressiveness = 5
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/mask/gas/sechailer/crowbar_act(mob/user, obj/item/tool)
	if(!hailer())
		to_chat(user, span_warning("This mask has an integrated hailer, you can't remove it!"))
		return ITEM_INTERACT_BLOCKING
	if(loc?.release_refusal(src, user))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/clothing/mask/gas/half/mask = new(loc)
	playsound(src, tool.usesound, 50, TRUE)
	transfer_blooddna_to(mask)
	transfer_fingerprints_to(mask)
	transfer_fibres_to(mask)
	if(!isturf(mask.loc))
		user.put_in_hands(hailer())
		user.put_in_hands(mask)
	else
		hailer().forceMove(mask.loc)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS

/// Old verb "HALT!".
/obj/item/clothing/mask/gas/sechailer/proc/sechailer_halt_verb(mob/user, obj/item/held)
	var/key = phrase_list[phrase]
	var/message = phrase_list[key]

	if(COOLDOWN_FINISHED(src, hail_cooldown)) // A cooldown, to stop people being jerks
		if(!safety)
			message = "FUCK YOUR CUNT YOU SHIT EATING COCKSUCKER MAN EAT A DONG FUCKING ASS RAMMING SHIT FUCK EAT PENISES IN YOUR FUCK FACE AND SHIT OUT ABORTIONS OF FUCK AND DO SHIT IN YOUR ASS YOU COCK FUCK SHIT MONKEY FUCK ASS WANKER FROM THE DEPTHS OF SHIT."
			act_message(user, null, others = span_infoplain("%U%'s Compli-o-Nator: " + span_red(span_huge(span_bold("[message]")))))
			play_sfx(src, SFX_VOICE_BINSULT, 0.5, extrarange = 4) //Future sound channel = something like SFX
			COOLDOWN_START(src, hail_cooldown, 3.5 SECONDS)
			return

		act_message(user, null, others = span_infoplain("%U%'s Compli-o-Nator: " + span_red(span_huge(span_bold("[message]")))))
		playsound(src, "sound/voice/complionator/[key].ogg", 50, 0, 4) //future sound channel = something like SFX
		COOLDOWN_START(src, hail_cooldown, 3.5 SECONDS)


/obj/item/clothing/mask/gas/sechailer/swat/officer //Just a little nicer to begin with. Can always up the anger with a screwdriver!
	aggressiveness = 1
	phrase = 1

/// the hailer this refers to (a relation view: null once it is deleted).
/obj/item/clothing/mask/gas/sechailer/proc/hailer() as /obj/item/hailer
	return hailer
