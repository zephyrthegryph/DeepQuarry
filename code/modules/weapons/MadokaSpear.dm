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

TRACKED(/obj/item/oldtwohanded, wielded)

/obj/item/oldtwohanded/proc/unwield()
	set_wielded(0)
	set_force(combat_of_type(type).force)
	name = "[initial(name)]"

/obj/item/oldtwohanded/proc/wield()
	set_wielded(1)
	set_force(force_wielded)
	name = "[initial(name)] (Wielded)"


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
	acceptance("equip", req_acceptance_unwielded(), mode = ACCEPTANCE_APPEND)
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
		changed(src)

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

/// Shows the mapped sprite, none of the parent's states.
/obj/item/oldtwohanded/offhand/draw(datum/look/look)
	..()
	look.state(null)

//spears, bay edition
/obj/item/oldtwohanded/spear
	icon_state = "spearglass0"
	base_icon = "spearglass"
	name = "spear"
	desc = "A haphazardly-constructed yet still deadly weapon of ancient design."
	w_class = 4.0
	force_wielded = 22 // Was 13, Buffed - RR
	throw_speed = 3
	injury_kind = INJURY_PIERCE

CAPABILITIES(/obj/item/oldtwohanded/spear)
	configure(item_worn(slots = SLOT_BACK))
	configure(item_thrown(force = 20))
	configure(item_combat(force = 14, edge = 0, sharp = 1, attack_verbs = list("attacked", "poked", "jabbed", "torn", "gored")))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE))

/proc/req_acceptance_unwielded()
	return part_make(/datum/entry/part/req/acceptance_leaf/unwielded, list())
/datum/entry/part/req/acceptance_leaf/unwielded/acceptance_reason(datum/act/op/A)
	var/obj/item/oldtwohanded/I = A.target
	return I.wielded ? "unwield it first" : null
/datum/entry/part/req/acceptance_leaf/unwielded/read_keys(datum/act/op/A)
	var/obj/item/oldtwohanded/I = A.target
	return list(list(I, nameof(I.wielded)))
