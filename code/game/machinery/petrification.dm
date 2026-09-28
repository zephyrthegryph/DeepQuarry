/obj/machinery/petrification
	name = "odd interface"
	desc = "An odd looking machine with an interface, some buttons and a tiny keyboard on the side."
	icon = 'icons/obj/machines/petrification.dmi'
	icon_state = "petrification"

	idle_power_usage = 100
	active_power_usage = 1000
	use_power = USE_POWER_IDLE
	anchored = TRUE
	unacidable = TRUE
	dir = EAST
	var/material = "stone"
	var/identifier = "statue"
	var/adjective = "hardens"
	var/tint = "#ffffff"
	var/able_to_unpetrify = TRUE
	var/discard_clothes = TRUE
	var/target_handle
	var/list/remotes

/obj/machinery/petrification/Initialize(mapload)
	. = ..()
	if(!pixel_x && !pixel_y)
		pixel_x = (dir & 3) ? 0 : (dir == 4 ? 26 : -26)
		pixel_y = (dir & 3) ? (dir == 1 ? 26 : -26) : 0

/obj/machinery/petrification/proc/get_viable_targets()
	var/list/targets = list()
	//dir is the opposite of whichever direction we want to scan
	var/turf/center
	center = get_step(src, turn(dir, 180))
	if (!center)
		return
	//square of 3x3 in front of the device
	for (var/n = center.x-1; n <= center.x+1; n++)
		for (var/m = center.y-1; m <= center.y+1; m++)
			var/turf/T = locate(n,m,z)
			if (!isturf(T))
				continue
			for (var/mob/living/carbon/human/H in turf_contents_of_type(T, /mob/living/carbon/human))
				if (H.stat == DEAD)
					continue
				var/option = "[H]["[H]" != H.real_name ? " ([H.real_name])" : ""]"
				var/r = 1
				if (option in targets)
					while ("[option] ([r])" in targets)
						r += 1
					option = "[option] ([r])"
				targets[option] = H
	return targets

/obj/machinery/petrification/proc/is_valid_target(mob/living/carbon/human/H)
	if (QDELETED(H) || !istype(H) || !H.client)
		return FALSE
	var/turf/T = H.loc
	if (!isturf(T))
		return FALSE
	var/turf/center
	center = get_step(get_turf(src), turn(dir, 180))
	if (!center)
		return
	if (T.z != z || T.x > center.x + 1 || T.x < center.x - 1 || T.y > center.y + 1 || T.y < center.y - 1)
		return FALSE
	return TRUE

/obj/machinery/petrification/proc/popup_msg(mob/user, message, notice = TRUE)
	if (notice)
		message = "A notice pops up on the interface: \"[message]\""
	if (target_ref())
		to_chat(user, span_notice("[message]"))

