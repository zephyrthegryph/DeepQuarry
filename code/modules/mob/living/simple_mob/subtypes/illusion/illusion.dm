// Illusion type mobs pretend to be other things visually, and generally cannot be harmed as they're not 'real'.

/mob/living/simple_mob/illusion
	name = "illusion"
	desc = "If you can read me, the game broke. Please report this to a coder."

	resistance = 1000 // Holograms are tough.
	heat_resist = 1
	cold_resist = 1
	shock_resist = 1
	poison_resist = 1

	movement_cooldown = -2
	mob_bump_flag = 0 // If the illusion can't be swapped it will be obvious.

	response_help   = "pushes a hand through"
	response_disarm = "tried to disarm"
	response_harm   = "tried to punch"

	mob_class = MOB_CLASS_ILLUSION
	draws_life_state = FALSE
	biology = BIOLOGY_SYNTHETIC // Holographic: nothing to poison or suffocate, nothing to medicate.


	var/atom/movable/copying = null // The thing we're trying to look like.
	var/realistic = FALSE // If true, things like bullets and weapons will hit it, to be a bit more convincing from a distance.

	can_pain_emote = FALSE

/mob/living/simple_mob/illusion/proc/copy_appearance(atom/movable/thing_to_copy)
	if(!thing_to_copy)
		return FALSE
	appearance = thing_to_copy.appearance
	rel_set(src, nameof(copying), thing_to_copy)
	set_density(thing_to_copy.density) // So you can't bump into objects that aren't supposed to be dense.
	catalogue_data = thing_to_copy.get_catalogue_data()
	dq_set_catalogue_delay(src, thing_to_copy.get_catalogue_delay()) // copy DQ catalogue scan-delay so illusions don't reveal themselves via faster scan time
	return TRUE

// Because we can't perfectly duplicate some examine() output, we directly examine the AM it is copying.  It's messy but
// this is to prevent easy checks from the opposing force.
/mob/living/simple_mob/illusion/examine(mob/user)
	SHOULD_CALL_PARENT(FALSE)
	if(copying)
		return copying.examine(user)
	else
		return list("???")

/mob/living/simple_mob/illusion/bullet_act(obj/item/projectile/P)
	if(!P)
		return

	if(realistic)
		return ..()

	return PROJECTILE_FORCE_MISS

CAPABILITIES(/mob/living/simple_mob/illusion)
	op("illusion_hand_help", hand(), ungated(), stance(I_HELP), label("Hug"), then(PROC_REF(illusion_interaction_hand_help)))
	op("illusion_hand_disarm", hand(), ungated(), stance(I_DISARM), label("Shove"), then(PROC_REF(illusion_interaction_hand_disarm)))
	op("illusion_hand_grab", hand(), ungated(), stance(I_GRAB), label("Grab"), then(PROC_REF(illusion_interaction_hand_grab)))
	op("illusion_hand_hurt", hand(), ungated(), stance(I_HURT), label("Hit"), then(PROC_REF(illusion_interaction_hand_hurt)))
	extend(/datum/act/hit/explosion, instead())

/// The help-stance input of illusion_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/illusion/proc/illusion_interaction_hand_help(datum/act/op/A)
	return illusion_interaction_hand(A, I_HELP)

/// The disarm-stance input of illusion_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/illusion/proc/illusion_interaction_hand_disarm(datum/act/op/A)
	return illusion_interaction_hand(A, I_DISARM)

/// The grab-stance input of illusion_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/illusion/proc/illusion_interaction_hand_grab(datum/act/op/A)
	return illusion_interaction_hand(A, I_GRAB)

/// The hurt-stance input of illusion_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/illusion/proc/illusion_interaction_hand_hurt(datum/act/op/A)
	return illusion_interaction_hand(A, I_HURT)

/// Old attack_hand: unrealistic illusions can't be touched; realistic ones fake the reactions.
/mob/living/simple_mob/illusion/proc/illusion_interaction_hand(datum/act/op/A, stance)
	var/mob/living/carbon/human/M = A.actor
	. = OP_OK
	if(!realistic)
		play_sfx(src, SFX_WEAPONS_PUNCHMISS)
		act_message(M, src, null, MSG_OTHERS(span_warning("%U%'s hand goes through %T%!")))
		return
	else
		switch(stance)
			if(I_HELP)
				act_message(M, src, \
					MSG_SELF(span_notice("You hug %T% to make [p_them()] feel better!")), \
					MSG_OTHERS(span_notice("%U% hugs %T% to make [p_them()] feel better!"))) // slightly redundant as at the moment most mobs still use the normal gender var, but it works and future-proofs it
				play_sfx(src, SFX_WEAPONS_THUDSWOOSH)

			if(I_DISARM)
				play_sfx(src, SFX_WEAPONS_PUNCHMISS)
				act_message(M, src, null, MSG_OTHERS(span_danger("%U% attempted to disarm %T%!")))
				M.do_attack_animation(src)

			if(I_GRAB)
				return OP_DECLINE

			if(I_HURT)
				injure(INJURY_BLUNT, harm_intent_damage, source = M)
				act_message(M, src, null, MSG_OTHERS(span_danger("%U% [response_harm] %T%")))
				M.do_attack_animation(src)

/mob/living/simple_mob/illusion/hit_with_weapon(obj/item/I, mob/living/user, effective_force, hit_zone)
	if(realistic)
		return ..()

	play_sfx(src, SFX_WEAPONS_PUNCHMISS)
	act_message(user, src, null, MSG_OTHERS(span_warning("%U%'s %I% goes through %T%!")), item = I)
	return FALSE

// Try to have the same tooltip, or else it becomes really obvious which one is fake.
/mob/living/simple_mob/illusion/get_nametag_name(mob/user)
	if(copying)
		return copying.get_nametag_name(user)

/mob/living/simple_mob/illusion/get_nametag_desc(mob/user)
	if(copying)
		return copying.get_nametag_desc(user)

// Cataloguer stuff. I don't think this will actually come up but better safe than sorry.
/mob/living/simple_mob/illusion/get_catalogue_data()
	if(copying)
		return copying.get_catalogue_data()

/mob/living/simple_mob/illusion/can_catalogue()
	if(copying)
		return copying.can_catalogue()

/mob/living/simple_mob/illusion/get_catalogue_delay()
	if(copying)
		return copying.get_catalogue_delay()

