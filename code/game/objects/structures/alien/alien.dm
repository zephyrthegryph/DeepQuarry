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

CAPABILITIES(/obj/structure/alien)
	extend(/datum/act/hit, instead(then(PROC_REF(alien_thrown_at))))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("melt", hand(), stance(I_HURT), label("Melt"), wait(PROC_REF(melt_time)), then(PROC_REF(interaction_melt)))
	op("hand", hand(), stance(I_HELP, I_DISARM, I_GRAB), label("Use"), then(PROC_REF(interaction_hand)))

/// A throw squelches into the resin before it lands. A thrown thing is the generic hit, so the squelch checks the entry; the hit goes on either way.
/obj/structure/alien/proc/alien_thrown_at(datum/act/hit/A)
	if(A.packet.entry != DAMAGE_ENTRY_THROWN)
		return HOOK_DECLINE
	visible_message(span_danger("\The [src] was hit by \the [A.packet.source]."))
	play_sfx(loc, SFX_EFFECTS_ATTACKBLOB, 2)
	return HOOK_DECLINE

/obj/structure/alien/attack_generic(mob/user, damage, attack_verb)
	act_message(user, src, others = span_danger("%U% [attack_verb] %T%!"))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)
	return

/obj/structure/alien/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(user.get_attack_speed(W))
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB, 2)
	act_message(user, src, others = span_danger("%U% attacks %T%!"))
	receive_weapon_hit(W, user)
	return OP_OK

/// Old attack_hand: a Hulk destroys it, or a xenomorph claws at it.
/obj/structure/alien/proc/interaction_hand(datum/act/op/A)
	return alien_hand_used(A, FALSE)

/// Combat mode: hivenode carriers melt it away, replicant resin spinners dissolve it.
/obj/structure/alien/proc/interaction_melt(datum/act/op/A)
	return alien_hand_used(A, TRUE)

/// A replicant resin spinner takes three seconds to melt it; a hulk, a hivenode carrier and a plain claw are answered at once.
/obj/structure/alien/proc/melt_time(datum/act/op/A)
	var/mob/living/carbon/M = A.actor
	if(!istype(M) || (HULK in M.mutations))
		return 0
	if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
		return 0
	if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/resinspinner/replicant))
		return 3 SECONDS
	return 0

/obj/structure/alien/proc/alien_hand_used(datum/act/op/A, harm)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if (HULK in user.mutations)
		act_message(user, null, others = span_warning("%U% destroys the [name]!"))
		take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
	else

		// Aliens can get straight through these.
		if(istype(user,/mob/living/carbon))
			if(harm)
				var/mob/living/carbon/M = user
				if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
					act_message(user, null, others = span_warning("%U% strokes the [name] and it melts away!"))
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return OP_OK
				if(locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/resinspinner/replicant))
					visible_message(span_warning("[user] strokes the [name] and it melts away!"), 1)
					take_damage(get_integrity(), BRUTE, MELEE, sound_effect = FALSE)
					return OP_OK
			act_message(user, null, others = span_warning("%U% claws at the [name]!"))
			take_damage(rand(5,10), BRUTE, MELEE, sound_effect = FALSE)
	return OP_OK

/obj/structure/alien/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(air_group) return 0
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return !opacity
	return !density
