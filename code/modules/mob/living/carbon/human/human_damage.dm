/mob/living/carbon/human/Stun(amount, ignore_canstun = FALSE)
	if(has_mutation(HULK))	return
	..()

/mob/living/carbon/human/Weaken(amount, ignore_canstun = FALSE)
	if(has_mutation(HULK))	return
	..()

/mob/living/carbon/human/Paralyse(amount, ignore_canstun = FALSE)
	if(has_mutation(HULK))	return
	// Notify our AI if they can now control the suit.
	if(wearing_rig && !stat && paralysis < amount) //We are passing out right this second.
		wearing_rig.notify_ai(span_danger("Warning: user consciousness failure. Mobility control passed to integrated intelligence system."))
	..()

// Oxy / tox / clone "damage" for humans is condition severity — see
// code/modules/medical/damage_pools.dm for the adapters.

/mob/living/carbon/human/Stun(amount, ignore_canstun = FALSE)
	if(amount > 0)	//only multiply it by the mod if it's positive, or else it takes longer to fade too!
		amount = amount*species.stun_mod
	..(amount)

/mob/living/carbon/human/SetStunned(amount, ignore_canstun = FALSE)
	..()

/mob/living/carbon/human/AdjustStunned(amount, ignore_canstun = FALSE)
	if(amount > 0) // Only multiply it if positive.
		amount = amount*species.stun_mod
	..(amount)

/mob/living/carbon/human/Weaken(amount, ignore_canstun = FALSE)
	if(amount > 0)	//only multiply it by the mod if it's positive, or else it takes longer to fade too!
		amount = amount*species.weaken_mod
	..(amount)

/mob/living/carbon/human/SetWeakened(amount, ignore_canstun = FALSE)
	..()

/mob/living/carbon/human/AdjustWeakened(amount, ignore_canstun = FALSE)
	if(amount > 0) // Only multiply it if positive.
		amount = amount*species.weaken_mod
	..(amount)

////////////////////////////////////////////

//Returns a list of damaged organs
/mob/living/carbon/human/proc/get_damaged_organs(brute, burn)
	var/list/obj/item/organ/external/parts = list()
	for(var/obj/item/organ/external/O in organs)
		if((brute && O.get_trauma()) || (burn && O.get_burn()))
			parts += O
	return parts

//Returns a list of damageable organs
/mob/living/carbon/human/proc/get_damageable_organs()
	var/list/obj/item/organ/external/parts = list()
	for(var/obj/item/organ/external/O in organs)
		if(O.is_damageable())
			parts += O
	return parts

//Returns a list of fracturable organs
/mob/living/carbon/human/proc/get_fracturable_organs()
	var/list/obj/item/organ/external/parts = list()
	for(var/obj/item/organ/external/O in organs)
		if(O.is_fracturable())
			parts += O
	return parts


/*
This function restores the subjects blood to max.
*/
/mob/living/carbon/human/proc/restore_blood()
	if(!should_have_organ(O_HEART))
		return
	if(vessel.total_volume < species.blood_volume)
		vessel.add_reagent(REAGENT_ID_BLOOD, species.blood_volume - vessel.total_volume)

/*
This function restores all organs.
*/
/mob/living/carbon/human/restore_all_organs(ignore_prosthetic_prefs)
	for(var/obj/item/organ/external/current_organ in organs)
		current_organ.rejuvenate(ignore_prosthetic_prefs)

/*
/mob/living/carbon/human/proc/get_organ(zone)
	if(!zone)
		zone = BP_TORSO
	else if (zone in list( O_EYES, O_MOUTH ))
		zone = BP_HEAD
	return organs_by_name[zone]
*/
