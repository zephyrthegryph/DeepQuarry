/obj/item/paper/talisman
	icon_state = "paper_talisman"
	var/imbue = null
	var/uses = 0
	info = "<center><img src='talisman.png'></center><br/><br/>"

/obj/item/paper/talisman/attack_self(mob/living/user)
	. = ..(user)
	if(.)
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
				supply()
		user.take_organ_damage(5, 0)
		if(src && src.imbue!="supply" && src.imbue!="runestun")
			if(delete)
				qdel(src)
		return
	else
		to_chat(user, "You see strange symbols on the paper. Are they supposed to mean something?")
		return


/obj/item/paper/talisman/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(iscultist(user))
		if(imbue == "runestun")
			user.take_organ_damage(5, 0)
			call(/obj/effect/rune/proc/runestun)(M,user)
			qdel(src)
			return ITEM_INTERACT_SUCCESS
		else
			..()   ///If its some other talisman, use the generic attack code, is this supposed to work this way?
	else
		..()


/obj/item/paper/talisman/proc/supply(key)
	if (!src.uses)
		qdel(src)
		return

	// Talisman rune picker is just a labelled list-of-actions,
	// which is exactly what tgui_input_list is for. Routes the user's
	// pick straight to Topic(rune=<choice>) so the existing handler
	// runs unchanged.
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
	var/picked_label = tgui_input_list(
		usr,
		"There are [uses] bloody runes on the parchment. Choose the chant to imbue into the fabric of reality.",
		"Talisman",
		rune_options,
	)
	if(!picked_label)
		return
	var/rune = rune_options[picked_label]
	if(rune)
		Topic("rune=[rune]", list("rune" = rune))


/obj/item/paper/talisman/Topic(href, href_list)
	if(!src)	return
	if (usr.stat || usr.restrained() || !in_range(src, usr))	return

	if (href_list["rune"])
		switch(href_list["rune"])
			if("newtome")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "newtome"
			if("teleport")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "[pick("ire", "ego", "nahlizet", "certum", "veri", "jatkaa", "balaq", "mgar", "karazet", "geeri", "orkan", "allaq")]"
				T.info = "[T.imbue]"
			if("emp")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "emp"
			if("conceal")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "conceal"
			if("communicate")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "communicate"
			if("runestun")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "runestun"
			if("armor")
				var/obj/item/paper/talisman/T = new /obj/item/paper/talisman(get_turf(usr))
				T.imbue = "armor"
			if("soulstone")
				new /obj/item/soulstone(get_turf(usr))
			if("construct")
				new /obj/structure/constructshell/cult(get_turf(usr))
		src.uses--
		supply()
	return


/obj/item/paper/talisman/supply
	imbue = "supply"
	uses = 5
