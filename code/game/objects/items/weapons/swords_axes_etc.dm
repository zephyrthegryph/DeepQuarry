/* Weapons
 * Contains:
 *		Sword
 *		Classic Baton
 *		Telescopic Baton
 */

/*
 * Classic Baton
 */

/obj/item/melee
	name = "weapon"
	desc = "Murder device."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "baton"
	slot_flags = SLOT_BELT
	force = 10
	drop_sound = SFX_ITEMS_DROP_METALWEAPON

/obj/item/melee/classic_baton
	name = "police baton"
	desc = "A wooden truncheon for beating criminal scum."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "baton"
	item_state = "classic_baton"
	slot_flags = SLOT_BELT
	force = 10
	drop_sound = SFX_ITEMS_DROP_CROWBAR
	pickup_sound = SFX_ITEMS_PICKUP_CROWBAR

/obj/item/melee/classic_baton/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_warning("You club yourself over the head."))
		user.status_at_least(STAT_WEAKENED, 3 * force)
		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			H.injure(injury_kind, 2*force, BP_HEAD, src)
		else
			user.injure(injury_kind, 2*force, source = src)
		return ITEM_INTERACT_SUCCESS
	return ..()

//Telescopic baton
/obj/item/melee/telebaton
	name = "telescopic baton"
	desc = "A compact yet rebalanced personal defense weapon. Can be concealed when folded."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "telebaton0"
	item_state = "telebaton0"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	force = 3
	drop_sound = SFX_ITEMS_DROP_CROWBAR
	pickup_sound = SFX_ITEMS_PICKUP_CROWBAR
	var/on = 0

TRACKED(/obj/item/melee/telebaton, on)

CAPABILITIES(/obj/item/melee/telebaton)
	op("toggle", in_hand(), label("Extend or collapse baton"), then(PROC_REF(baton_toggled)))

/// The native held-item activation preserves the complete equipment change.
/obj/item/melee/telebaton/proc/baton_toggled(datum/act/op/A)
	var/mob/user = A.actor
	set_on(!on)
	if(on)
		act_message(user, null, MSG_SELF(span_warning("You extend the baton.")), \
			MSG_OTHERS(span_warning("With a flick of their wrist, %U% extends their telescopic baton.")), \
			MSG_BLIND("You hear an ominous click."))
		icon_state = "telebaton1"
		item_state = icon_state
		w_class = ITEMSIZE_NORMAL
		force = 15//quite robust
		attack_verb = list("smacked", "struck", "slapped")
	else
		act_message(user, null, MSG_SELF(span_notice("You collapse the baton.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " collapses their telescopic baton.")), \
			MSG_BLIND("You hear a click."))
		icon_state = "telebaton0"
		item_state = icon_state
		w_class = ITEMSIZE_SMALL
		force = 3//not so robust now
		attack_verb = list("hit", "punched")

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	play_sfx(src, SFX_WEAPONS_EMPTY)
	add_fingerprint(user)

	if(blood_overlay && forensic_data?.has_blooddna()) //updates blood overlay, if any
		cut_overlays()

		var/icon/I = new /icon(src.icon, src.icon_state)
		I.Blend(new /icon('icons/effects/blood.dmi', rgb(255,255,255)),ICON_ADD)
		I.Blend(new /icon('icons/effects/blood.dmi', "itemblood"),ICON_MULTIPLY)
		blood_overlay = I

		add_overlay(blood_overlay)

	return OP_OK

/obj/item/melee/telebaton/attack(mob/living/target, mob/living/user, target_zone, attack_modifier)
	if(on)
		if(CLUMSY_FAIL_CHANCE(user))
			to_chat(user, span_warning("You club yourself over the head."))
			user.status_at_least(STAT_WEAKENED, 3 * force)
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				H.injure(injury_kind, 2*force, BP_HEAD, src)
			else
				user.injure(injury_kind, 2*force, source = src)
			return ITEM_INTERACT_SUCCESS
	return ..()
