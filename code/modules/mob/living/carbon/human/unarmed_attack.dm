//Species unarmed attacks
/datum/unarmed_attack
	var/attack_name = "fist"
	// Both are interned in New(): shared between attacks with the same words, so never write to them.
	// ALLOW(instance_list): kept: interned with string_list() in New()
	var/list/attack_verb = list("attack")	// Empty hand hurt intent verb.
	var/list/attack_noun = list("fist") // ALLOW(instance_list): kept: interned with string_list() in New()
	var/damage = 0						// Extra empty hand attack damage.
	var/attack_sound = SFX_PUNCH
	var/miss_sound = 'sound/weapons/punchmiss.ogg'
	var/shredding = FALSE // Calls the old attack_alien() behavior on objects/mobs when on harm intent.
	var/sharp = FALSE
	var/edge = FALSE
	/// What the attack inflicts.
	var/injury_kind = INJURY_BLUNT

	var/is_punch = FALSE //If the attack benefits from the damage increase things being on your hands give.
	var/sparring_variant_type = /datum/unarmed_attack/light_strike

	var/eye_attack_text
	var/eye_attack_text_victim

/datum/unarmed_attack/New()
	..()
	if(islist(attack_verb))
		attack_verb = string_list(attack_verb)
	if(islist(attack_noun))
		attack_noun = string_list(attack_noun)

/datum/unarmed_attack/proc/get_sparring_variant()
	if(sparring_variant_type)
		if(!GLOB.sparring_attack_cache[sparring_variant_type])
			GLOB.sparring_attack_cache[sparring_variant_type] = new sparring_variant_type()
		return GLOB.sparring_attack_cache[sparring_variant_type]

/datum/unarmed_attack/proc/is_usable(mob/living/carbon/human/user, mob/living/carbon/human/target, zone)
	if(user.restrained())
		return FALSE

	// Check if they have a functioning hand.
	var/obj/item/organ/external/E = user.organs_by_name[BP_L_HAND]
	if(E && !E.is_stump())
		return TRUE

	E = user.organs_by_name[BP_R_HAND]
	if(E && !E.is_stump())
		return TRUE

	return FALSE

/datum/unarmed_attack/proc/get_unarmed_damage(mob/living/carbon/human/user)
	if(has_trait(user, TRAIT_NONLETHAL_BLOWS))//don't add extra species strength when pulling punches
		return damage
	return damage + user.species.unarmed_bonus

