#define NEST_RESIST_TIME 1200

/obj/structure/bed/nest
	name = "alien nest"
	desc = "It's a gruesome pile of thick, sticky resin shaped like a nest."
	icon = 'icons/mob/alien.dmi'
	icon_state = "nest"
	max_integrity = 100
	unacidable = TRUE
	flippable = FALSE

/obj/structure/bed/nest/update_icon()
	return

/obj/structure/bed/nest/user_unbuckle_mob(mob/living/buckled_mob, mob/user)
	if(buckled_mob)
		if(buckled_mob?.buckled_to() == src)
			if(buckled_mob != user)
				act_message(buckled_mob, null, MSG_SELF(span_notice("[user.name] pulls you free from the gelatinous resin.")), \
					MSG_OTHERS(span_notice("[user.name] pulls [buckled_mob.name] free from the sticky nest!")), \
					MSG_BLIND(span_notice("You hear squelching...")))
				buckled_mob.pixel_y = 0
				buckled_mob.old_y = 0
				unbuckle_mob(buckled_mob)
			else
				if(!COOLDOWN_FINISHED(buckled_mob, last_special))
					return
				COOLDOWN_START(buckled_mob, last_special, NEST_RESIST_TIME)
				act_message(buckled_mob, null, MSG_SELF(span_warning("You struggle to break free from the gelatinous resin...")), \
					MSG_OTHERS(span_warning("[buckled_mob.name] struggles to break free of the gelatinous resin...")), \
					MSG_BLIND(span_notice("You hear squelching...")))
				om_after(src, NEST_RESIST_TIME, PROC_REF(struggle_free), user, buckled_mob)
			src.add_fingerprint(user)
	return

/// The end of a struggle out of the resin.
/obj/structure/bed/nest/proc/struggle_free(mob/user, mob/living/buckled_mob)
	if(user?.buckled_to() == src)
		COOLDOWN_START(buckled_mob, last_special, NEST_RESIST_TIME)
		buckled_mob.pixel_y = 0
		buckled_mob.old_y = 0
		unbuckle_mob(buckled_mob)

#undef NEST_RESIST_TIME

/obj/structure/bed/nest/user_buckle_mob(mob/M as mob, mob/user as mob)
	if ( !ismob(M) || (get_dist(src, user) > 1) || (M.loc != src.loc) || user.restrained() || user.stat || M?.buckled_to() || ispAI(user) )
		return

	unbuckle_mob()

	var/mob/living/carbon/xenos = user
	var/mob/living/carbon/victim = M

	if(istype(victim) && locate_in_list(victim.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
		return

	if(istype(xenos) && !(locate_in_list(xenos.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode)))
		return

	if(M == user)
		return
	else
		act_message(M, src, MSG_SELF(span_warning("[user.name] drenches you in a foul-smelling resin, trapping you in %T%!")), \
			MSG_OTHERS(span_notice("[user.name] secretes a thick vile goo, securing [M.name] into %T%!")), \
			MSG_BLIND(span_notice("You hear squelching...")))
	M.forceMove(src.loc)
	buckle_mob(M, forced = TRUE)
	M.pixel_y = 6
	M.old_y = 6
	src.add_fingerprint(user)
	return

// Nest's Use and item overrides fully replace bed's (the original overrides never called
// ..() into it either), so it declares its own interactions.
/obj/structure/bed/nest/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/nest_item,
		/datum/interaction/entry_hand/nest_hand/harm,
		/datum/interaction/entry_hand/nest_hand,
	)

/// Old attackby: hit the nest.
/datum/interaction/entry_item/nest_item
	id = "nest_item"
	name = "Use"
	effect = /obj/structure/bed/nest/proc/interaction_nest_item

/obj/structure/bed/nest/proc/interaction_nest_item(mob/user, obj/item/W, datum/interaction/interaction)
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	for(var/mob/M in viewers(src, 7))
		M.show_message(span_warning("[user] hits [src] with [W]!"), 1)
	receive_weapon_hit(W, user)
	return TRUE

/obj/structure/bed/nest/atom_destruction(damage_flag)
	set_density(FALSE)
	return ..()

// start - Allows xenos to clean nests.
/// Old attack_hand: a Hulk destroys it, or a xenomorph melts through it.
/datum/interaction/entry_hand/nest_hand
	id = "nest_hand"
	name = "Use"
	effect = /obj/structure/bed/nest/proc/interaction_hand

/// Combat mode: hivenode carriers melt the nest away.
/datum/interaction/entry_hand/nest_hand/harm
	id = "nest_hand_harm"
	name = "Melt"
	stance = I_HURT

/obj/structure/bed/nest/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if (HULK in user.mutations)
		act_message(user, null, others = span_warning("%U% destroys the [name]!"))
		take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
	else

		// Aliens can get straight through these.
		if(istype(user,/mob/living/carbon))
			if(interaction.stance == I_HURT)
				var/mob/living/carbon/M = user
				if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
					act_message(user, null, others = span_warning("%U% strokes the [name] and it melts away!"))
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return TRUE
	return TRUE
// end.
