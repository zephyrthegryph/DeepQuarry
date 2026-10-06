/* Two-handed Weapons
 * Contains:
 * 		Twohanded
 *		Fireaxe
 *		Double-Bladed Energy Swords
 */

/*##################################################################
##################### TWO HANDED WEAPONS BE HERE~ -Agouri :3 ########
####################################################################*/

//Rewrote TwoHanded weapons stuff and put it all here. Just copypasta fireaxe to make new ones ~Carn
//This rewrite means we don't have two variables for EVERY item which are used only by a few weapons.
//It also tidies stuff up elsewhere.

/*
 * Twohanded
 */
/obj/item/oldtwohanded
	var/wielded = 0
	var/force_wielded = 0
	var/wieldsound = null
	var/unwieldsound = null
	var/base_icon

/obj/item/oldtwohanded/proc/unwield()
	wielded = 0
	force = initial(force)
	name = "[initial(name)]"
	changed(src)

/obj/item/oldtwohanded/proc/wield()
	wielded = 1
	force = force_wielded
	name = "[initial(name)] (Wielded)"
	changed(src)

TYPE_TABLE(/obj/item/oldtwohanded, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/oldtwohanded/proc/not_wielded, "unwield it first"))))

/obj/item/oldtwohanded/proc/not_wielded()
	return !wielded

/obj/item/oldtwohanded/dropped(mob/user, equipping, slot)
	//handles unwielding a twohanded weapon when dropped as well as clearing up the offhand
	..()
	if(user)
		var/obj/item/oldtwohanded/O = user.get_inactive_hand()
		if(istype(O))
			O.unwield()
	return	unwield()

/obj/item/oldtwohanded/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	drawn_state = look.state("[base_icon][wielded]")
	look.held_state(drawn_state)

/obj/item/oldtwohanded/pickup(mob/user)
	unwield()

CAPABILITIES(/obj/item/oldtwohanded)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/oldtwohanded/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor

	if(wielded) //Trying to unwield it
		unwield()
		to_chat(user, span_notice("You are now carrying the [name] with one hand."))
		if (src.unwieldsound)
			playsound(src.loc, unwieldsound, 50, 1)

		var/obj/item/oldtwohanded/offhand/O = user.get_inactive_hand()
		if(O && istype(O))
			O.unwield()

	else //Trying to wield it
		if(user.get_inactive_hand())
			to_chat(user, span_warning("You need your other hand to be empty"))
			return TRUE
		wield()
		to_chat(user, span_notice("You grab the [initial(name)] with both hands."))
		if (src.wieldsound)
			playsound(src.loc, wieldsound, 50, 1)

		var/obj/item/oldtwohanded/offhand/O = new(user) ////Let's reserve his other hand~
		O.name = "[initial(name)] - offhand"
		O.desc = "Your second grip on the [initial(name)]"
		user.put_in_inactive_hand(O)

	if(istype(user,/mob/living/carbon/human))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	return TRUE

///////////OFFHAND///////////////
/obj/item/oldtwohanded/offhand
	w_class = 5.0
	icon_state = "offhand"
	name = "offhand"

/obj/item/oldtwohanded/offhand/unwield()
	spent(src)

/obj/item/oldtwohanded/offhand/wield()
	spent(src)

/// The look (the draw sweep: from APPEARANCE_NONE).
/obj/item/oldtwohanded/offhand/draw(datum/look/look)
	..()
	// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers
	look.state(null)

//spears, bay edition
/obj/item/oldtwohanded/spear
	icon_state = "spearglass0"
	base_icon = "spearglass"
	name = "spear"
	desc = "A haphazardly-constructed yet still deadly weapon of ancient design."
	force = 14
	w_class = 4.0
	slot_flags = SLOT_BACK
	force_wielded = 22 // Was 13, Buffed - RR
	throwforce = 20
	throw_speed = 3
	edge = 0
	sharp = 1
	injury_kind = INJURY_PIERCE
	hitsound = SFX_WEAPONS_BLADESLICE
	attack_verb = list("attacked", "poked", "jabbed", "torn", "gored")
