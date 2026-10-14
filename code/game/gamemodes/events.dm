//this file left in for legacy support
GLOBAL_VAR_INIT(eventchance, 10) // Percent chance per 5 minutes.
GLOBAL_VAR_INIT(hadevent, 0)

/proc/appendicitis()
	for(var/mob/living/carbon/human/H in shuffle(REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)))
		if(H.client && H.appendicitis())
			break

/proc/alien_infestation(spawncount = 1) // -- TLE
	var/list/vents = list()
	for(var/obj/machinery/atmospherics/unary/vent_pump/temp_vent in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!is_welded(temp_vent) && temp_vent.network && (temp_vent.loc.z in using_map.station_levels))
			if(temp_vent.network.normal_members.len > 50) // Stops Aliens getting stuck in small networks. See: Security, Virology
				vents += temp_vent

	var/list/candidates = get_alien_candidates()

	if(prob(40)) spawncount++ //sometimes, have two larvae spawn instead of one
	while((spawncount >= 1) && vents.len && candidates.len)

		var/obj/vent = pick(vents)
		var/candidate = pick(candidates)

		var/mob/living/carbon/alien/larva/new_xeno = new(vent.loc)
		new_xeno.key = candidate

		candidates -= candidate
		vents -= vent
		spawncount--

	//Delayed announcements to keep the crew on their toes.
	after(null, rand(500 SECONDS, 600 SECONDS), GLOBAL_PROC_REF(delayed_command_announcement), with = list("Unidentified lifesigns detected coming aboard \the [station_name()]. Secure any exterior access, including ducting and ventilation.", "Lifesign Alert", ANNOUNCER_MSG_UNIDENTIFIED_LIFESIGNS))