/obj/machinery/petrification/proc/petrify(mob/user, obj/item/petrifier/petrifier = null)
	. = FALSE
	var/mat = material
	var/idt = identifier
	var/adj = adjective
	var/tnt = tint
	var/can_unpetrify = able_to_unpetrify
	var/no_clothes = discard_clothes
	var/mob/living/carbon/human/statue = target_ref()
	if (petrifier && istype(petrifier))
		mat = petrifier.material
		idt = petrifier.identifier
		adj = petrifier.adjective
		tnt = petrifier.tint
		can_unpetrify = petrifier.able_to_unpetrify
		no_clothes = petrifier.discard_clothes
		statue = petrifier.target_ref()
	if (QDELETED(statue) || !istype(statue))
		popup_msg(user, "Invalid target.")
		return
	if (statue.stat == DEAD)
		popup_msg(user, "The target must be alive.")
		return
	if (!statue.client)
		popup_msg(user, "The target must be capable of conscious thought.")
		return
	if (!istext(mat) || !istext(idt) || !istext(adj) || !istext(tnt))
		popup_msg(user, "Invalid options.")
		return
	var/turf/T = statue.loc
	if (!istype(T))
		popup_msg(user, "They must be visible to the [petrifier ? "device" : "machine"].")
		return
	if (!petrifier)
		var/turf/center = get_step(get_turf(src), turn(dir, 180))
		if (!center)
			return
		if (T.z != z || T.x > center.x + 1 || T.x < center.x - 1 || T.y > center.y + 1 || T.y < center.y - 1)
			popup_msg(user, "They are out of range. They must be standing within a 3x3 square in front of the machine.")
			return
	else
		var/turf/center = get_turf(petrifier)
		if (!center)
			return
		if (T.z != center.z || get_dist(center, T) > 4)
			popup_msg(user, "They are out of range. They must be standing within 4 tiles of the device.")
			return
	var/datum/component/gargoyle/comp = statue.GetComponent(/datum/component/gargoyle)
	if (no_clothes)
		for(var/obj/item/W in statue)
			if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))
				continue
			statue.drop_from_inventory(W)

	var/obj/structure/gargoyle/G = new(T, statue, idt, mat, adj, tnt, can_unpetrify, no_clothes)
	G.was_rayed = TRUE

	if (can_unpetrify)
		add_verb(statue,/mob/living/carbon/human/proc/gargoyle_transformation)
		comp?.cooldown = 0
	else
		remove_verb(statue,/mob/living/carbon/human/proc/gargoyle_transformation)
		remove_verb(statue,/mob/living/carbon/human/proc/gargoyle_pause)
		remove_verb(statue,/mob/living/carbon/human/proc/gargoyle_checkenergy)
		comp?.cooldown = INFINITY

	if (!petrifier)
		visible_message(span_notice("A ray of purple light streams out of \the [src], aimed directly at [statue]. Everywhere the light touches on them quickly [adj] into [mat]."))
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/petrification/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/obj/machinery/petrification/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PetrificationInterface", name)
		ui.open()

/obj/machinery/petrification/tgui_data(mob/user)
	var/list/data = list()
	data["material"] = material
	data["identifier"] = identifier
	data["adjective"] = adjective
	data["tint"] = tint
	var/list/h = rgb2num(tint)
	data["t"] = ((h[1]*0.299)+(h[2]*0.587)+(h[3]*0.114)) > 102 //0.4 luminance
	data["target"] = "[target_ref() ? target_ref() : "None"]"
	data["able_to_unpetrify"] = able_to_unpetrify
	data["discard_clothes"] = discard_clothes
	data["can_remote"] = is_valid_target(target_ref()) && istext(material) && istext(identifier) && istext(adjective) && istext(tint)
	return data

/obj/machinery/petrification/proc/set_input(option, mob/user)
	var/list/only_these = list("tint","material","identifier","adjective","able_to_unpetrify","discard_clothes","target")
	if (!(option in only_these))
		return
	switch(option)
		if("tint")
			om_prompt(src, user, list("kind" = "color", "message" = "Choose the color for the [identifier] to be:", "title" = "Statue color", "default" = tint, "requires" = PROMPT_USABLE), PROC_REF(tint_chosen))
		if("material","identifier","adjective")
			om_prompt(src, user, list("kind" = "text", "message" = "What should the [option] be?", "title" = "Statue [option]", "default" = vars[option], "max_length" = MAX_NAME_LEN, "requires" = PROMPT_USABLE, "data" = list("option" = option)), PROC_REF(statue_text_entered))
		if("able_to_unpetrify", "discard_clothes")
			vars[option] = !vars[option] // ALLOW(api): TGUI settings keyed by option name
		if("target")
			var/list/targets = get_viable_targets()
			if (!length(targets))
				popup_msg(user, "No targets within range. Make sure there is a humanoid being within a 3x3 metre square in front of the interface.")
				return
			om_prompt(src, user, list("kind" = "list", "message" = "Choose the target.", "title" = "Petrification Target", "choices" = targets, "requires" = PROMPT_USABLE, "data" = list("targets" = targets)), PROC_REF(petrify_target_chosen))

/obj/machinery/petrification/proc/tint_chosen(mob/user, new_color, datum/om/prompt/ask)
	if (new_color)
		tint = new_color