/datum/unarmed_attack/proc/apply_effects(mob/living/carbon/human/user,mob/living/carbon/human/target,armour,attack_damage,zone)

	var/stun_chance = rand(0, 100)

	if(attack_damage >= 5 && armour < 2 && !(target == user) && stun_chance <= attack_damage * 5) // 25% standard chance
		switch(zone) // strong punches can have effects depending on where they hit
			if(BP_HEAD, O_EYES, O_MOUTH)
				// Induce blurriness
				act_message(target, null, MSG_SELF(span_danger("You see stars.")), MSG_OTHERS(span_danger("%U% looks momentarily disoriented.")))
				target.apply_effect(attack_damage*2, EYE_BLUR, armour)
			if(BP_L_ARM, BP_L_HAND)
				if (target.get_equipped_item(SLOT_ID_HAND_L))
					// Disarm left hand
					//Urist McAssistant dropped the macguffin with a scream just sounds odd.
					act_message(target, null, others = span_danger("\The [target.get_equipped_item(SLOT_ID_HAND_L)] was knocked right out of %U%'s grasp!"))
					target.drop_l_hand()
			if(BP_R_ARM, BP_R_HAND)
				if (target.get_equipped_item(SLOT_ID_HAND_R))
					// Disarm right hand
					act_message(target, null, others = span_danger("\The [target.get_equipped_item(SLOT_ID_HAND_R)] was knocked right out of %U%'s grasp!"))
					target.drop_r_hand()
			if(BP_TORSO)
				if(!target.lying)
					var/turf/T = get_step(get_turf(target), get_dir(get_turf(user), get_turf(target)))
					if(T && !T.density)
						step(target, get_dir(get_turf(user), get_turf(target)))
						act_message(target, null, others = span_danger("[pick("%U% was sent flying backward!", "%U% staggers back from the impact!")]"))
					else
						act_message(target, T, others = span_danger("%U% slams into %T%!"))
					if(prob(50))
						target.set_dir(GLOB.reverse_dir[target.dir])
					target.apply_effect(attack_damage * 0.4, WEAKEN, armour)
			if(BP_GROIN)
				act_message(target, null, MSG_SELF(span_warning("Oh god that hurt!")), MSG_OTHERS(span_warning("%U% looks like %THEYRE% in pain!")))
				target.apply_effects(stutter = attack_damage * 2, agony = attack_damage* 3, blocked = armour)
			if(BP_L_LEG, BP_L_FOOT, BP_R_LEG, BP_R_FOOT)
				if(!target.lying)
					act_message(target, null, others = span_warning("%U% gives way slightly."))
					target.apply_effect(attack_damage*3, AGONY, armour)
	else if(attack_damage >= 5 && !(target == user) && (stun_chance + attack_damage * 5 >= 100) && armour < 2) // Chance to get the usual throwdown as well (25% standard chance)
		if(!target.lying)
			act_message(target, null, others = span_danger("%U% [pick("slumps", "falls", "drops")] down to the ground!"))
		else
			act_message(target, null, others = span_danger("%U% has been weakened!"))
		target.apply_effect(3, WEAKEN, armour)

/datum/unarmed_attack/proc/show_attack(mob/living/carbon/human/user, mob/living/carbon/human/target, zone, attack_damage)
	var/obj/item/organ/external/affecting = target.get_organ(zone)
	act_message(user, target, others = span_warning("%U% [pick(attack_verb)] %T% in the [affecting.name]!"))
	playsound(user, attack_sound, 25, 1, -1)

/datum/unarmed_attack/proc/handle_eye_attack(mob/living/carbon/human/user, mob/living/carbon/human/target)
	var/obj/item/organ/internal/eyes/eyes = target.organ_in(O_EYES)
	if(eyes)
		target.injure(INJURY_BLUNT, rand(3,4), eyes, user, flags = INJURE_SILENT)
		act_message(user, target, others = span_danger("%U% presses [p_their()] [eye_attack_text] into %T%'s [eyes.name]!"))
		var/eye_pain = eyes.organ_can_feel_pain()
		to_chat(target, span_danger("You experience[(eye_pain) ? "" : " immense pain as you feel" ] [eye_attack_text_victim] being pressed into your [eyes.name][(eye_pain)? "." : "!"]"))
		return
	act_message(user, target, others = span_danger("%U% attempts to press [p_their()] [eye_attack_text] into %T%'s eyes, but [target.p_they()] [target.p_do()]n't have any!"))

/datum/unarmed_attack/proc/unarmed_override(mob/living/carbon/human/user,mob/living/carbon/human/target,zone)
	return FALSE //return true if the unarmed override prevents further attacks

/datum/unarmed_attack/bite
	attack_name = "bite"
	attack_verb = list("bit")
	attack_sound = SFX_WEAPONS_BITE
	damage = 0

/datum/unarmed_attack/bite/event1

/datum/unarmed_attack/bite/is_usable(mob/living/carbon/human/user, mob/living/carbon/human/target, zone)
	if (user.is_muzzled() || user?.buckled_to())
		return FALSE
	if (user == target && ((zone == BP_GROIN && (prob(98)) || (zone == BP_HEAD || zone == O_EYES || zone == O_MOUTH)))) //biting your own groin is hard. 2% hit chance.
		return FALSE
	for(var/obj/item/organ/external/head/user_head in user.organs) //We have a head!
		if(!user_head.dislocated && !user_head.is_fractured()) //And it's not dislocated
			return TRUE
	return FALSE

