//** Shield Helpers
//These are shared by various items that have shield-like behaviour

//bad_arc is the ABSOLUTE arc of directions from which we cannot block. If you want to fix it to e.g. the user's facing you will need to rotate the dirs yourself.
/proc/check_shield_arc(mob/user, bad_arc, atom/damage_source = null, mob/attacker = null)
	//check attack direction
	var/attack_dir = 0 //direction from the user to the source of the attack
	if(istype(damage_source, /obj/item/projectile))
		var/obj/item/projectile/P = damage_source
		attack_dir = get_dir(get_turf(user), P.starting)
	else if(attacker)
		attack_dir = get_dir(get_turf(user), get_turf(attacker))
	else if(damage_source)
		attack_dir = get_dir(get_turf(user), get_turf(damage_source))

	if(!(attack_dir && (attack_dir & bad_arc)))
		return 1
	return 0

/proc/default_parry_check(mob/user, mob/attacker, atom/damage_source)
	//parry only melee attacks
	if(istype(damage_source, /obj/item/projectile) || (attacker && get_dist(user, attacker) > 1) || user.incapacitated())
		return 0

	//block as long as they are not directly behind us
	var/bad_arc = reverse_direction(user.dir) //arc of directions from which we cannot block
	if(!check_shield_arc(user, bad_arc, damage_source, attacker))
		return 0

	return 1

/obj/item/proc/unique_parry_check(mob/user, mob/attacker, atom/damage_source)	// An overrideable version of the above proc.
	return default_parry_check(user, attacker, damage_source)

/obj/item/shield
	name = "shield"
	var/base_block_chance = 50
	preserve_item = 1
	item_icons = list(
				slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
				slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
				)

/obj/item/shield/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(user.incapacitated())
		return 0

	//block as long as they are not directly behind us
	var/bad_arc = reverse_direction(user.dir) //arc of directions from which we cannot block
	if(check_shield_arc(user, bad_arc, damage_source, attacker))
		if(prob(get_block_chance(user, damage, damage_source, attacker)))
			user.visible_message(span_danger("\The [user] blocks [attack_text] with \the [src]!"))
			return 1
	return 0

/obj/item/shield/proc/get_block_chance(mob/user, damage, atom/damage_source = null, mob/attacker = null)
	return base_block_chance

/obj/item/shield/riot
	name = "riot shield"
	desc = "A shield adept for close quarters engagement.  It's also capable of protecting from less powerful projectiles."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "riot"
	slot_flags = SLOT_BACK
	force = 5.0
	throwforce = 5.0
	throw_speed = 1
	throw_range = 4
	w_class = ITEMSIZE_LARGE
	matter = list(MAT_GLASS = 7500, MAT_STEEL = 1000)
	attack_verb = list("shoved", "bashed")
	var/cooldown = 0 //shield bash cooldown. based on world.time

/obj/item/shield/riot/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(user.incapacitated())
		return 0

	//block as long as they are not directly behind us
	var/bad_arc = reverse_direction(user.dir) //arc of directions from which we cannot block
	if(check_shield_arc(user, bad_arc, damage_source, attacker))
		if(prob(get_block_chance(user, damage, damage_source, attacker)))
			//At this point, we succeeded in our roll for a block attempt, however these kinds of shields struggle to stand up
			//to strong bullets and lasers.  They still do fine to pistol rounds of all kinds, however.
			if(istype(damage_source, /obj/item/projectile))
				var/obj/item/projectile/P = damage_source
				if((is_sharp(P) && P.armor_penetration >= 10) || istype(P, /obj/item/projectile/beam))
					//If we're at this point, the bullet/beam is going to go through the shield, however it will hit for less damage.
					//Bullets get slowed down, while beams are diffused as they hit the shield, so these shields are not /completely/
					//useless.  Extremely penetrating projectiles will go through the shield without less damage.
					user.visible_message(span_danger("\The [user]'s [src.name] is pierced by [attack_text]!"))
					if(P.armor_penetration < 30) //PTR bullets and x-rays will bypass this entirely.
						P.damage = P.damage / 2
					return 0
			//Otherwise, if we're here, we're gonna stop the attack entirely.
			user.visible_message(span_danger("\The [user] blocks [attack_text] with \the [src]!"))
			playsound(src, 'sound/weapons/genhit.ogg', 50, 1)
			return 1
	return 0

