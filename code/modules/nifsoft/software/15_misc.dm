/datum/nifsoft/apc_recharge
	name = "APC Connector"
	desc = "A small attachment that allows synthmorphs to recharge themselves from APCs."
	list_pos = NIF_APCCHARGE
	cost = 625
	wear = 2
	applies_to = NIF_SYNTHETIC
	tick_flags = NIF_ACTIVETICK
	var/tmp/obj/machinery/power/apc/apc
	other_flags = (NIF_O_APCCHARGE)

/datum/nifsoft/apc_recharge/activate()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		rel_set(src, "apc", locate_within(get_step(H,H.dir), /obj/machinery/power/apc))
		if(!apc())
			rel_set(src, "apc", locate_within(get_step(H,0), /obj/machinery/power/apc))
		if(!apc())
			nif().notify("You must be facing an APC to connect to.",TRUE)
			om_after(src, 0, PROC_REF(deactivate))
			return FALSE

		act_message(H, null, MSG_SELF(span_notice("Thin snakelike tendrils grow from you and connect to \the [apc()].")), \
			MSG_OTHERS(span_warning("Thin snakelike tendrils grow from %U% and connect to \the [apc()].")))

/datum/nifsoft/apc_recharge/deactivate(force = FALSE)
	if((. = ..()))
		rel_clear(src, "apc")

/datum/nifsoft/apc_recharge/life()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		if(apc() && (get_dist(H,apc()) <= 1) && H.nutrition < 440) // 440 vs 450, life() happens before we get here so it'll never be EXACTLY 450
			H.set_nutrition(min(H.nutrition+10, 450))
			apc().drain_power(7000/450*10) //This is from the large rechargers. No idea what the math is.
			return TRUE
		else
			nif().notify("APC charging has ended.")
			act_message(H, null, MSG_SELF(span_notice("The APC connector tendrils return to your body.")), \
				MSG_OTHERS(span_warning("%U%'s snakelike tendrils whip back into their body from \the [apc()].")))
			deactivate()
			return FALSE

/datum/nifsoft/pressure
	name = "Pressure Seals"
	desc = "Creates pressure seals around important synthetic components to protect them from vacuum. Almost impossible on organics."
	list_pos = NIF_PRESSURE
	cost = 875
	a_drain = 0.5
	wear = 3
	applies_to = NIF_SYNTHETIC
	other_flags = (NIF_O_PRESSURESEAL)

/datum/nifsoft/heatsinks
	name = "Heat Sinks"
	desc = "Advanced heat sinks for internal heat storage of heat on a synth until able to vent it in atmosphere."
	list_pos = NIF_HEATSINK
	cost = 725
	a_drain = 0.25
	wear = 3
	var/used = 0
	tick_flags = NIF_ALWAYSTICK
	applies_to = NIF_SYNTHETIC
	other_flags = (NIF_O_HEATSINKS)

/datum/nifsoft/heatsinks/activate()
	if((. = ..()))
		if(used >= 1500)
			nif().notify("Heat sinks not safe to operate again yet! Max 75% on activation.",TRUE)
			om_after(src, 0, PROC_REF(deactivate))
			return FALSE

/datum/nifsoft/heatsinks/stat_text()
	return "[active ? "Active" : "Disabled"] (Stored Heat: [FLOOR((used/20), 1)]%)"

/datum/nifsoft/heatsinks/life()
	if((. = ..()))
		//Not being used, all clean.
		if(!active && !used)
			return TRUE

		//Being used, and running out.
		else if(active && ++used == 2000)
			nif().notify("Heat sinks overloaded! Shutting down!",TRUE)
			deactivate()

		//Being cleaned, and finishing empty.
		else if(!active && --used == 0)
			nif().notify("Heat sinks re-chilled.")

/datum/nifsoft/compliance
	name = "Compliance Module"
	desc = "A system that allows one to apply 'laws' to sapient life. Extremely illegal, of course."
	list_pos = NIF_COMPLIANCE
	cost = 8200
	wear = 1
	illegal = TRUE
	vended = FALSE
	access = 999 //Prevents anyone from buying it without an emag.
	var/laws = "Be nice to people!"

/datum/nifsoft/compliance/New(newloc,newlaws)
	laws = newlaws //Sanitize before this (the disk does)
	..(newloc)

