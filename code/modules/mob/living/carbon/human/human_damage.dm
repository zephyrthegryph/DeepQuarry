// Oxy / tox / clone "damage" for humans is condition severity — see
// code/modules/medical/damage_pools.dm for the adapters.

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
