#define GET_TARGET_PRONOUN(target, pronoun, gender) call(target, ALL_PRONOUNS[pronoun])(gender)

// ATOM GENDER DEFAULTS
// Only atoms (and clients, below) have pronouns. They are not /datum procs: BYOND keeps a proc-table slot for every inherited proc of every type,
// so each /datum proc costs about 1 MB across the ~45 k datum types that never use it.

/atom/proc/p_they(temp_gender)
	return "it"

/atom/proc/p_They(temp_gender)
	return capitalize(p_they(temp_gender))

/atom/proc/p_their(temp_gender)
	return "its"

/atom/proc/p_Their(temp_gender)
	return capitalize(p_their(temp_gender))

/atom/proc/p_theirs(temp_gender)
	return "its"

/atom/proc/p_Theirs(temp_gender)
	return capitalize(p_theirs(temp_gender))

/atom/proc/p_them(temp_gender)
	return "it"

/atom/proc/p_Them(temp_gender)
	return capitalize(p_them(temp_gender))

/atom/proc/p_have(temp_gender)
	return "has"

/atom/proc/p_are(temp_gender)
	return "is"

/atom/proc/p_were(temp_gender)
	return "was"

/atom/proc/p_do(temp_gender)
	return "does"

/atom/proc/p_theyve(temp_gender)
	return p_they(temp_gender) + "'" + copytext_char(p_have(temp_gender), 3)

/atom/proc/p_Theyve(temp_gender)
	return p_They(temp_gender) + "'" + copytext_char(p_have(temp_gender), 3)

/atom/proc/p_theyre(temp_gender)
	return p_they(temp_gender) + "'" + copytext_char(p_are(temp_gender), 2)

/atom/proc/p_Theyre(temp_gender)
	return p_They(temp_gender) + "'" + copytext_char(p_are(temp_gender), 2)

/atom/proc/p_s(temp_gender)
	return "s"

/atom/proc/p_es(temp_gender)
	return "es"

/atom/proc/p_themselves(temp_gender)
	return "itself"

/proc/plural_s(datum/source, pluralize)
	switch(copytext_char(pluralize, -2))
		if("ss")
			return "es"
		if("sh")
			return "es"
		if("ch")
			return "es"
		else
			switch(copytext_char(pluralize, -1))
				if("s", "x", "z")
					return "es"
				else
					return "s"

/// A proc to replace pronouns in a string with the appropriate pronouns for a target atom.
/// Uses associative list access from a __DEFINE list, since associative access is slightly faster
/atom/proc/REPLACE_PRONOUNS(target_string, atom/targeted_atom, targeted_gender = null)
	/// If someone specifies targeted_gender we choose that,
	/// otherwise we go off the gender of our object
	var/gender
	if(targeted_gender)
		if(!istext(targeted_gender) || !(targeted_gender in list(MALE, FEMALE, PLURAL, NEUTER, HERM)))
			stack_trace("REPLACE_PRONOUNS called with improper parameters.")
			return
		gender = targeted_gender
	else
		gender = targeted_atom.get_visible_gender()
	///The pronouns are ordered by their length to avoid %PRONOUN_Theyve being translated to "Heve" instead of "He's", for example
	var/regex/pronoun_regex = regex("%PRONOUN(_(theirs|Theirs|theyve|Theyve|theyre|Theyre|their|Their|they|They|them|Them|have|were|are|do|es|s))")
	while(pronoun_regex.Find(target_string))
		target_string = pronoun_regex.Replace(target_string, GET_TARGET_PRONOUN(targeted_atom, pronoun_regex.match, gender))
	return target_string

// CLIENT GENDER

