/obj/machinery/wish_granter
	name = "Wish Granter"
	desc = "You're not so sure about this, anymore..."
	icon = 'icons/obj/device.dmi'
	icon_state = "syndbeacon"

	anchored = 1
	density = 1
	use_power = USE_POWER_OFF

	var/chargesa = 1
	var/insistinga = 0



TRACKED(/obj/machinery/wish_granter, chargesa)
TRACKED(/obj/machinery/wish_granter, insistinga)

CAPABILITIES(/obj/machinery/wish_granter)
	op("wish_touch", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Touch"), asks(/datum/prompt/choice/wish_granter, fields = list("title" = "Wish", "question" = "You want...", "choices" = list("Power", "Wealth", "Immortality", "To Kill", "Peace"), "timeout" = 0), when = PROC_REF(wish_ready)), then(PROC_REF(interaction_touch)))

/obj/machinery/wish_granter/proc/interaction_touch(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	if(A.answer)
		return wish_chosen(A)
	if(chargesa <= 0)
		to_chat(user, span_infoplain("The Wish Granter lies silent."))
		return

	else if(!ishuman(user))
		to_chat(user, span_infoplain("You feel a dark stirring inside of the Wish Granter, something you want nothing of. Your instincts are better than any man's."))
		return

	else if(is_special_character(user))
		to_chat(user, span_infoplain("Even to a heart as dark as yours, you know nothing good will come of this.  Something instinctual makes you pull away."))

	else if (!insistinga)
		to_chat(user, span_infoplain("Your first touch makes the Wish Granter stir, listening to you.  Are you really sure you want to do this?"))
		set_insistinga(insistinga + 1)

	return OP_OK

/obj/machinery/wish_granter/proc/wish_chosen(datum/act/op/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/user = A.actor
	switch(A.answer.value)
		if("Power")
			to_chat(user, span_boldwarning("Your wish is granted, but at a terrible cost..."))
			to_chat(user, span_warning("The Wish Granter punishes you for your selfishness, claiming your soul."))
			if (!(user.has_mutation(LASER_EYES)))
				user.add_mutation(LASER_EYES)
				to_chat(user, span_notice("You feel pressure building behind your eyes."))
			if (!(user.has_mutation(COLD_RESISTANCE)))
				user.add_mutation(COLD_RESISTANCE)
				to_chat(user, span_notice("Your body feels warm."))
			if (!(user.has_mutation(XRAY)))
				user.add_mutation(XRAY)
				user.sight |= (SEE_MOBS|SEE_OBJS|SEE_TURFS)
				user.see_in_dark = 8
				user.see_invisible = SEE_INVISIBLE_LEVEL_TWO
				to_chat(user, span_notice("The walls suddenly disappear."))
		if("Wealth")
			to_chat(user, span_boldwarning("Your wish is granted, but at a terrible cost..."))
			to_chat(user, span_warning("The Wish Granter punishes you for your selfishness, claiming your soul."))
			new /obj/structure/closet/syndicate/resources/everything(loc)
		if("To Kill")
			to_chat(user, span_boldwarning("Your wish is granted, but at a terrible cost..."))
			to_chat(user, span_danger("The Wish Granter is outraged at your excessive wickedness, yet grants you your wish regardless. Someone will be killed soon."))
			after(src, 10 SECONDS, PROC_REF(gib_wisher), with = list(user))
		if("Peace")
			to_chat(user, span_infoplain(span_bold("Whatever alien sentience that the Wish Granter possesses is satisfied with your wish. There is a distant wailing as the last of the Faithless begin to die, then silence.")))
			to_chat(user, span_infoplain("You feel as if you just narrowly avoided a terrible fate..."))
			for(var/mob/living/simple_mob/faithless/F in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
				F.set_stat(DEAD)
				F.icon_state = "faithless_dead"

/obj/machinery/wish_granter/proc/gib_wisher(mob/living/carbon/human/user)
	if(user)
		to_chat(user, span_bolddanger("Suddenly, you feel as though you are being torn to countless shreds! Your wish is coming true!"))
		user.gib()

/obj/machinery/wish_granter/proc/wish_ready(datum/act/op/A)
	return chargesa > 0 && insistinga && ishuman(A.actor)

/// The original second touch spends its charge when the question opens, even if cancelled.
/datum/prompt/choice/wish_granter
	var/selection_ready = FALSE
	var/readiness_refusal
	recheck_on_open = TRUE

/datum/prompt/choice/wish_granter/prepare(datum/act/A)
	..()
	var/obj/machinery/wish_granter/W = owner
	if(!istype(W))
		return
	if(is_special_character(answerer))
		readiness_refusal = "Even to a heart as dark as yours, you know nothing good will come of this.  Something instinctual makes you pull away."
		return
	W.set_chargesa(W.chargesa - 1)
	W.set_insistinga(0)
	selection_ready = TRUE

/datum/prompt/choice/wish_granter/recheck_extra()
	if(!selection_ready)
		return readiness_refusal || "the wish granter is unavailable"
	return null
