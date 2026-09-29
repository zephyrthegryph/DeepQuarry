/obj/structure/alien //Gurg Addition, framework for alien structures.
	name = "alien thing"
	desc = "There's something alien about this."
	icon = 'icons/mob/alien.dmi'
	layer = ABOVE_JUNK_LAYER
	max_integrity = 50
	unacidable = TRUE
	anchored = TRUE

/obj/structure/alien/atom_destruction(damage_flag)
	set_density(0)
	return ..()

/obj/structure/alien/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	visible_message(span_danger("\The [src] was hit by \the [source]."))
	play_sfx(loc, SFX_EFFECTS_ATTACKBLOB, 2)
	..()

/obj/structure/alien/attack_generic(mob/user, damage, attack_verb)
	visible_message(span_danger("[user] [attack_verb] the [src]!"))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)
	return

/obj/structure/alien/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/alien_item,
		/datum/interaction/entry_hand/alien_hand/harm,
		/datum/interaction/entry_hand/alien_hand,
	)
	..()

/// Old attackby: hit the alien structure.
/datum/interaction/entry_item/alien_item
	id = "alien_item"
	name = "Use"
	effect = /obj/structure/alien/proc/interaction_item

/obj/structure/alien/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	user.setClickCooldown(user.get_attack_speed(W))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	visible_message(span_danger("[user] attacks the [src]!"))
	receive_weapon_hit(W, user)
	return TRUE

/// Old attack_hand: a Hulk destroys it, or a xenomorph melts through it.
/datum/interaction/entry_hand/alien_hand
	id = "alien_hand"
	name = "Use"
	effect = /obj/structure/alien/proc/interaction_hand

/// Combat mode: hivenode carriers melt it away, replicant resin spinners dissolve it.
/datum/interaction/entry_hand/alien_hand/harm
	id = "alien_hand_harm"
	name = "Melt"
	stance = I_HURT

/obj/structure/alien/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if (HULK in user.mutations)
		visible_message(span_warning("[user] destroys the [name]!"))
		take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
	else

		// Aliens can get straight through these.
		if(istype(user,/mob/living/carbon))
			if(interaction.stance == I_HURT)
				var/mob/living/carbon/M = user
				if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
					visible_message (span_warning("[user] strokes the [name] and it melts away!"), 1)
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return TRUE
				if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/resinspinner/replicant))
					om_task_timed(M, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(usr))
					return TRUE
			visible_message(span_warning("[usr] claws at the [name]!"))
			take_damage(rand(5,10), BRUTE, MELEE, sound_effect = FALSE)
	return TRUE

/obj/structure/alien/proc/attack_hand_timed_done(mob/usr_mob)
	visible_message (span_warning("[usr_mob] strokes the [name] and it melts away!"), 1)
	take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
	return

/obj/structure/alien/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(air_group) return 0
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return !opacity
	return !density
