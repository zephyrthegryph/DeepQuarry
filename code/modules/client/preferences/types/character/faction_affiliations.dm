/datum/preference/faction_affiliations
	savefile_key = "faction_affiliations"
	savefile_identifier = PREFERENCE_CHARACTER
	category = "identity"
	group = "affiliations"
	widget = PREF_WIDGET_HIDDEN
	can_randomize = FALSE

/datum/preference/faction_affiliations/create_default_value()
	var/list/result = list()
	for(var/faction_id in GLOB.reputation_factions)
		result[faction_id] = AFFILIATION_NEUTRAL
	return result

/datum/preference/faction_affiliations/pref_deserialize(input, datum/preferences/preferences)
	var/list/result = create_default_value()
	if(!islist(input))
		return result
	var/list/source = input
	var/list/choices = reputation_affiliation_choices()
	for(var/faction_id in GLOB.reputation_factions)
		if(source[faction_id] in choices)
			result[faction_id] = source[faction_id]
	if(reputation_affiliation_total(result) > REPUTATION_AFFILIATION_NET_CAP)
		for(var/faction_id in GLOB.reputation_factions)
			if(reputation_for_affiliation(result[faction_id]) <= 0)
				continue
			result[faction_id] = AFFILIATION_NEUTRAL
			if(reputation_affiliation_total(result) <= REPUTATION_AFFILIATION_NET_CAP)
				break
	return result

/datum/preference/faction_affiliations/pref_serialize(input)
	if(!islist(input))
		return create_default_value()
	var/list/affiliations = input
	return affiliations.Copy()

/datum/preference/faction_affiliations/is_valid(value)
	if(!islist(value))
		return FALSE
	var/list/choices = reputation_affiliation_choices()
	for(var/faction_id in GLOB.reputation_factions)
		if(!(value[faction_id] in choices))
			return FALSE
	return reputation_affiliation_total(value) <= REPUTATION_AFFILIATION_NET_CAP

/datum/preference/faction_affiliations/apply_to_human(mob/living/carbon/human/target, value)
	target.set_faction_affiliations(value)

/datum/preference/faction_affiliations/apply_to_silicon(mob/living/silicon/target, value)
	target.set_faction_affiliations(value)

/datum/preference/faction_affiliations/apply_to_animal(mob/living/simple_mob/target, value)
	target.set_faction_affiliations(value)
