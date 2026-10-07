/*	This code is responsible for the examine tab.  When someone examines something, it shows the examined object's generated
	mechanics (its declared interactions, from the resolver, and its properties: get_mechanics_info()), description_fluff
	and description_antag in a new tab. There is no hand-written help text: it could drift from what the code does.

	In this file, some atom and mob stuff is defined here.  It is defined here instead of in the normal files, to keep the whole system self-contained.
	This means that this file can be unchecked, along with the other examine files, and can be removed entirely with no effort.
*/


/atom/
	var/description_fluff = null //Green text about the atom's fluff, if any exists.
	var/description_antag = null //Malicious red text, for the antags.

/**
 * Generated mechanics text: what the atom's properties mean in play (a weapon's
 * damage, armour ratings, a gun's fire modes). Types add lines generated from
 * their vars; what can be *done* with the atom comes from its declared
 * interactions instead (interaction_examine_lines(), screentips).
 * `additional_information` is extra lines from a subtype, listed first.
 */
/atom/proc/get_mechanics_info(list/additional_information)
	if(LAZYLEN(additional_information))
		return jointext(additional_information, "<br>")
	return

/atom/proc/get_description_fluff()
	if(description_fluff)
		return description_fluff
	return

/atom/proc/get_description_antag()
	if(description_antag)
		return description_antag
	return

// This one is slightly different, in that it must return a list.
/atom/proc/get_description_interaction()
	return list()

// Quickly adds the boilerplate code to add an image and padding for the image.
/proc/desc_panel_image(icon_state)
	return "[icon2html(GLOB.description_icons[icon_state], usr)]&emsp;"

/mob/living/get_description_fluff()
	if(flavor_text) //Get flavor text for the green text.
		return flavor_text
	else //No flavor text?  Try for hardcoded fluff instead.
		return ..()

/mob/living/carbon/human/get_description_fluff()
	return print_flavor_text(0)

/* The examine panel itself */

/client/var/description_holders[0]

/client/proc/update_description_holders(atom/A, update_antag_info=0)
	examine_icon = null
	var/list/info = list()
	var/mechanics = A.get_mechanics_info()
	if(mechanics)
		info += mechanics
	if(mob)
		var/list/interaction_lines = interaction_examine_lines(mob, A)
		if(interaction_lines)
			info += interaction_lines
	description_holders["info"] = jointext(info, "<br>")
	description_holders["fluff"] = A.get_description_fluff()
	description_holders["antag"] = (update_antag_info)? A.get_description_antag() : ""
	description_holders["interactions"] = A.get_description_interaction()

	description_holders["name"] = "[A.name]"
	description_holders["icon"] = A
	description_holders["desc"] = A.desc

//override examinate verb to update description holders when things are examined
//mob verbs are faster than object verbs. See http://www.byond.com/forum/?post=1326139&page=2#comment8198716 for why this isn't atom/verb/examine()
/mob/verb/examinate(atom/A as mob|obj|turf in _validate_atom(A))
	set name = "Examine"
	set category = VERB_CAT_IC_GAME

	if((is_blind(src) || src.stat) && !isobserver(src))
		to_chat(src, span_notice("Something is there but you can't see it."))
		return 1

	//Could be gone by the time they finally pick something
	if(!A)
		return 1
	if(!is_paralyzed())
		face_atom(A)
	var/list/results = A.examine(src)
	if(!results || !results.len)
		results = list("You were unable to examine that. Tell a developer!")

	var/list/interaction_lines = interaction_examine_lines(src, A)
	if(interaction_lines)
		results += interaction_lines
	var/list/construction_lines = construction_examine_lines(src, A)
	if(construction_lines)
		results += construction_lines
	results += embedded_info(src, A)

	var/final_string = span_infoplain("[jointext(results, "<br>")]")
	if(ismob(A) || client?.prefs?.read_preference(/datum/preference/choiced/examine_mode) == EXAMINE_MODE_VERBOSE) // mob descriptions matter more than others, & it looks weird to have dropdowns outside the box.
		final_string = examine_block(final_string)
	to_chat(src, final_string)
	update_examine_panel(A)

