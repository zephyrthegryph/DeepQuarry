/obj/item/rig_module/voice

	name = "hardsuit voice synthesiser"
	desc = "A speaker box and sound processor."
	icon_state = "megaphone"
	usable = 1
	selectable = 0
	toggleable = 0
	disruptive = 0

	engage_string = "Configure Synthesiser"

	interface_name = "voice synthesiser"
	interface_desc = "A flexible and powerful voice modulator system."

	var/obj/item/voice_changer/voice_holder

CAPABILITIES(/obj/item/rig_module/voice)
	owns_one(nameof(voice_holder), starts = /obj/item/voice_changer)

/obj/item/rig_module/voice/Initialize(mapload)
	. = ..()
	voice_holder.active = 0

/obj/item/rig_module/voice/installed()
	..()
	rel_set(holder, nameof(holder.speech), src)

/obj/item/rig_module/voice/engage(atom/target, notify_ai, mob/user)

	if(!..())
		return 0

	om_ask(user, /datum/om/prompt/choice/rig_voice, PROC_REF(voice_choice_made))
	return 1

/// Toggling the voice synthesiser or naming it. Re-checked on the answer: conscious, and still
/// wearing the suit the module is in.
/datum/om/prompt/choice/rig_voice
	message = "Would you like to toggle the synthesiser or set the name?"
	buttons = TRUE
	choices = list("Enable","Disable","Set Name","Cancel")
	ask_flags = ASK_CONSCIOUS

/datum/om/prompt/choice/rig_voice/valid()
	var/obj/item/rig_module/voice/module = subject
	return (module.holder && module.holder.wearer() == answerer) ? null : "not wearing the suit"

/datum/prompt/text/rig_voice_name
	title = "Change name"
	question = "Please enter a new name."
	max_len = MAX_NAME_LEN
	name_text = TRUE
	ask_flags = ASK_CONSCIOUS
	timeout = 0

/datum/prompt/text/rig_voice_name/recheck_extra()
	var/obj/item/rig_module/voice/module = owner
	if(!answer_value)
		return "no name"
	return (module.holder && module.holder.wearer() == answerer) ? null : "not wearing the suit"

/obj/item/rig_module/voice/proc/voice_choice_made(datum/om/prompt/choice/rig_voice/ask)
	var/mob/user = ask.answerer
	switch(ask.choice)
		if("Enable")
			active = 1
			voice_holder.active = 1
			to_chat(user, span_blue("You enable the speech synthesiser."))
		if("Disable")
			active = 0
			voice_holder.active = 0
			to_chat(user, span_blue("You disable the speech synthesiser."))
		if("Set Name")
			open_request(src, /datum/prompt/text/rig_voice_name, PROC_REF(voice_name_entered), answerer = user, default = voice_holder.voice)

/obj/item/rig_module/voice/proc/voice_name_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	voice_holder.voice = A.answer.answer_value
	to_chat(user, span_blue("You are now mimicking <B>[voice_holder.voice]</B>."))

