/mob/living/carbon/alien
	name = "alien"
	desc = "What IS that?"
	icon = 'icons/mob/alien.dmi'
	icon_state = "alien"
	pass_flags = PASSTABLE
	endurance = 100
	mob_size = 4
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE


	var/adult_form
	var/dead_icon
	var/amount_grown = 0
	var/max_grown = 200
	EXPIRY_DECLARE(time_of_birth)
	var/language
	var/can_namepick_as_adult = 0
	var/adult_name
	var/instance_num
	gender = NEUTER

// Each is numbered and named for it, knows its kind's language and is stamped with its birth (its CAPABILITIES, alien_damage.dm).
/mob/living/carbon/alien/proc/numbered_name(datum/roller/R)
	return "[initial(name)] ([instance_num])"

/// Its age counts from now (setup()).
/mob/living/carbon/alien/proc/stamp_birth()
	EXPIRY_STAMP(src, time_of_birth, CLOCK_WORLD)

/mob/living/carbon/alien/restrained()
	return 0

/mob/living/carbon/alien/cannot_use_vents()
	return

/mob/living/carbon/alien/get_default_language()
	if(default_language)
		return default_language
	return GLOB.all_languages[LANGUAGE_XENOLINGUA]

/mob/living/carbon/alien/say_quote(message, datum/language/speaking = null)
	var/verb = "hisses"
	var/ending = copytext(message, length(message))

	if(speaking && (speaking.name != "Galactic Common")) //this is so adminbooze xenos speaking common have their custom verbs,
		verb = speaking.get_spoken_verb(ending)          //and use normal verbs for their own languages and non-common languages
	else
		if(ending == "!")
			verb = "roars"
		else if(ending == "?")
			verb = "hisses curiously"
	return verb
