/mob/proc/HasDisease(datum/disease/D)
	for(var/thing in GetViruses())
		var/datum/disease/DD = thing
		if(DD.IsSame(D))
			return TRUE
	return FALSE

/mob/proc/addDisease(datum/disease/D)
	LAZYADD(viruses, D)
	var/mob/living/L = src
	if(istype(L))
		om_changed(L, CHANGE_MOB_CONDITIONS)
	return TRUE

/mob/proc/RemoveDisease(datum/disease/D)
	LAZYREMOVE(viruses, D)
	return TRUE

/mob/proc/HasResistance(resistance)
	if(LAZYFIND(resistances, resistance))
		return TRUE
	return FALSE

/mob/proc/IsInfected()
	if(isemptylist(GetViruses()))
		return FALSE
	return TRUE

/mob/proc/isInfective()
	if(isemptylist(GetSpreadableViruses()))
		return FALSE
	return TRUE

/mob/proc/CanContractDisease(datum/disease/D)
	if(stat == DEAD && !global_flag_check(D.virus_modifiers, SPREAD_DEAD))
		return FALSE

	if(D.GetDiseaseID() in GetResistances())
		return FALSE

	if(HasDisease(D))
		return FALSE

	var/compatible_type = FALSE
	for(var/type_to_test in D.viable_mobtypes)
		if(ispath(type, type_to_test))
			compatible_type = TRUE
			break
	if(!compatible_type)
		return FALSE

	if(isSynthetic())
		if(global_flag_check(D.virus_modifiers, INFECT_SYNTHETICS))
			return TRUE
		return FALSE

	return TRUE

/mob/proc/ContractDisease(datum/disease/D, target_zone)
	if(!CanContractDisease(D))
		return FALSE
	D.try_infect(src)
	return TRUE

/mob/living/carbon/human/ContractDisease(datum/disease/D, target_zone)
	if(!CanContractDisease(D))
		return FALSE

	if(species.virus_immune && !global_flag_check(D.virus_modifiers, BYPASSES_IMMUNITY))
		return FALSE

	var/obj/item/clothing/Cl = null
	var/passed = TRUE

	var/head_chance = 80
	var/body_chance = 100
	var/hands_chance = 35/2
	var/feet_chance = 15/2

	if(prob(15/D.permeability_mod))
		return

/* We have stupid high nutrition values - Something to see about in the future
	if(nutrition > 300 && prob(nutrition/50))
		return
*/

	if(!target_zone)
		target_zone = pick(list(
			BP_HEAD = head_chance,
			BP_TORSO = body_chance,
			BP_R_HAND = hands_chance,
			BP_L_HAND = hands_chance,
			BP_R_FOOT = feet_chance,
			BP_L_FOOT = feet_chance
		))
	else
		target_zone = check_zone(target_zone)

	if(ishuman(src))
		var/mob/living/carbon/human/H = src

		switch(target_zone)
			if(BP_HEAD)
				if(isobj(H.get_equipped_item(SLOT_ID_HEAD)) && !istype(H.get_equipped_item(SLOT_ID_HEAD), /obj/item/paper))
					Cl = H.get_equipped_item(SLOT_ID_HEAD)
					passed = prob((Cl.permeability_coefficient*100) - 1)
				if(passed && isobj(H.get_equipped_item(SLOT_ID_MASK)))
					Cl = H.get_equipped_item(SLOT_ID_MASK)
					passed = prob((Cl.permeability_coefficient*100) - 1)
			if(BP_TORSO)
				if(isobj(H.get_equipped_item(SLOT_ID_SUIT)))
					Cl = H.get_equipped_item(SLOT_ID_SUIT)
					passed = prob((Cl.permeability_coefficient*100) - 1)
				if(passed && isobj(H.get_equipped_item(SLOT_ID_UNIFORM)))
					Cl = H.get_equipped_item(SLOT_ID_UNIFORM)
					passed = prob((Cl.permeability_coefficient*100) - 1)
			if(BP_L_HAND, BP_R_HAND)
				if(isobj(H.get_equipped_item(SLOT_ID_SUIT)) && H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & HANDS)
					Cl = H.get_equipped_item(SLOT_ID_SUIT)
					passed = prob((Cl.permeability_coefficient*100) - 1)

				if(passed && isobj(H.get_equipped_item(SLOT_ID_GLOVES)))
					Cl = H.get_equipped_item(SLOT_ID_GLOVES)
					passed = prob((Cl.permeability_coefficient*100) - 1)
			if(BP_L_FOOT, BP_R_FOOT)
				if(isobj(H.get_equipped_item(SLOT_ID_SUIT)) && H.get_equipped_item(SLOT_ID_SUIT).body_parts_covered & FEET)
					Cl = H.get_equipped_item(SLOT_ID_SUIT)
					passed = prob((Cl.permeability_coefficient*100) - 1)

				if(passed && isobj(H.get_equipped_item(SLOT_ID_SHOES)))
					Cl = H.get_equipped_item(SLOT_ID_SHOES)
					passed = prob((Cl.permeability_coefficient*100) - 1)

	if(passed)
		D.try_infect(src)