/datum/unarmed_attack/punch
	attack_name = "punch"
	attack_verb = list("punched")
	attack_noun = list("fist")
	eye_attack_text = "fingers"
	eye_attack_text_victim = "digits"
	damage = 0
	is_punch = TRUE

/datum/unarmed_attack/punch/event1

/datum/unarmed_attack/punch/show_attack(mob/living/carbon/human/user, mob/living/carbon/human/target, zone, attack_damage)
	var/obj/item/organ/external/affecting = target.get_organ(zone)
	var/organ = affecting.name

	attack_damage = CLAMP(attack_damage, 1, 5) // We expect damage input of 1 to 5 for this proc. But we leave this check juuust in case.

	if(target == user)
		act_message(user, null, others = span_danger("%U% [pick(attack_verb)] [p_themselves()] in the [organ]!"))
		return FALSE

	if(!target.lying)
		switch(zone)
			if(BP_HEAD, O_MOUTH, O_EYES)
				// ----- HEAD ----- //
				switch(attack_damage)
					if(1 to 2)
						act_message(user, target, others = span_danger("%U% slapped %T% across [p_their()] cheek!"))
					if(3 to 4)
						act_message(user, target, others = pick( 40; span_danger("%U% [pick(attack_verb)] %T% in the head!"), 30; span_danger("%U% struck %T% in the head[pick("", " with a closed fist")]!"), 30; span_danger("%U% threw a hook against %T%'s head!") ))
					if(5)
						act_message(user, target, others = pick( 30; span_danger("%U% gave %T% a resounding [pick("slap", "punch")] to the face!"), 40; span_danger("%U% smashed [p_their()] [pick(attack_noun)] into %T%'s face!"), 30; span_danger("%U% gave a strong blow against %T%'s jaw!") ))
			else
				// ----- BODY ----- //
				switch(attack_damage)
					if(1 to 2)	act_message(user, target, others = span_danger("%U% threw a glancing punch at %T%'s [organ]!"))
					if(1 to 4)	act_message(user, target, others = span_danger("%U% [pick(attack_verb)] %T% in [target.p_their()] [organ]!"))
					if(5)
						act_message(user, target, others = pick( 50; span_danger("%U% smashed [p_their()] [pick(attack_noun)] into %T%'s [organ]!"), 50; span_danger("%U% landed a striking [pick(attack_noun)] on %T%'s [organ]!") ))
	else
		act_message(user, target, others = span_danger("%U% [pick("punched", "threw a punch against", "struck", "slammed [p_their()] [pick(attack_noun)] into")] %T%'s [organ]!")) //why do we have a separate set of verbs for lying targets?

/datum/unarmed_attack/kick
	attack_name = "kick"
	attack_verb = list("kicked", "kicked", "kicked", "kneed")
	attack_noun = list("kick", "kick", "kick", "knee strike")
	attack_sound = SFX_SWING_HIT
	damage = 0

/datum/unarmed_attack/kick/event1

/datum/unarmed_attack/kick/is_usable(mob/living/carbon/human/user, mob/living/carbon/human/target, zone)
	if(user.get_equipped_item(SLOT_ID_LEGCUFFED) || user?.buckled_to())
		return FALSE

	if(!(zone in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT, BP_GROIN)))
		return FALSE

	var/obj/item/organ/external/E = user.organs_by_name[BP_L_FOOT]
	if(E && !E.is_stump())
		return TRUE

	E = user.organs_by_name[BP_R_FOOT]
	if(E && !E.is_stump())
		return TRUE

	return FALSE

