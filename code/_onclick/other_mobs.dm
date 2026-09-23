// Generic damage proc (slimes and monkeys).
/atom/proc/attack_generic(mob/user, damage, attack_verb)
	if(!damage || !uses_integrity)
		return 0
	user.do_attack_animation(src)
	visible_message(span_danger("[user] [attack_verb || "attacks"] \the [src]!"))
	receive_generic_attack(user, damage)
	return 1

/*
	Humans:
	Adds an exception for get_equipped_item(SLOT_ID_GLOVES), to allow special glove types like the ninja ones.

	Otherwise pretty standard.
*/
/mob/living/carbon/human/UnarmedAttack(atom/A, proximity)

	if(!..())
		return

	// Special glove functions:
	// If the gloves do anything, have them return 1 to stop
	// normal attack_hand() here.
	var/obj/item/clothing/gloves/G = get_equipped_item(SLOT_ID_GLOVES) // not typecast specifically enough in defines
	if(istype(G) && G.Touch(A,1))
		return

	A.attack_hand(src)

/**
 * Touched with an empty hand, or a silicon's Use through silicon_use. The
 * type's gates run first (hand_gate()); then the converted handlers (I7):
 * interactions with `entry = INTERACTION_ENTRY_HAND`, most specific type first.
 * Returns TRUE when a gate stopped the touch or an interaction answered it.
 */
/atom/proc/attack_hand(mob/user as mob)
	return run_interaction_entry(user, src, null, INTERACTION_ENTRY_HAND, null, TRUE) ? TRUE : FALSE

/**
 * What a touch passes through before the type's own hand interactions: signal
 * listeners, unbuckling, the machinery operability checks. Returns TRUE to stop
 * the touch there. Overrides call ..() at the point the old attack_hand did.
 */
/atom/proc/hand_gate(mob/user)
	if(SEND_SIGNAL(src, COMSIG_ATOM_ATTACK_HAND, user) & COMPONENT_CANCEL_ATTACK_CHAIN)
		return TRUE
	return FALSE

/mob/living/carbon/human/RestrainedClickOn(atom/A)
	return

/mob/proc/has_telegrip()
	return TK in mutations

/mob/living/carbon/human/has_telegrip()
	if(istype(get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/telekinetic))
		var/obj/item/clothing/gloves/telekinetic/G = get_equipped_item(SLOT_ID_GLOVES)
		if(G.has_grip_power())
			return TRUE
	return ..()

/mob/living/carbon/human/RangedAttack(atom/A)
	if(!get_equipped_item(SLOT_ID_GLOVES) && !mutations.len && !spitting)
		return
	var/obj/item/clothing/gloves/G = get_equipped_item(SLOT_ID_GLOVES)
	if((LASER_EYES in mutations) && IS_HARMING(src))
		LaserEyes(A) // moved into a proc below

	else if(istype(G) && G.Touch(A,0)) // for magic gloves
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
			A.attack_tk(src)
	else if(spitting) //Only used by xenos right now, can be expanded.
		Spit(A)

/mob/living/RestrainedClickOn(atom/A)
	return

/*
	Aliens
*/

/mob/living/carbon/alien/RestrainedClickOn(atom/A)
	return

/mob/living/carbon/alien/UnarmedAttack(atom/A, proximity)

	if(!..())
		return 0

	setClickCooldown(get_attack_speed())
	A.attack_generic(src,rand(5,6),"bitten")

/*
	New Players:
	Have no reason to click on anything at all.
*/
/mob/new_player/ClickOn()
	return
