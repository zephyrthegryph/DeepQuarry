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
	var/mob/living/carbon/human/target
	var/list/remotes

CAPABILITIES(/obj/machinery/petrification)
	owns_many(nameof(remotes))
	interface("PetrificationInterface")
	op("set_option", ui_act("set_option", arg("option", schema_text(4096))),
		asks(/datum/prompt/color/statue_tint, step = "tint", fields = list("title" = "Statue color", "question" = computed(PROC_REF(tint_question)), "default" = computed(PROC_REF(tint_default))), when = PROC_REF(choosing_tint)),
		asks(/datum/prompt/text/statue_option, step = "text", fields = list("title" = computed(PROC_REF(option_title)), "question" = computed(PROC_REF(option_question)), "default" = computed(PROC_REF(option_default)), "option" = computed(PROC_REF(option_name))), when = PROC_REF(choosing_text)),
		then(PROC_REF(ui_act_set_option)))
	op("petrify", ui_act("petrify"), then(PROC_REF(ui_act_petrify)))
	op("remote", ui_act("remote"), then(PROC_REF(ui_act_remote)))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))

/// Whoever presses a button leaves their prints on the machine.
/obj/machinery/petrification/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

// ALLOW(init/INSTANCE_STATE): offsets onto the wall it faces unless the map placed it
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
	var/datum/trait_state/gargoyle/comp = statue.get_trait_state(/datum/trait_state/gargoyle)
	if (no_clothes)
		for(var/obj/item/W in statue)
			if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))
				continue
			statue.drop_from_inventory(W)

	var/obj/structure/gargoyle/G = new(T, statue, idt, mat, adj, tnt, can_unpetrify, no_clothes)
	G.was_rayed = TRUE

	if (can_unpetrify)
		grant(statue, granted_verb(/mob/living/carbon/human/proc/gargoyle_transformation), G)
		comp?.cooldown = 0
	else
		// A permanent statue: the structure hides the gargoyle verbs for as long as it stands, whoever grants them.
		for(var/granted_path in list(/mob/living/carbon/human/proc/gargoyle_transformation, /mob/living/carbon/human/proc/gargoyle_pause, /mob/living/carbon/human/proc/gargoyle_checkenergy))
			grant(statue, granted_verb(granted_path, hidden = TRUE), G)
		comp?.cooldown = INFINITY

	if (!petrifier)
		visible_message(span_notice("A ray of purple light streams out of \the [src], aimed directly at [statue]. Everywhere the light touches on them quickly [adj] into [mat]."))
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/petrification/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/h = rgb2num(tint)
	data["t"] = ((h[1]*0.299)+(h[2]*0.587)+(h[3]*0.114)) > 102 //0.4 luminance
	data["target"] = "[target_ref() ? target_ref() : "None"]"
	data["can_remote"] = is_valid_target(target_ref()) && istext(material) && istext(identifier) && istext(adjective) && istext(tint)
	data["material"] = material
	data["identifier"] = identifier
	data["adjective"] = adjective
	data["tint"] = tint
	data["able_to_unpetrify"] = able_to_unpetrify
	data["discard_clothes"] = discard_clothes
	return data

/obj/machinery/petrification/proc/set_input(option, mob/user)
	var/static/list/only_these = list("tint","material","identifier","adjective","able_to_unpetrify","discard_clothes","target")
	if (!(option in only_these))
		return
	switch(option)
		if("able_to_unpetrify", "discard_clothes")
			vars[option] = !vars[option] // ALLOW(api): TGUI settings keyed by option name
		if("target")
			var/list/targets = get_viable_targets()
			if (!length(targets))
				popup_msg(user, "No targets within range. Make sure there is a humanoid being within a 3x3 metre square in front of the interface.")
				return
			open_request(src, /datum/prompt/choice/statue_target, PROC_REF(petrify_target_chosen), answerer = user, title = "Petrification Target", question = "Choose the target.", choices = targets)


/obj/machinery/petrification/proc/choosing_tint(datum/act/op/A)
	return A.args["option"] == "tint"

/obj/machinery/petrification/proc/choosing_text(datum/act/op/A)
	return A.args["option"] in list("material", "identifier", "adjective")

/obj/machinery/petrification/proc/tint_question(datum/act/op/A)
	return "Choose the color for the [identifier] to be:"

/obj/machinery/petrification/proc/tint_default(datum/act/op/A)
	return tint

/obj/machinery/petrification/proc/option_name(datum/act/op/A)
	return A.args["option"]

/obj/machinery/petrification/proc/option_title(datum/act/op/A)
	return "Statue [A.args["option"]]"

/obj/machinery/petrification/proc/option_question(datum/act/op/A)
	return "What should the [A.args["option"]] be?"

/obj/machinery/petrification/proc/option_default(datum/act/op/A)
	switch(A.args["option"])
		if("material")
			return material
		if("identifier")
			return identifier
		if("adjective")
			return adjective

/obj/machinery/petrification/proc/tint_chosen(datum/act/op/A)
	var/value = A.step_value("tint")
	if(value)
		tint = value

/datum/prompt/text/statue_option
	max_len = MAX_NAME_LEN
	timeout = 0
	usable_state = "default"
	recheck_on_open = TRUE
	/// "material", "identifier" or "adjective".
	var/option