/datum/unarmed_attack/kick/get_unarmed_damage(mob/living/carbon/human/user)
	var/obj/item/clothing/shoes = user.get_equipped_item(SLOT_ID_SHOES)
	if(!istype(shoes))
		return user.species.unarmed_bonus + damage
	if(has_trait(user, TRAIT_NONLETHAL_BLOWS))//don't add extra species strength when pulling punches
		return damage + (shoes ? shoes.force : 0)
	return user.species.unarmed_bonus + damage + (shoes ? shoes.force : 0)

/datum/unarmed_attack/kick/show_attack(mob/living/carbon/human/user, mob/living/carbon/human/target, zone, attack_damage)
	var/obj/item/organ/external/affecting = target.get_organ(zone)
	var/organ = affecting.name

	attack_damage = CLAMP(attack_damage, 1, 5)

	switch(attack_damage)
		if(1 to 2)	act_message(user, target, others = span_danger("%U% threw %T% a glancing [pick(attack_noun)] to the [organ]!")) //it's not that they're kicking lightly, it's that the kick didn't quite connect
		if(3 to 4)	act_message(user, target, others = span_danger("%U% [pick(attack_verb)] %T% in [target.p_their()] [organ]!"))
		if(5)		act_message(user, target, others = span_danger("%U% landed a strong [pick(attack_noun)] against %T%'s [organ]!"))

/datum/unarmed_attack/stomp
	attack_name = "stomp"
	attack_verb = null
	attack_noun = list("stomp")
	attack_sound = SFX_SWING_HIT
	damage = 0

/datum/unarmed_attack/stomp/event1

/datum/unarmed_attack/stomp/is_usable(mob/living/carbon/human/user, mob/living/carbon/human/target, zone)

	if (user.get_equipped_item(SLOT_ID_LEGCUFFED) || user?.buckled_to())
		return FALSE

	if(!istype(target))
		return FALSE

	if (!user.lying && (target.lying || (zone in list(BP_L_FOOT, BP_R_FOOT))))
		if(target?.grabbed_by_list() == user && target.lying)
			return FALSE
		var/obj/item/organ/external/E = user.organs_by_name[BP_L_FOOT]
		if(E && !E.is_stump())
			return TRUE

		E = user.organs_by_name[BP_R_FOOT]
		if(E && !E.is_stump())
			return TRUE

		return FALSE

/datum/unarmed_attack/stomp/get_unarmed_damage(mob/living/carbon/human/user)
	var/obj/item/clothing/shoes = user.get_equipped_item(SLOT_ID_SHOES)
	if(has_trait(user, TRAIT_NONLETHAL_BLOWS))//don't add extra species strength when pulling punches
		return damage + (shoes ? shoes.force : 0)
	return user.species.unarmed_bonus + damage + (shoes ? shoes.force : 0)

/datum/unarmed_attack/stomp/show_attack(mob/living/carbon/human/user, mob/living/carbon/human/target, zone, attack_damage)
	var/obj/item/organ/external/affecting = target.get_organ(zone)
	var/organ = affecting.name
	var/obj/item/clothing/shoes = user.get_equipped_item(SLOT_ID_SHOES)

	attack_damage = CLAMP(attack_damage, 1, 5)

	switch(attack_damage)
		if(1 to 4)	act_message(user, target, others = span_danger("[pick("%U% stomped on", "%U% slammed %THEIR% [shoes ? copytext(shoes.name, 1, -1) : "foot"] down onto")] %T%'s [organ]!"))
		if(5)		act_message(user, target, others = span_danger("[pick("%U% landed a powerful stomp on", "%U% stomped down hard on", "%U% slammed %THEIR% [shoes ? copytext(shoes.name, 1, -1) : "foot"] down hard onto")] %T%'s [organ]!")) //Devastated lol. No. We want to say that the stomp was powerful or forceful, not that it /wrought devastation/

/datum/unarmed_attack/light_strike
	attack_name = "light hit"
	attack_noun = list("tap","light strike")
	attack_verb = list("tapped", "lightly struck")
	damage = 0
	injury_kind = INJURY_PAIN
	is_punch = TRUE
