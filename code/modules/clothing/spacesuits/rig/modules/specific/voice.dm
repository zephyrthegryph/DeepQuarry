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

/obj/item/rig_module/voice/Initialize(mapload)
	. = ..()
	voice_holder = new(src)
	voice_holder.active = 0

/obj/item/rig_module/voice/installed()
	..()
	holder.speech = src

/obj/item/rig_module/voice/engage()

	if(!..())
		return 0

	om_prompt(src, usr, list("message" = "Would you like to toggle the synthesiser or set the name?", "choices" = list("Enable","Disable","Set Name","Cancel"), "requires" = PROMPT_CONSCIOUS), PROC_REF(voice_choice_made))
	return 1

/obj/item/rig_module/voice/proc/voice_choice_made(mob/user, choice, datum/om/prompt/ask)
	if(!holder || holder.wearer != user)
		return
	switch(choice)
		if("Enable")
			active = 1
			voice_holder.active = 1
			to_chat(user, span_blue("You enable the speech synthesiser."))
		if("Disable")
			active = 0
			voice_holder.active = 0
			to_chat(user, span_blue("You disable the speech synthesiser."))
		if("Set Name")
			om_prompt(src, user, list("kind" = "text", "message" = "Please enter a new name.", "title" = "Change name", "default" = voice_holder.voice, "max_length" = MAX_NAME_LEN, "requires" = PROMPT_CONSCIOUS), PROC_REF(voice_name_entered))

/obj/item/rig_module/voice/proc/voice_name_entered(mob/user, raw_choice, datum/om/prompt/ask)
	if(!raw_choice || !holder || holder.wearer != user)
		return

REF_OWNED(/obj/item/rig_module/voice, "voice_holder")
	voice_holder.voice = raw_choice
	to_chat(user, span_blue("You are now mimicking <B>[voice_holder.voice]</B>."))