/obj/machinery/petrification/proc/statue_text_entered(mob/user, input, datum/om/prompt/ask)
	var/option = ask.get("option")
	input = sanitizeSafe(input, 25)
	if (length(input) <= 0)
		return
	if (option == "adjective")
		if (copytext_char(input, -1) != "s")
			switch(copytext_char(input, -2))
				if ("ss")
					input += "es"
				if ("sh")
					input += "es"
				if ("ch")
					input += "es"
				else
					switch(copytext_char(input, -1))
						if("s", "x", "z")
							input += "es"
						else
							input += "s"
	vars[option] = input // ALLOW(api): TGUI settings keyed by option name

/obj/machinery/petrification/proc/petrify_target_chosen(mob/user, selected, datum/om/prompt/ask)
	var/list/targets = ask.get("targets")
	var/mob/living/carbon/human/H = targets[selected]
	if(!ishuman(H) || !is_valid_target(H))
		return
	om_prompt_sequence(src, H, list(
		list("key" = "confirm", "message" = "You have been selected as a petrification target. If you press confirm, you will possibly be turned into a statue, and if the option is selected, possibly one that cannot be reverted back from a statue at all.", "title" = "Petrification Target", "choices" = list("Confirm", "Cancel")),
		PROC_REF(ask_petrify_certain),
	), PROC_REF(petrify_consent_answered), list("on_cancel" = PROC_REF(petrify_declined), "data" = list("operator" = user)))

/obj/machinery/petrification/proc/ask_petrify_certain(mob/living/carbon/human/H, datum/om/prompt/ask)
	if(ask.get("confirm") == "Confirm")
		return list("key" = "double", "message" = "This is your last warning, are you -certain-?", "title" = "Petrification Target", "choices" = list("Confirm", "Cancel"))

/obj/machinery/petrification/proc/petrify_declined(mob/living/carbon/human/H, datum/om/prompt/ask)
	popup_msg(ask.get("operator"), "They declined the request.", FALSE)

/obj/machinery/petrification/proc/petrify_consent_answered(mob/living/carbon/human/H, datum/om/prompt/ask)
	if(ask.get("confirm") == "Confirm" && ask.get("double") == "Confirm" && is_valid_target(H))
		target_handle = om_handle(H)
		SStgui.update_uis(src)
	else
		popup_msg(ask.get("operator"), "They declined the request.", FALSE)

/obj/machinery/petrification/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	if (ui.user)
		add_fingerprint(ui.user)

	switch(action)
		if("set_option")
			if (params["option"])
				set_input(params["option"], ui.user)
				SStgui.update_uis(src)
			return TRUE
		if("petrify")
			petrify(ui.user)
			return TRUE
		if("remote")
			if (is_valid_target(target_ref()) && istext(material) && istext(identifier) && istext(adjective) && istext(tint))
				var/obj/item/petrifier/PE = LAZYACCESS(remotes, target_ref())
				if (!QDELETED(PE))
					PE.visible_message(span_warning("\The [PE] disappears!"))
					qdel(PE)
				var/obj/item/petrifier/P = new(loc, src)
				P.material = material
				P.identifier = identifier
				P.adjective = adjective
				P.tint = tint
				P.able_to_unpetrify = able_to_unpetrify
				P.discard_clothes = discard_clothes
				P.target_handle = om_handle(target_ref())
				LAZYSET(remotes, target_ref(), P)
				ui.user.put_in_hands(P)
			return TRUE
	return TRUE

/obj/item/paper/petrification_notes
	name = "written notes"
	info = "<font face=\"Times New Roman\">" + span_italics("Found this buried in the machine over there after digging through it a bit- I hooked it up to one of our displays so it was a bit more usable- seems to be a spare part, it was right next to another one that actually " + span_bold("was") + " hooked up. Turns things into other materials, probably one of the components that makes that machine work.") + "</font>"

/// LC-refs: target -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/petrification/proc/target_ref() as /mob/living/carbon/human
	return om_resolve(target_handle)
