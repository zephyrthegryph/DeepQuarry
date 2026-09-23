/datum/component/rotting_disability
	var/mob/living/carbon/human/owner

/datum/component/rotting_disability/Initialize()
	if (!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

	owner = parent
	RegisterSignal(owner, COMSIG_HANDLE_DISABILITIES, PROC_REF(process_component))

/datum/component/rotting_disability/proc/process_component()
	SIGNAL_HANDLER

	if (QDELETED(parent))
		return
	if(isbelly(owner.loc))
		return
	if(owner.transforming)
		return
	if(prob(2) && prob(3)) // stacked percents for rarity
		// random strange symptoms from organ/limb
		owner.automatic_custom_emote(VISIBLE_MESSAGE, "flinches slightly.", check_stat = TRUE)
		switch(rand(1,4))
			if(1)
				owner.injure(INJURY_TOXIN, rand(2, 8))
			if(2)
				owner.injure(INJURY_CELLULAR, rand(1, 2))
			if(3)
				owner.add_modifier(/datum/modifier/numbness/mild, 3 SECONDS)
			else
				owner.add_oxygen_debt(rand(13, 26), src)
		// external organs need to fall off if damaged enough
		var/obj/item/organ/O = pick(owner.organs)
		if(O && !(O.organ_tag == BP_GROIN || O.organ_tag == BP_TORSO) && istype(O,/obj/item/organ/external))
			var/obj/item/organ/external/E = O
			if(O.damage >= O.min_broken_damage && O.robotic <= ORGAN_ASSISTED && prob(70))
				owner.add_modifier(/datum/modifier/numbness/deep, 3 SECONDS) // what limb? Extreme nerve damage. Can't feel a thing + shock
				E.droplimb(TRUE, DROPLIMB_ACID)

/datum/component/rotting_disability/Destroy(force = FALSE)
	UnregisterSignal(owner, COMSIG_HANDLE_DISABILITIES)
	owner = null
	. = ..()