/proc/embedded_info(mob/source, atom/A)
	. = ""
	if(!(source.client?.prefs?.read_preference(/datum/preference/choiced/examine_mode) == EXAMINE_MODE_VERBOSE))
		return
	if(!source.client?.prefs?.read_preference(/datum/preference/toggle/vchat_enable))
		return //sorry oldchat

	//do pref check here
	var/desc_info_temp = A.get_mechanics_info()
	if(desc_info_temp)
		. += span_details("ℹ️ | Information", desc_info_temp)
	var/fluff_info_temp = A.get_description_fluff()
	if(fluff_info_temp && fluff_info_temp != "")
		var/title = "🪐 | Flavor Information"
		var/examine_text = splittext(fluff_info_temp, "||")
		var/index = 0
		var/rendered_text = ""
		for(var/part in examine_text)
			if(index % 2)
				rendered_text += span_spoiler("[part]")
			else
				rendered_text += "[part]"
			index++
		if(isliving(A)) //ehhh
			var/mob/living/B = A
			if(B.flavor_text)
				title = "🔍 | Flavor Text"

		. += span_details(title, rendered_text)
	var/is_antagish = source.antag_check()
	var/antag_info_temp = A.get_description_antag()
	if(is_antagish && antag_info_temp)
		. += span_details("🏴‍☠️ | Antag Information", antag_info_temp)
	var/list/interaction_info = A.get_description_interaction()
	if(LAZYLEN(interaction_info))
		var/temp = ""
		for(var/a in interaction_info)
			temp += a + "\n"
		. += span_details("🛠️ | Interaction Information",temp)

/mob/proc/antag_check()
	if(mind && (mind.special_role || mind.antag_holder.is_antag())) //We're a /mob and have a mind and antag status.
		return TRUE
	if(isobserver(src)) //We're an observer. We always are able to see stuff antags see.
		return TRUE
	if(get_changeling_state())
		return TRUE
	return FALSE

/mob/proc/update_examine_panel(atom/A)
	if(client)
		var/is_antag = antag_check()
		client.update_description_holders(A, is_antag)
		SSstatpanels.set_examine_tab(client)



/mob/verb/mob_examine()
	set name = "Mob Examine"
	set desc = "Allows one to examine mobs they can see, even from inside of bellies and objects."
	set category = VERB_CAT_IC_GAME
	set popup_menu = FALSE

	return mob_examine_stage(FALSE)

/mob/proc/mob_examine_stage(answered, atom/selected)
	if((is_blind(src) || src.stat) && !isobserver(src))
		to_chat(src, span_notice("Something is there but you can't see it."))
		return 1
	var/list/E = list()
	if(isAI(src))
		var/mob/living/silicon/ai/my_ai = src
		for(var/e in my_ai?.eyes_list())
			var/turf/my_turf = get_turf(e)
			var/foundcam = FALSE
			for(var/obj/cam in view(world.view, my_turf))
				if(istype(cam, /obj/machinery/camera))
					var/obj/machinery/camera/mycam = cam
					if(!mycam.has_condition())
						foundcam = TRUE
			if(!foundcam)
				continue
			for(var/atom/M in view(world.view, my_turf))
				if(M == src || istype(M, /mob/observer))
					continue
				if(ismob(M) && !M.invisibility)
					if(src && src == M)
						var/list/results = src.examine(src)
						if(!results || !results.len)
							results = list("You were unable to examine that. Tell a developer!")
						to_chat(src, jointext(results, "<br>"))
						update_examine_panel(src)
						return
					else
						E |= M
		if(E.len == 0)
			return
	else
		var/my_turf = get_turf(src)
		for(var/atom/M in view(world.view, my_turf))
			if(ismob(M) && M != src && !istype(M, /mob/observer) && !M.invisibility)
				E |= M
		for(var/turf/T in view(world.view, my_turf))
			if(!isopenspace(T))
				continue
			var/turf/checked = T
			var/keepgoing = TRUE
			while(keepgoing)
				var/checking = GetBelow(checked)
				for(var/atom/m in checking)
					if(ismob(m) && !istype(m, /mob/observer) && !m.invisibility)
						E |= m
				checked = checking
				if(!isopenspace(checked))
					keepgoing = FALSE

	if(E.len == 0)
		to_chat(src, span_notice("There are no mobs to examine."))
		return
	var/atom/B = null
	if(E.len == 1)
		B = pick(E)
	else
		if(!answered)
			open_request(src, /datum/prompt/choice/mob_examine_selection, PROC_REF(mob_examine_selected), answerer = src, choices = E)
			return
		B = selected

	if(!B)
		return
	if(!isbelly(loc) && !istype(loc, /obj/item/holder) && !isAI(src))
		if(B.z == src.z && !is_paralyzed())
			face_atom(B)
	var/list/results = B.examine(src)
	if(!results || !results.len)
		results = list("You were unable to examine that. Tell a developer!")
	to_chat(src, jointext(results, "<br>"))
	update_examine_panel(B)

/mob/proc/mob_examine_selected(datum/act/request/A)
	if(!A.answer)
		return
	mob_examine_stage(TRUE, A.answer.value)

/datum/prompt/choice/mob_examine_selection
	question = "What would you like to examine?"
	title = "Examine"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/mob_examine_selection/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer))
		return "gone"
	var/atom/selected = value
	if(!isnull(selected) && QDELETED(selected))
		return "gone"
	return null
