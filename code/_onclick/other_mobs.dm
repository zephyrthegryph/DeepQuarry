/// A generic attack (a simple mob's, a xeno's, a bot's, a hulk's smash) on `target`: the hit/generic action (doc/rewrite/final_api.html, section 8).
/// The one emitter: a type answers it with extend(/datum/act/hit/generic, instead(...)); when nothing takes it over the default generic attack
/// (attack_generic()) lands with the act's final damage. Returns what the default attack returned, or FALSE when the target took it over.
/proc/generic_hit(atom/target, mob/user, damage, attack_verb)
	if(!target || QDELETED(target))
		return FALSE
	var/datum/damage_packet/packet = damage_packet(user, user, null, null, DAMAGE_PACKET_SILENT, 0, user ? get_dir(user, target) : 0, null, DAMAGE_ENTRY_GENERIC)
	var/datum/act/hit/generic/G = ACT_TRY(target, hit_generic, packet, user, damage, attack_verb)
	if(!G)
		packet.release()
		return FALSE
	damage = ACT_FINAL(G, damage, damage)
	. = target.attack_generic(user, damage, attack_verb)
	act_done(G)
	packet.release()

// Generic damage proc (slimes and monkeys): the default a generic hit lands when no hook takes it over. Reached only through generic_hit().
/atom/proc/attack_generic(mob/user, damage, attack_verb)
	if(!damage || !uses_integrity)
		react_to_entry(DAMAGE_ENTRY_GENERIC, 0, user, user)
		return 0
	user.do_attack_animation(src)
	act_message(user, src, others = span_danger("%U% [attack_verb || "attacks"] %T%!"))
	receive_generic_attack(user, damage)
	return 1

/*
	Humans:
	Adds an exception for get_equipped_item(SLOT_ID_GLOVES), to allow special glove types like the ninja ones.

	Otherwise pretty standard.
*/
/mob/living/carbon/human/UnarmedAttack(atom/A, proximity, stance = I_HURT)

	if(!..())
		return

	// Special glove functions:
	// If the gloves do anything, have them return 1 to stop
	// normal attack_hand() here.
	var/obj/item/clothing/gloves/G = get_equipped_item(SLOT_ID_GLOVES) // not typecast specifically enough in defines
	if(istype(G) && G.Touch(A, 1, stance, src))
		return

	A.attack_hand(src)

/**
 * Touched with an empty hand, or a silicon's Use through silicon_use: the ops answered it first; what is left is the type's gate (hand_gate()).
 * Returns TRUE when the gate stopped the touch.
 */
/atom/proc/attack_hand(mob/user as mob)
	if(!user)
		return FALSE
	return hand_gate(user) ? TRUE : FALSE

/**
 * What a touch passes through before the type's own hand interactions: signal
 * listeners, unbuckling, the machinery operability checks. Returns TRUE to stop
 * the touch there. Overrides call ..() at the point the old attack_hand did.
 */
/atom/proc/hand_gate(mob/user)
	var/datum/act/attack_hand/touch = ACT_TRY(src, attack_hand, user)
	if(!touch)
		return TRUE
	act_done(touch)
	return FALSE

/mob/proc/has_telegrip()
	return has_mutation(TK)

/mob/living/carbon/human/has_telegrip()
	if(istype(get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/telekinetic))
		var/obj/item/clothing/gloves/telekinetic/G = get_equipped_item(SLOT_ID_GLOVES)
		if(G.has_grip_power())
			return TRUE
	return ..()

/mob/living/carbon/human/RangedAttack(atom/A, params, stance = I_HURT)
	if(!get_equipped_item(SLOT_ID_GLOVES) && !mutation_count() && !spitting)
		return
	var/obj/item/clothing/gloves/G = get_equipped_item(SLOT_ID_GLOVES)
	if((has_mutation(LASER_EYES)) && stance == I_HURT)
		LaserEyes(A) // moved into a proc below

	else if(istype(G) && G.Touch(A, 0, stance, src)) // for magic gloves
		return

	else if(has_telegrip())
		if(istype(get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/telekinetic))
			var/obj/item/clothing/gloves/telekinetic/TKG = get_equipped_item(SLOT_ID_GLOVES)
			TKG.use_grip_power(src,TRUE)
		if(is_remote_viewing()) // Extremely bad exploits if allowed to TK while remote viewing
			to_chat(src, TK_DENIED_MESSAGE)
		else if(get_dist(src, A) > TK_MAXRANGE)
			to_chat(src, TK_OUTRANGED_MESSAGE)
		else
			actor_use(/datum/input_adapter/telekinesis, src, A)
	else if(spitting) //Only used by xenos right now, can be expanded.
		Spit(A)

/mob/living/RestrainedClickOn(atom/A, stance = I_HURT)
	return

/*
	Aliens
*/

/mob/living/carbon/alien/RestrainedClickOn(atom/A, stance = I_HURT)
	return

/mob/living/carbon/alien/UnarmedAttack(atom/A, proximity, stance = I_HURT)

	if(!..())
		return 0

	setClickCooldown(get_attack_speed())
	generic_hit(A, src, rand(5,6), "bitten")

/*
	New Players:
	Have no reason to click on anything at all.
*/
/mob/new_player/ClickOn()
	return