/obj/item/shield/riot/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/melee/baton))
		if(cooldown < world.time - 25)
			user.visible_message(span_warning("[user] bashes [src] with [W]!"))
			playsound(src, 'sound/effects/shieldbash.ogg', 50, 1)
			cooldown = world.time
	else
		..()

/*
 * Energy Shield
 */

/obj/item/shield/energy
	name = "energy combat shield"
	desc = "A shield capable of stopping most projectile and melee attacks. It can be retracted, expanded, and stored anywhere."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "eshield"
	item_state = "eshield"
	slot_flags = SLOT_EARS
	flags = NOCONDUCT
	force = 3.0
	throwforce = 5.0
	throw_speed = 1
	throw_range = 4
	w_class = ITEMSIZE_SMALL
	var/lrange = 1.5
	var/lpower = 1.5
	var/lcolor = "#006AFF"
	attack_verb = list("shoved", "bashed")
	var/active = 0
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
			)

/obj/item/shield/energy/handle_shield(mob/user)
	if(!active)
		return 0 //turn it on first!
	. = ..()

	if(.)
		var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
		spark_system.set_up(5, 0, user.loc)
		spark_system.start()
		playsound(src, 'sound/weapons/blade1.ogg', 50, 1)

/obj/item/shield/energy/get_block_chance(mob/user, damage, atom/damage_source = null, mob/attacker = null)
	if(istype(damage_source, /obj/item/projectile))
		var/obj/item/projectile/P = damage_source
		if((is_sharp(P) && damage > 10) || istype(P, /obj/item/projectile/beam))
			return (base_block_chance - round(damage / 3)) //block bullets and beams using the old block chance
	return base_block_chance

/obj/item/shield/energy/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	if (CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_warning("You beat yourself in the head with [src]."))
		user.take_organ_damage(5)
	active = !active
	if (active)
		force = 10
		update_icon()
		w_class = ITEMSIZE_LARGE
		slot_flags = null
		playsound(src, 'sound/weapons/saberon.ogg', 50, 1)
		to_chat(user, span_notice("\The [src] is now active."))

	else
		force = 3
		update_icon()
		w_class = ITEMSIZE_TINY
		slot_flags = SLOT_EARS
		playsound(src, 'sound/weapons/saberoff.ogg', 50, 1)
		to_chat(user, span_notice("\The [src] can now be concealed."))

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	add_fingerprint(user)
	return

/obj/item/shield/energy/update_icon()
	var/mutable_appearance/blade_overlay = mutable_appearance(icon, "[icon_state]_blade")
	if(lcolor)
		blade_overlay.color = lcolor
		color = lcolor
	cut_overlays()		//So that it doesn't keep stacking overlays non-stop on top of each other
	if(active)
		add_overlay(blade_overlay)
		item_state = "[icon_state]_blade"
		set_light(lrange, lpower, lcolor)
	else
		color = "FFFFFF"
		set_light(0)
		item_state = "[icon_state]"

	if(ishuman(usr))
		var/mob/living/carbon/human/H = usr
		H.update_inv_l_hand()
		H.update_inv_r_hand()

/obj/item/shield/energy/click_alt(mob/living/user)
	if(!in_range(src, user))	//Basic checks to prevent abuse
		return
	if(user.incapacitated() || !istype(user))
		to_chat(user, span_warning("You can't do that right now!"))
		return
	if(tgui_alert(user, "Are you sure you want to recolor your shield?", "Confirm Recolor", list("Yes", "No")) == "Yes")
		var/energy_color_input = tgui_color_picker(user,"","Choose Energy Color",lcolor)
		if(energy_color_input)
			lcolor = sanitize_hexcolor(energy_color_input)
		update_icon()

/obj/item/shield/energy/examine(mob/user)
	. = ..()
	. += span_notice("Alt-click to recolor it.")

/obj/item/shield/riot/tele
	name = "telescopic shield"
	desc = "An advanced riot shield made of lightweight materials that collapses for easy storage."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "teleriot0"
	slot_flags = null
	force = 3
	throwforce = 3
	throw_speed = 3
	throw_range = 4
	w_class = ITEMSIZE_NORMAL
	var/active = 0