/obj/machinery/petrification/proc/statue_text_entered(datum/act/op/A)
	var/datum/prompt/text/statue_option/ask = A.step_answer("text")
	if(!ask)
		return
	var/option = ask.option
	var/input = sanitizeSafe(ask.value, 25)
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

/obj/machinery/petrification/proc/petrify_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/ask = A.answer
	var/mob/living/carbon/human/H = ask.choices[ask.value]
	if(!ishuman(H) || !is_valid_target(H))
		return
	open_request(src, /datum/prompt/choice/petrify_consent, PROC_REF(first_confirmed), answerer = H, operator = A.request.answerer, question = "You have been selected as a petrification target. If you press confirm, you will possibly be turned into a statue, and if the option is selected, possibly one that cannot be reverted back from a statue at all.")

/// The chosen target confirms twice; a no or a cancel at either step tells the operator (actor).
/datum/prompt/choice/petrify_consent
	title = "Petrification Target"
	choices = list("Confirm", "Cancel")
	buttons = TRUE
	timeout = 0
	var/mob/operator

CAPABILITIES(/datum/prompt/choice/petrify_consent)
	ref_one(nameof(operator), /mob)

/datum/prompt/choice/petrify_consent/prepare(datum/act/A)
	..()
	var/mob/captured_operator = operator
	rel_clear(src, nameof(operator))
	rel_set(src, nameof(operator), captured_operator)

/datum/prompt/choice/petrify_consent/recheck_extra()
	return QDELETED(operator) ? "gone" : null

/obj/machinery/petrification/proc/first_confirmed(datum/act/request/A)
	var/datum/prompt/choice/petrify_consent/ask = A.request
	var/mob/living/carbon/human/H = ask.answerer
	if(QDELETED(ask.operator) || !istype(H) || QDELETED(H))
		return
	if(!A.answer || ask.value != "Confirm")
		popup_msg(ask.operator, "They declined the request.", FALSE)
		return
	open_request(src, /datum/prompt/choice/petrify_consent, PROC_REF(second_confirmed), answerer = H, operator = ask.operator, question = "This is your last warning, are you -certain-?")

/obj/machinery/petrification/proc/second_confirmed(datum/act/request/A)
	var/datum/prompt/choice/petrify_consent/ask = A.request
	var/mob/living/carbon/human/H = ask.answerer
	if(QDELETED(ask.operator) || !istype(H) || QDELETED(H))
		return
	if(!A.answer || ask.value != "Confirm")
		popup_msg(ask.operator, "They declined the request.", FALSE)
		return
	if(!is_valid_target(H))
		popup_msg(ask.operator, "They declined the request.", FALSE)
		return
	rel_set(src, nameof(target), H)
	SStgui.update_uis(src)

/obj/machinery/petrification/proc/ui_act_set_option(datum/act/op/A, option)
	var/mob/user = A.actor
	if (option)
		switch(option)
			if("tint")
				tint_chosen(A)
			if("material", "identifier", "adjective")
				statue_text_entered(A)
			else
				set_input(option, user)
		SStgui.update_uis(src)
	return TRUE

/obj/machinery/petrification/proc/ui_act_petrify(datum/act/op/A)
	var/mob/user = A.actor
	petrify(user)
	return TRUE

/obj/machinery/petrification/proc/ui_act_remote(datum/act/op/A)
	var/mob/user = A.actor
	if (is_valid_target(target_ref()) && istext(material) && istext(identifier) && istext(adjective) && istext(tint))
		var/obj/item/petrifier/PE = LAZYACCESS(remotes, target_ref())
		if (!QDELETED(PE))
			PE.visible_message(span_warning("\The [PE] disappears!"))
			spent(PE)
		var/obj/item/petrifier/P = new(loc, src)
		P.material = material
		P.identifier = identifier
		P.adjective = adjective
		P.tint = tint
		P.able_to_unpetrify = able_to_unpetrify
		P.discard_clothes = discard_clothes
		rel_set(P, nameof(/datum/accessory_stat_modifier::target), target_ref())
		rel_add(src, nameof(/obj/machinery/petrification::remotes), P, target_ref())
		user.put_in_hands(P)
	return TRUE

/obj/item/paper/petrification_notes
	name = "written notes"
	info = "<font face=\"Times New Roman\">" + span_italics("Found this buried in the machine over there after digging through it a bit- I hooked it up to one of our displays so it was a bit more usable- seems to be a spare part, it was right next to another one that actually " + span_bold("was") + " hooked up. Turns things into other materials, probably one of the components that makes that machine work.") + "</font>"

/// target (a relation view: it reads null once the target is deleted).
/obj/machinery/petrification/proc/target_ref() as /mob/living/carbon/human
	return target

/datum/prompt/color/statue_tint
	timeout = 0
	usable_state = "default"
	recheck_on_open = TRUE

/datum/prompt/color/statue_tint/normalize(given)
	return istext(given) ? given : null

/datum/prompt/color/statue_tint/present(mob/user)
	var/datum/tgui_color_picker/prompt/picker = new(user, question, title || "Pick a color", default || "#000000", timeout, TRUE, GLOB.tgui_always_state)
	rel_set(picker, nameof(picker.prompt), src)
	picker.tgui_interact(user)
	return picker

/// The old name-text normalization stripped tokens without truncating raw submissions.
/datum/prompt/text/statue_option/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/choice/statue_target
	timeout = 0
	usable_state = "default"
	recheck_on_open = TRUE
