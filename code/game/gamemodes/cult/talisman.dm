/obj/item/paper/talisman
	icon_state = "paper_talisman"
	var/imbue = null
	var/uses = 0
	info = "<center><img src='talisman.png'></center><br/><br/>"

// Its own self-use ops come before the paper's (the old EXTEND listed the child's specs first).
CAPABILITIES(/obj/item/paper/talisman)
	op("talisman_crumple", in_hand(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Crumple"), then(PROC_REF(talisman_crumple_op)))
	op("talisman_invoke", in_hand(), priority(OP_PRIORITY_DEFAULT - 2), label("Invoke"), then(PROC_REF(talisman_invoke_op)))

/obj/item/paper/talisman/proc/talisman_crumple_op(datum/act/op/A)
	talisman_use(A.actor, I_HURT)
	return OP_OK

/obj/item/paper/talisman/proc/talisman_invoke_op(datum/act/op/A)
	talisman_use(A.actor, I_HELP)
	return OP_OK

/// Old attack_self: the paper's own self-use (read or crumple), then the talisman's effect.
/obj/item/paper/talisman/proc/talisman_use(mob/living/user, stance)
	paper_use(user, stance)
	if(QDELETED(src))
		return TRUE
	if(iscultist(user))
		var/delete = 1
		// who the hell thought this was a good idea :(
		switch(imbue)
			if("newtome")
				call(/obj/effect/rune/proc/tomesummon)(user)
			if("armor")
				call(/obj/effect/rune/proc/armor)(user)
			if("emp")
				call(/obj/effect/rune/proc/emp)(user.loc,3,user)
			if("conceal")
				call(/obj/effect/rune/proc/obscure)(2,user)
			if("revealrunes")
				call(/obj/effect/rune/proc/revealrunes)(src,user)
			if("ire", "ego", "nahlizet", "certum", "veri", "jatkaa", "balaq", "mgar", "karazet", "geeri")
				call(/obj/effect/rune/proc/teleport)(imbue,user)
			if("communicate")
				//If the user cancels the talisman this var will be set to 0
				delete = call(/obj/effect/rune/proc/communicate)(user)
			if("deafen")
				call(/obj/effect/rune/proc/deafen)(user)
			if("blind")
				call(/obj/effect/rune/proc/blind)(user)
			if("runestun")
				to_chat(user, span_warning("To use this talisman, attack your target directly."))
				return
			if("supply")
				supply(null, user)
		user.injure(INJURY_BLUNT, 5)
		if(src && src.imbue!="supply" && src.imbue!="runestun")
			if(delete)
				consume(src, user)
		return
	else
		to_chat(user, "You see strange symbols on the paper. Are they supposed to mean something?")
		return


/obj/item/paper/talisman/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(iscultist(user))
		if(imbue == "runestun")
			user.injure(INJURY_BLUNT, 5)
			call(/obj/effect/rune/proc/runestun)(M,user)
			consume(src, user)
			return ITEM_INTERACT_SUCCESS
		else
			..()   ///If its some other talisman, use the generic attack code, is this supposed to work this way?
	else
		..()


/obj/item/paper/talisman/proc/supply(key, mob/user)
	if (!src.uses)
		spent(src, user)
		return

	// Talisman rune picker is just a labelled list-of-actions; the pick goes to imbue_rune().
	var/static/list/rune_options = list(
		"N'ath reth sh'yro eth d'raggathnor! — summon a new arcane tome" = "newtome",
		"Sas'so c'arta forbici! — move to a rune with the same last word" = "teleport",
		"Ta'gh fara'qha fel d'amar det! — destroy technology in a short range" = "emp",
		"Kla'atu barada nikt'o! — conceal the runes you placed on the floor" = "conceal",
		"O bidai nabora se'sma! — coordinate with others of your cult" = "communicate",
		"Fuu ma'jin — stun a person by attacking them with the talisman" = "runestun",
		"Sa tatha najin — summon armoured robes and an unholy blade" = "armor",
		"Kal om neth — summon a soul stone" = "soulstone",
		"Da A'ig Osk — summon a construct shell" = "construct",
	)
	open_request(src, /datum/prompt/choice/talisman_chant, PROC_REF(talisman_chant_chosen), answerer = user, title = "Talisman", question = "There are [uses] bloody runes on the parchment. Choose the chant to imbue into the fabric of reality.", choices = rune_options)

/obj/item/paper/talisman/proc/talisman_chant_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/talisman_chant/ask = context.answer
	var/rune = ask.choices[ask.value]
	if(rune && uses > 0)
		imbue_rune(ask.answerer, rune)


/// Makes the chosen talisman (the user must still hold and be able to use this one).
/obj/item/paper/talisman/proc/imbue_rune(mob/user, rune)
	if(!user || user.stat || user.restrained() || !in_range(src, user))
		return
	var/turf/T = get_turf(user)
	switch(rune)
		if("newtome")
			var/obj/item/paper/talisman/new_talisman = new /obj/item/paper/talisman(T)
			new_talisman.imbue = "newtome"
		if("teleport")
			var/obj/item/paper/talisman/new_talisman = new /obj/item/paper/talisman(T)
			new_talisman.imbue = "[pick("ire", "ego", "nahlizet", "certum", "veri", "jatkaa", "balaq", "mgar", "karazet", "geeri", "orkan", "allaq")]"
			new_talisman.info = "[new_talisman.imbue]"
		if("emp", "conceal", "communicate", "runestun", "armor")
			var/obj/item/paper/talisman/new_talisman = new /obj/item/paper/talisman(T)
			new_talisman.imbue = rune
		if("soulstone")
			new /obj/item/soulstone(T)
		if("construct")
			new /obj/structure/constructshell/cult(T)
		else
			return
	src.uses--
	supply(null, user)


/obj/item/paper/talisman/supply
	imbue = "supply"
	uses = 5

/datum/prompt/choice/talisman_chant
	timeout = 0
	recheck_on_open = TRUE
	ask_flags = ASK_CARRIED | ASK_CAPABLE