/*
/obj/item/shield/energy/IsShield()
	if(active)
		return 1
	else
		return 0
*/
/obj/item/shield/riot/tele/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	active = !active
	icon_state = "teleriot[active]"
	playsound(src, 'sound/weapons/empty.ogg', 50, 1)

	if(active)
		force = 8
		throwforce = 5
		throw_speed = 2
		w_class = ITEMSIZE_LARGE
		slot_flags = SLOT_BACK
		to_chat(user, span_notice("You extend \the [src]."))
	else
		force = 3
		throwforce = 3
		throw_speed = 3
		w_class = ITEMSIZE_NORMAL
		slot_flags = null
		to_chat(user, span_notice("[src] can now be concealed."))

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	add_fingerprint(user)
	return


// === merged from shields_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/shield/energy/imperial
	name = "energy scutum"
	desc = "It's really easy to mispronounce the name of this shield if you've only read it in books."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "impshield" // eshield1 for expanded
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi', slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi')

/obj/item/shield/fluff/wolfgirlshield
	name = "Autumn Shield"
	desc = "A shiny silvery shield with a large red leaf symbol in the center."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "wolfgirlshield"
	slot_flags = SLOT_BACK | SLOT_OCLOTHING
	force = 5.0
	throwforce = 5.0
	throw_speed = 2
	throw_range = 6
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi', slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi', slot_back_str = 'icons/vore/custom_items_vr.dmi', slot_wear_suit_str = 'icons/vore/custom_items_vr.dmi')
	attack_verb = list("shoved", "bashed")
	var/cooldown = 0 //shield bash cooldown. based on world.time


/obj/item/shield/riot/explorer
	name = "green explorer shield" //CHOMP explo keep
	desc = "A shield issued to exploration teams to help protect them when advancing into the unknown. It is lighter and cheaper but less protective than some of its counterparts. It has a flashlight straight in the middle to help draw attention."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "explorer_shield"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi'
	)
	base_block_chance = 40
	slot_flags = SLOT_BACK
	var/brightness_on
	brightness_on = 6
	var/on = 0
	var/light_applied
	//var/light_overlay

//POURPEL WHY U NO COVER

/obj/item/shield/riot/explorer/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(brightness_on)
		if(!isturf(user.loc))
			to_chat(user, "You cannot turn the light on while in this [user.loc]")
			return
		on = !on
		to_chat(user, "You [on ? "enable" : "disable"] the shield light.")
		update_flashlight(user)

		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			H.update_inv_l_hand()
			H.update_inv_r_hand()

/obj/item/shield/riot/explorer/proc/update_flashlight(mob/user = null)
	if(on && !light_applied)
		set_light(brightness_on)
		light_applied = 1
	else if(!on && light_applied)
		set_light(0)
		light_applied = 0
	update_icon(user)
	user.update_mob_action_buttons()
	playsound(src, 'sound/weapons/empty.ogg', 15, 1, -3)

/obj/item/shield/riot/explorer/update_icon()
	if(on)
		icon_state = "explorer_shield_lighted"
	else
		icon_state = "explorer_shield"

/obj/item/shield/riot/explorer/purple
	name = "purple explorer shield" //CHOMP explo keep
	desc = "A shield issued to exploration teams to help protect them when advancing into the unknown. It is lighter and cheaper but less protective than some of its counterparts. It has a flashlight straight in the middle to help draw attention. This one is POURPEL"
	icon_state = "explorer_shield_P"

/obj/item/shield/riot/explorer/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/material/knife/machete))
		if(cooldown < world.time - 25)
			user.visible_message(span_warning("[user] bashes [src] with [W]!"))
			playsound(src, 'sound/effects/shieldbash.ogg', 50, 1)
			cooldown = world.time
	else
		..()

/obj/item/shield/riot/explorer/purple/update_icon()
	if(on)
		icon_state = "explorer_shield_P_lighted"
	else
		icon_state = "explorer_shield_P"

/obj/item/shield/primitive
	name = "primitive shield"
	desc = "A defensive object that is little more than planks strapped your arm"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "buckler"
	w_class = ITEMSIZE_LARGE
	base_block_chance = 30