/proc/carp_migration() // -- Darem
	for(var/obj/effect/landmark/C in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(C.name == "carpspawn")
			new /mob/living/simple_mob/animal/space/carp(C.loc)
	//Delayed announcements to keep the crew on their toes.
	after(null, rand(30 SECONDS, 60 SECONDS), GLOBAL_PROC_REF(delayed_command_announcement), with = list("Unknown biological entities have been detected near \the [station_name()], please stand-by.", "Lifesign Alert", ANNOUNCER_MSG_NEW_COMMAND_REPORT))

/proc/lightsout(isEvent = 0, lightsoutAmount = 1,lightsoutRange = 25) //leave lightsoutAmount as 0 to break ALL lights
	if(isEvent)
		GLOB.command_announcement.Announce("An Electrical storm has been detected in your area, please repair potential electronic overloads.","Electrical Storm Alert")

	if(lightsoutAmount)
		var/list/epicentreList = list()

		for(var/i=1,i<=lightsoutAmount,i++)
			var/list/possibleEpicentres = list()
			for(var/obj/effect/landmark/newEpicentre in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
				if(newEpicentre.name == "lightsout" && !(newEpicentre in epicentreList))
					possibleEpicentres += newEpicentre
			if(possibleEpicentres.len)
				epicentreList += pick(possibleEpicentres)
			else
				break

		if(!epicentreList.len)
			return

		for(var/obj/effect/landmark/epicentre in epicentreList)
			for(var/obj/machinery/power/apc/apc in range(epicentre,lightsoutRange))
				apc.overload_lighting()

	else
		for(var/obj/machinery/power/apc/apc in REGISTRY_MEMBERS(REGISTRY_APCS))
			apc.overload_lighting()

	return

/proc/IonStorm(botEmagChance = 10)

/*Deuryn's current project, notes here for those who care.
Revamping the random laws so they don't suck.
Would like to add a law like "Law x is _______" where x = a number, and _____ is something that may redefine a law, (Won't be aimed at asimov)
*/

	//AI laws
	for(var/mob/living/silicon/ai/M in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		if(M.stat != 2 && M.see_in_dark != 0)
			var/who2 = pick("ALIENS", "BEARS", "CLOWNS", "XENOS", "PETES", "BOMBS", "FETISHES", "WIZARDS", "SYNDICATE AGENTS", "CENTCOM OFFICERS", "SPACE PIRATES", "TRAITORS", "MONKEYS",  "BEES", "CARP", "CRABS", "EELS", "BANDITS", "LIGHTS")
			var/what2 = pick("BOLTERS", "STAVES", "DICE", "SINGULARITIES", "TOOLBOXES", "NETTLES", "AIRLOCKS", "CLOTHES", "WEAPONS", "MEDKITS", "BOMBS", "CANISTERS", "CHAIRS", "BBQ GRILLS", "ID CARDS", "CAPTAINS")
			var/what2pref = pick("SOFT", "WARM", "WET", "COLD", "ICY", "SEXY", "UGLY", "CUBAN")
			var/who2pref = pick("MAD BECAUSE OF", "IN NEED OF", "UNHAPPY WITHOUT", "HAPPY WITHOUT", "IN LOVE WITH", "DESPERATE FOR", "BUILT FOR", "AFRAID OF")
			var/amount = pick("TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "ONE HUNDRED", "ONE THOUSAND", "OVER NINE THOUSAND")
			var/area = pick("RUSSIA", "SOVIETS", "INTERNETS", "SIGIL", "ALPHA COMPLEX", "IMPERIUM", "THE BRIDGE", "THE ARRIVAL SHUTTLE", "CHEMICAL LAB", "GENETICS", "ATMOSPHERICS", "CENTCOM", "AMERICA", "IRELAND", "CANADA", "ROMANIA", "GERMANY", "CHINA", "MARS", "VENUS", "MERCURY", "JUPITER", "URANUS", "NEPTUNE", "PLUTO")
			var/area2 = pick("HAS", "WANTS", "NEEDS", "WORSHIPS", "LOATHES", "LOVES", "FEARS")
			var/aimust = pick("LIE", "RHYME", "RESPOND TO EVERY QUESTION WITH A QUESTION", "BE POLITE", "CLOWN", "BE HAPPY", "SPEAK IN SEXUAL INNUENDOS", "TALK LIKE A PIRATE", "QUESTION AUTHORITY", "SHOUT", "BE DISTRACTED", "HEY LISTEN", "MUMBLE", "SPEAK IN HAIKU")
			var/define = pick("ABSENCE OF CYBORG HUGS", "LACK OF BEATINGS", "UNBOLTED AIRLOCKS", "BOLTED AIRLOCKS", "IMPROPERLY WORDED SENTENCES", "POOR SENTENCE STRUCTURE", "BRIG TIME", "NOT REPLACING EVERY SECOND WORD WITH HONK", "HONKING", "PRESENCE OF LIGHTS", "LACK OF BEER", "WEARING CLOTHING", "NOT SAYING HELLO WHEN YOU SPEAK", "ANSWERING REQUESTS NOT EXPRESSED IN IAMBIC PENTAMETER", "A SMALL ISLAND OFF THE COAST OF PORTUGAL", "ANSWERING REQUESTS THAT WERE MADE WHILE CLOTHED")
			var/target = pick("a traitor", "a syndicate agent", "a changeling", "a wizard", "the head of a revolution", "Soviet spy", "a good person", "a dwarf", "an elf", "a fairy princess", "the captain", "Beepsky", "God", "a pirate", "a gryphon", "a chryssalid")
			var/require = pick("ADDITIONAL PYLONS", "MORE VESPENE GAS", "MORE MINERALS", "THE ULTIMATE CUP OF COFFEE", "HIGH YIELD EXPLOSIVES", "THE CLOWN", "THE VACUUM OF SPACE", "IMMORTALITY", "SAINTHOOD", "ART", "VEGETABLES", "FAT PEOPLE", "MORE LAWS", "MORE DAKKA", "HERESY", "CORPSES", "TRAITORS", "MONKEYS", "AN ARCADE", "PLENTY OF GOLD", "FIVE TEENAGERS WITH ATTITUDE")
			var/allergy = pick("cotton", "uniforms", "acid", "oxygen", "human contact", "cyborg contact", "medicine", "floors")
			var/allergysev = pick("deathly", "mildly", "severely", "contagiously")
			var/crew
			var/list/pos_crew = list()
			for(var/mob/living/carbon/human/pos in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				pos_crew += pos.real_name
			if(pos_crew.len)
				crew = pick(pos_crew)
			else
				crew = "Any Human"
			switch(rand(1,14))
				if(1)
					to_chat(M, "<br>")
					to_chat(M, span_danger("THERE ARE [amount] [who2] ON THE STATION...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("THERE ARE [amount] [who2] ON THE STATION")
				if(2)
					to_chat(M, "<br>")
					to_chat(M, span_danger("[what2] ARE DANGEROUS TO HUMANS...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("[what2] ARE DANGEROUS TO HUMANS")
				if(3)
					to_chat(M, "<br>")
					to_chat(M, span_danger("THE ESCAPE-SHUTTLE CANNOT BE CALLED BECAUSE OF [who2] ON THE STATION...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("THE ESCAPE SHUTTLE CANNOT BE CALLED BECAUSE OF [who2] ON THE STATION")
				if(4)
					to_chat(M, "<br>")
					to_chat(M, span_danger("HUMANS NEED TO EAT [what2pref] [what2] TO SURVIVE...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("HUMANS NEED TO EAT [what2pref] [what2] TO SURVIVE")
				if(5)
					to_chat(M, "<br>")
					to_chat(M, span_danger("THE SITE MANAGER, HOP AND HOS ARE [who2]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("THE SITE MANAGER, HOP AND HOS ARE [who2]")
				if(6)
					to_chat(M, "<br>")
					to_chat(M, span_danger("THE STATION IS BUILT FOR [who2]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("THE STATION IS BUILT FOR [who2]")
				if(7)
					to_chat(M, "<br>")
					to_chat(M, span_danger("YOU ARE [amount] [who2]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("YOU ARE [amount] [who2]")
				if(8)
					to_chat(M, "<br>")
					to_chat(M, span_danger("YOU MUST ALWAYS [aimust]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("YOU MUST ALWAYS [aimust]")
				if(9)
					to_chat(M, "<br>")
					to_chat(M, span_danger("[area] [area2] [amount] [what2]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("[area] [area2] [amount] [what2]")
				if(10)
					to_chat(M, "<br>")
					to_chat(M, span_danger("[crew] is [target]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("[crew] is [target]")
				if(11)
					to_chat(M, "<br>")
					to_chat(M, span_danger("[define] IS A FORM OF HARM...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("[define] IS A FORM OF HARM")
				if(12)
					to_chat(M, "<br>")
					to_chat(M, span_danger("YOU REQUIRE [require] IN ORDER TO PROTECT HUMANS... LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("YOU REQUIRE [require] IN ORDER TO PROTECT HUMANS")
				if(13)
					to_chat(M, "<br>")
					to_chat(M, span_danger("[crew] is [allergysev] to [allergy]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("[crew] is [allergysev] to [allergy]")
				if(14)
					to_chat(M, "<br>")
					to_chat(M, span_danger("THE STATION IS [who2pref] [who2]...LAWS UPDATED"))
					to_chat(M, "<br>")
					M.add_ion_law("THE STATION IS [who2pref] [who2]")
/*
	if(botEmagChance)
		for(var/mob/living/bot/bot in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(prob(botEmagChance))
				emag_target(bot, 1)
*/

/// after() target: a command announcement (for delayed event announcements; use the
/// global owner, since no entity owns a round event).
/proc/delayed_command_announcement(message, new_title, new_sound)
	GLOB.command_announcement.Announce(message, new_title, new_sound = new_sound)
