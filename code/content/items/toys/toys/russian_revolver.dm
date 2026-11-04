/*
 * Russian revolver
 */
/obj/item/toy/russian_revolver
	name = "russian revolver"
	desc = "For fun and games!"
	icon = 'icons/obj/gun.dmi'
	icon_state = "detective"
	item_state = "gun"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_guns.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_guns.dmi',
		)
	var/bullets_left = 0
	var/max_shots = 6

/obj/item/toy/russian_revolver/proc/revolver_after_init(datum/act/timer/A)
	spin_cylinder()

CAPABILITIES(/obj/item/toy/russian_revolver)
	configure(movable_motion(throw_range = 5, throw_speed = 4))
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5, attack_verbs = list("struck", "hit", "bashed")))
	after_init(0, then(PROC_REF(revolver_after_init)))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/russian_revolver/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!bullets_left)
		act_message(user, src, others = span_warning("%U% loads a bullet into %T%'s cylinder before spinning it."))
		spin_cylinder()
	else
		act_message(user, src, others = span_warning("%U% spins the cylinder on %T%!"))
		play_sfx(src, SFX_WEAPONS_REVOLVER_SPIN)
		spin_cylinder()
	return TRUE

/obj/item/toy/russian_revolver/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/toy/russian_revolver/afterattack(atom/target, mob/user, flag, params)
	if(flag)
		if(is_in_holder(target, user))
			return
		if(!ismob(target))
			return
	shoot_gun(user)

/obj/item/toy/russian_revolver/proc/spin_cylinder()
	bullets_left = rand(1, max_shots)

/obj/item/toy/russian_revolver/proc/post_shot(mob/user)
	return

/obj/item/toy/russian_revolver/proc/shoot_gun(mob/living/carbon/human/user)
	if(bullets_left > 1)
		bullets_left--
		user.visible_message(span_danger("*click*"))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		return FALSE
	if(bullets_left == 1)
		bullets_left = 0
		var/zone = BP_HEAD
		if(!(user.has_organ(zone))) // If they somehow don't have a head.
			zone = "chest"
		play_sfx(src, SFX_EFFECTS_SNAP)
		user.visible_message(span_danger("[src] goes off!"))
		shake_camera(user, 2, 1)
		user.status_at_least(STAT_STUNNED, 1)
		post_shot(user)
		return TRUE
	else
		to_chat(user, span_warning("[src] needs to be reloaded."))
		return FALSE