/datum/nifsoft/compliance/activate()
	if((. = ..()))
		to_chat(nif().human,span_danger("You are compelled to follow these rules:") + "\n" + span_notify("[laws]"))

/datum/nifsoft/compliance/install()
	if((. = ..()))
		to_chat(nif().human,span_danger("You feel suddenly compelled to follow these rules:") + "\n" + span_notify("[laws]"))

/datum/nifsoft/compliance/uninstall()
	nif().notify("ERROR! Unable to comply!",TRUE)
	return FALSE //NOPE.

/datum/nifsoft/compliance/stat_text()
	return "Show Laws"

/datum/nifsoft/sizechange
	name = "Mass Alteration"
	desc = "A system that allows one to change their size, through drastic mass rearrangement. Causes significant wear when installed."
	list_pos = NIF_SIZECHANGE
	cost = 300
	wear = 0.5

/datum/nifsoft/sizechange/activate()
	if((. = ..()))
		var/new_size = rerun_ask(usr, "k128", PROC_REF(activate), args, /datum/om/prompt/number, message = "Put the desired size (25-200%), or (1-600%) in dormitory areas.", title = "Set Size", default = 200, max = 600, min = 1)
		if(isnull(new_size))
			return

		if (!nif().human.size_range_check(new_size))
			if(new_size)
				to_chat(nif().human,span_notice("The safety features of the NIF Program prevent you from choosing this size."))
			return
		else
			if(nif().human.resize(new_size/100, uncapped=nif().human.has_large_resize_bounds(), ignore_prefs = TRUE))
				to_chat(nif().human,span_notice("You set the size to [new_size]%"))
				nif().human.visible_message(span_warning("Swirling grey mist envelops [nif().human] as they change size!"),span_notice("Swirling streams of nanites wrap around you as you change size!"))
		om_after(src, 0, PROC_REF(deactivate))

/datum/nifsoft/sizechange/deactivate(force = FALSE)
	if((. = ..()))
		return TRUE

/datum/nifsoft/sizechange/stat_text()
	return "Change Size"

/datum/nifsoft/worldbend
	name = "World Bender"
	desc = "Alters your perception of various objects in the world. Only has one setting for now: displaying all your crewmates as farm animals."
	list_pos = NIF_WORLDBEND
	cost = 100
	a_drain = 0.01

/datum/nifsoft/worldbend/activate()
	if((. = ..()))
		var/list/justme = list(nif().human)
		for(var/human in REGISTRY_MEMBERS(REGISTRY_HUMANS))
			if(human == nif().human)
				continue
			var/mob/living/carbon/human/H = human
			H.display_alt_appearance("animals", justme)
			registry_join(REGISTRY_ALT_FARMANIMALS, nif().human)

/datum/nifsoft/worldbend/deactivate(force = FALSE)
	if((. = ..()))
		var/list/justme = list(nif().human)
		for(var/human in REGISTRY_MEMBERS(REGISTRY_HUMANS))
			if(human == nif().human)
				continue
			var/mob/living/carbon/human/H = human
			H.hide_alt_appearance("animals", justme)
			registry_leave(REGISTRY_ALT_FARMANIMALS, nif().human)

/datum/nifsoft/malware
	name = "Cool Kidz Toolbar"
	desc = "Best toolbar in business since 2098."
	list_pos = NIF_MALWARE
	cost = 1987
	wear = 0
	illegal = TRUE
	vended = FALSE
	tick_flags = NIF_ALWAYSTICK
	EXPIRY_DECLARE(last_ads)
	can_uninstall = FALSE

/datum/nifsoft/malware/activate()
	if((. = ..()))
		to_chat(nif().human,span_danger("Runtime error in 15_misc.dm, line 191."))

/datum/nifsoft/malware/install()
	if((. = ..()))
		EXPIRY_STAMP(src, last_ads, CLOCK_WORLD)

/datum/nifsoft/malware/life()
	if((. = ..()))
		if(nif().human.client && ELAPSED(src, last_ads, CLOCK_WORLD) > rand(10 MINUTES, 15 MINUTES) && prob(1))
			EXPIRY_STAMP(src, last_ads, CLOCK_WORLD)
			nif().human.client.create_fake_ad_popup_multiple(/atom/movable/screen/popup/default, 5)

/// LC-refs: the apc this refers to -- a relation view: null once it is deleted.
/datum/nifsoft/apc_recharge/proc/apc() as /obj/machinery/power/apc
	return apc