/mob/living/proc/AirborneContractDisease(datum/disease/D, force_spread)
	if(((D.spread_flags & DISEASE_SPREAD_AIRBORNE) || force_spread) && prob(50*D.permeability_mod) - 1)
		ForceContractDisease(D)

/mob/living/carbon/AirborneContractDisease(datum/disease/D, force_spread)
	if(internal)
		return
	if(has_mutation(mNobreath))
		return
	..()

/mob/proc/ForceContractDisease(datum/disease/D, respect_carrier)
	if(!CanContractDisease(D))
		return FALSE

	D.infect(src, respect_carrier)
	return TRUE

/mob/living/carbon/human/CanContractDisease(datum/disease/D)
	for(var/organ in D.required_organs)
		if(!((locate(organ) in organs) || (locate(organ) in internal_organs)))
			return FALSE

	if(species.virus_immune && !global_flag_check(D.virus_modifiers, BYPASSES_IMMUNITY))
		D.virus_modifiers |= CARRIER
	else
		D.virus_modifiers &= ~CARRIER

	return ..()

/mob/living/carbon/human/monkey/CanContractDisease(datum/disease/D)
	. = ..()
	if(. == -1)
		if(LAZYFIND(D.viable_mobtypes, /mob/living/carbon/human))
			return

/mob/living/proc/CanSpreadAirborneDisease()
	return !is_mouth_covered()

/datum/life_system/diseases
	name = "diseases"
	phase = LIFE_PHASE_BODY
	order = 50
	segment = LIFE_SEG_LIVING
	woken_by = "addDisease()"

/// Continuous only while the mob carries a virus.
/datum/life_system/diseases/idle(mob/living/self)
	return !self.has_viruses()

/// Virus spread and stages. Runs dead or alive, only while the mob carries a virus.
/datum/life_system/diseases/tick(mob/living/self, datum/life_context/ctx)
	if(self.has_viruses())
		progress(self)

/// Spread and stage every virus this mob carries.
/datum/life_system/diseases/proc/progress(mob/living/self)
	return

/// How many viruses this mob carries, without creating the list.
/mob/proc/has_viruses()
	return LAZYLEN(viruses)

/mob/proc/GetViruses()
	LAZYINITLIST(viruses)
	return viruses

/mob/proc/GetActiveViruses()
	var/list/viruses_to_return = GetViruses()
	viruses_to_return.Remove(GetDormantDiseases())
	return viruses_to_return

/mob/proc/GetSpreadableViruses()
	LAZYINITLIST(viruses)
	var/list/viruses_to_return = list()
	for(var/datum/disease/D in viruses)
		if(D.spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS))
			continue
		viruses_to_return += D
	return viruses_to_return

/mob/proc/GetDormantDiseases()
	LAZYINITLIST(viruses)
	var/list/viruses_to_return = list()
	for(var/datum/disease/D in viruses)
		if(D.virus_modifiers & DORMANT)
			viruses_to_return += D
	return viruses_to_return

/mob/proc/GetResistances()
	LAZYINITLIST(resistances)
	return resistances

/mob/proc/AddResistances(list/resistance)
	LAZYINITLIST(resistances)
	resistances |= resistance
	return TRUE

/mob/proc/check_virus()
	var/threat
	var/danger
	for(var/thing in viruses)
		var/datum/disease/disease = thing
		if(!(disease.visibility_flags & HIDDEN_SCANNER))
			if(!threat || get_disease_danger_value(disease.danger) > threat)
				threat = get_disease_danger_value(disease.danger)
				danger = disease.danger
	return danger

ADMIN_VERB(ReleaseVirus, R_SPAWN|R_EVENT, "Release Virus", "Release a pre-set virus.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/disease = tgui_input_list(user, "Choose virus", "Viruses", subtypesof(/datum/disease), subtypesof(/datum/disease))

	if(isnull(disease))
		return FALSE

	var/mob/living/carbon/human/H = tgui_input_list(user, "Choose infectee", "Characters", GLOB.human_mob_list)

	if(isnull(H))
		return FALSE

	var/datum/disease/D = new disease

	if(!H.HasDisease(D))
		H.ForceContractDisease(D)

		message_admins("[key_name_admin(user)] has triggered a virus outbreak of [D.name]! Affected mob: [key_name_admin(H)]")
		log_admin("[key_name_admin(user)] infected [key_name_admin(H)] with [D.name]")

		if(!GLOB.archive_diseases[D.GetDiseaseID()])
			GLOB.archive_diseases[D.GetDiseaseID()] = D