/client/proc/p_they(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	switch(temp_gender)
		if(FEMALE)
			return "she"
		if(MALE)
			return "he"
		if(NEUTER)
			return "it"
		if(HERM)
			return "shi"
		else
			return "they"

/client/proc/p_their(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	switch(temp_gender)
		if(FEMALE)
			return "her"
		if(MALE)
			return "his"
		if(NEUTER)
			return "its"
		if(HERM)
			return "hir"
		else
			return "their"

/client/proc/p_theirs(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	switch(temp_gender)
		if(FEMALE)
			return "hers"
		if(MALE)
			return "his"
		if(NEUTER)
			return "its"
		if(HERM)
			return "hirs"
		else
			return "theirs"

/client/proc/p_them(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	switch(temp_gender)
		if(FEMALE)
			return "her"
		if(MALE)
			return "him"
		if(NEUTER)
			return "it"
		if(HERM)
			return "hir"
		else
			return "them"

/client/proc/p_have(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	if(temp_gender == PLURAL)
		return "have"
	return "has"

/client/proc/p_are(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	if(temp_gender == PLURAL)
		return "are"
	return "is"

/client/proc/p_were(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	if(temp_gender == PLURAL)
		return "were"
	return "was"

/client/proc/p_do(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	if(temp_gender == PLURAL)
		return "do"
	return "does"

/client/proc/p_s(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	if(temp_gender != PLURAL)
		return "s"

/client/proc/p_es(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	if(temp_gender != PLURAL && temp_gender != NEUTER)
		return "es"

/client/proc/p_themselves(temp_gender)
	if(!temp_gender)
		temp_gender = read_once(gender)
	switch(temp_gender)
		if(FEMALE)
			return "herself"
		if(MALE)
			return "himself"
		if(PLURAL)
			return "themselves"
		if(HERM)
			return "hirself"
		else
			return "itself"

// MOB GENDER

/mob/p_they(temp_gender)
	if(!temp_gender)
		temp_gender = gender // a pronoun is the gender the mob has when it is said
	switch(temp_gender)
		if(FEMALE)
			return "she"
		if(MALE)
			return "he"
		if(PLURAL)
			return "they"
		if(HERM)
			return "shi"
		else
			return "it"

/mob/p_their(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "her"
		if(MALE)
			return "his"
		if(PLURAL)
			return "their"
		if(HERM)
			return "hir"
		else
			return "its"

/mob/p_theirs(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "hers"
		if(MALE)
			return "his"
		if(PLURAL)
			return "theirs"
		if(HERM)
			return "hirs"
		else
			return "its"

/mob/p_them(capitalized, temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "her"
		if(MALE)
			return "him"
		if(PLURAL)
			return "them"
		if(HERM)
			return "hir"
		else
			return "it"

/mob/p_have(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "have"
	return "has"

/mob/p_are(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "are"
	return "is"

/mob/p_were(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "were"
	return "was"

/mob/p_do(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "do"
	return "does"

/mob/p_s(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender != PLURAL)
		return "s"

/mob/p_es(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender != PLURAL)
		return "es"

/mob/p_themselves(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "herself"
		if(MALE)
			return "himself"
		if(PLURAL)
			return "themselves"
		if(HERM)
			return "hirself"
		else
			return "itself"

// ATOM GENDER

/atom/p_they(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "she"
		if(MALE)
			return "he"
		if(PLURAL)
			return "they"
		if(HERM)
			return "shi"
		else
			return "it"

/atom/p_their(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "her"
		if(MALE)
			return "his"
		if(PLURAL)
			return "their"
		if(HERM)
			return "hir"
		else
			return "its"

/atom/p_theirs(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "hers"
		if(MALE)
			return "his"
		if(PLURAL)
			return "theirs"
		if(HERM)
			return "hirs"
		else
			return "its"

/atom/p_them(capitalized, temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "her"
		if(MALE)
			return "him"
		if(PLURAL)
			return "them"
		if(HERM)
			return "hir"
		else
			return "it"

/atom/p_have(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "have"
	return "has"

/atom/p_are(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "are"
	return "is"

/atom/p_were(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "were"
	return "was"

/atom/p_do(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "do"
	return "does"

/atom/p_s(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender != PLURAL)
		return "s"

/atom/p_es(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender != PLURAL)
		return "es"

/atom/p_themselves(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "herself"
		if(MALE)
			return "himself"
		if(PLURAL)
			return "themselves"
		if(HERM)
			return "hirself"
		else
			return "itself"

/atom/proc/get_visible_gender(mob/user, force)
	return gender

// CARBON GENDER

/mob/living/carbon/human/get_visible_gender(mob/user, force)
	if(get_equipped_item(SLOT_ID_SUIT) && (worn_of(get_equipped_item(SLOT_ID_SUIT)).hides & HIDEJUMPSUIT) && (get_equipped_item(SLOT_ID_MASK) && (worn_of(get_equipped_item(SLOT_ID_MASK)).hides & HIDEFACE) || isobj(get_equipped_item(SLOT_ID_HEAD)) && (worn_of(get_equipped_item(SLOT_ID_HEAD)).covers & FACE)))
		return PLURAL
	return gender

/mob/living/carbon/human/p_they(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_their(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_theirs(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_them(capitalized, temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_have(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_are(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_were(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_do(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_s(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_es(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

/mob/living/carbon/human/p_themselves(temp_gender)
	temp_gender ||= get_visible_gender()
	return ..()

// ITEM GENDER

/obj/item/clothing/p_they(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "they"
	return "it"

/obj/item/clothing/p_their(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "their"
	return "its"

/obj/item/clothing/p_theirs(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "theirs"
	return "its"

/obj/item/clothing/p_them(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "them"
	return "it"

/obj/item/clothing/p_have(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "have"
	return "has"

/obj/item/clothing/p_are(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "are"
	return "is"

/obj/item/clothing/p_were(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "were"
	return "was"

/obj/item/clothing/p_do(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender == PLURAL)
		return "do"
	return "does"

/obj/item/clothing/p_s(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender != PLURAL)
		return "s"

/obj/item/clothing/p_es(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	if(temp_gender != PLURAL)
		return "es"

/obj/item/clothing/p_themselves(temp_gender)
	if(!temp_gender)
		temp_gender = gender
	switch(temp_gender)
		if(FEMALE)
			return "herself"
		if(MALE)
			return "himself"
		if(PLURAL)
			return "themselves"
		if(HERM)
			return "hirself"
		else
			return "itself"
