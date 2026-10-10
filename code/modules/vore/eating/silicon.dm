/obj/effect/overlay/aiholo
	var/mob/living/silicon/ai/master //This will receive the AI controlling the Hologram. For referencing purposes.
	pass_flags = PASSTABLE | PASSGLASS | PASSGRILLE
	alpha = HOLO_ORIGINAL_ALPHA //Half alpha here rather than in the icon so we can toggle it easily.
	color = HOLO_ORIGINAL_COLOR //This is the blue from icons.dm that it was before.
	desc = "A hologram representing an AI persona."

/// Its bellies go back to the AI before phase 4 clears master.
/obj/effect/overlay/aiholo/lifecycle_prerelease()
	for(var/obj/belly/B in contents_of(src))
		B.forceMove(master)
	return ..()


// stops its walk loop.
/mob/living/silicon/ai/verb/holo_nom()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set name = "Hardlight Nom"
	set category = VERB_CAT_AI_VORE
	set desc = "Wrap up a person in hardlight holograms."

	// Wrong state
	if (!eyeobj || !holo)
		to_chat(src, span_vwarning("You can only use this when holo-projecting!"))
		return

	if(isbelly(loc))
		to_chat(src, span_vwarning("For safety reasons, you cannot consume people with holograms while you are inside someone else."))
		return

	//Holopads have this 'masters' list where the keys are AI names and the values are the hologram effects
	var/obj/effect/overlay/aiholo/hologram = LAZYACCESS(holo.masters, src)

	//Something wrong on holopad
	if(!hologram)
		return

	var/list/possible_prey
	for(var/mob/living/L in oview(1, eyeobj))
		LAZYADD(possible_prey, L)

	if(!LAZYLEN(possible_prey))
		to_chat(src, span_vwarning("There's no one in range to eat."))
		return

	var/mob/living/prey = rerun_ask(src, "a1", VERB_REF(holo_nom), args, /datum/prompt/choice, question = "Select a mob to eat", title = "Holonoms", choices = possible_prey)
	if(isnull(prey))
		return
	if(!prey)
		return //Probably cancelled

	if(!istype(prey))
		to_chat(src, span_vwarning("Invalid mob choice!"))
		return

	hologram.visible_message("[hologram] starts engulfing [prey] in hardlight holograms!")
	to_chat(src, span_vnotice("You begin engulfing [prey] in hardlight holograms.")) //Can't be part of the above, because the above is from the hologram.
	perform_op(eyeobj, prey, "holo_nom", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("holo_ai" = src))

/// The holo nom op runs on the prey (src); the AI's eye is the actor and the AI itself travels as the "holo_ai" value.
/mob/living/proc/holo_nom_finished(datum/act/op/A)
	var/mob/living/silicon/ai/engulfer = A.arg("holo_ai")
	if(!istype(engulfer) || QDELETED(engulfer))
		return OP_FAILED
	engulfer.holo_nom_done(src)
	return OP_OK

/mob/living/silicon/ai/proc/holo_nom_done(mob/living/prey)
	//Didn't move and still projecting and effect exists and no other bellied people
	if(holo && LAZYACCESS(holo.masters, src))
		feed_grabbed_to_self(src, prey)

//This can go here with all the references.
/obj/effect/overlay/aiholo/examine(mob/user)
	. = ..()
	if(master)
		var/flavor_text = master.print_flavor_text()
		if(flavor_text)
			. += "[flavor_text]"

		if(master.identity().ooc_notes)
			. += span_deptradio("OOC Notes:") + "<a href='byond://?src=\ref[master];ooc_notes=1'>\[View\]</a> - <a href='byond://?src=\ref[master];print_ooc_notes_chat=1'>\[Print\]</a>"

// Allow dissipating ai holograms by attacking them
CAPABILITIES(/obj/effect/overlay/aiholo)
	op("aiholo_dissipate_hand", hand(), ungated(), stance(I_HURT), label("Dissipate"), then(PROC_REF(aiholo_dissipate_hand)))
	op("aiholo_dissipate_item", item(/obj/item), stance(I_HURT), label("Dissipate"), then(PROC_REF(aiholo_dissipate_item)))

/// Old attack_hand: a harmful touch dissipates the hologram, then the touch goes on.
/obj/effect/overlay/aiholo/proc/aiholo_dissipate_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	to_chat(user, span_attack("You dissipate [src]."))
	master?.holo?.clear_holo(master)
	return OP_DECLINE

/// Old attackby: a harmful hit dissipates the hologram, then the hit goes on.
/obj/effect/overlay/aiholo/proc/aiholo_dissipate_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	to_chat(user, span_attack("You dissipate [src] with [I]."))
	master?.holo?.clear_holo(master)
	return OP_DECLINE
