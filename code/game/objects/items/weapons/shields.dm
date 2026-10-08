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
			act_message(user, src, others = span_danger("%U% blocks [attack_text] with %T%!"))
			return 1
	return 0

/obj/item/shield/proc/get_block_chance(mob/user, damage, atom/damage_source = null, mob/attacker = null)
	return base_block_chance

MATERIAL_MIX(/obj/item/shield/riot, list(MAT_GLASS = 7500, MAT_STEEL = 1000))
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
					act_message(user, src, others = span_danger("%U%'s [src.name] is pierced by [attack_text]!"))
					if(P.armor_penetration < 30) //PTR bullets and x-rays will bypass this entirely.
						P.damage = P.damage / 2
					return 0
			//Otherwise, if we're here, we're gonna stop the attack entirely.
			act_message(user, src, others = span_danger("%U% blocks [attack_text] with %T%!"))
			play_sfx(src, SFX_WEAPONS_GENHIT)
			return 1
	return 0

CAPABILITIES(/obj/item/shield/riot)
	op("baton_bash", item(/obj/item/melee/baton), label("Bash shield"), then(PROC_REF(baton_bashed)), passes())

/obj/item/shield/riot/proc/baton_bashed(datum/act/op/A)
	if(COOLDOWN_FINISHED(src, cooldown))
		act_message(A.actor, src, others = span_warning("%U% bashes %T% with [A.held]!"))
		play_sfx(src, SFX_EFFECTS_SHIELDBASH)
		COOLDOWN_START(src, cooldown, 2.5 SECONDS)
	return OP_OK

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
		fx_sparks(user.loc, 5, FALSE)
		play_sfx(src, SFX_WEAPONS_BLADE1)

/obj/item/shield/energy/get_block_chance(mob/user, damage, atom/damage_source = null, mob/attacker = null)
	if(istype(damage_source, /obj/item/projectile))
		var/obj/item/projectile/P = damage_source
		if((is_sharp(P) && damage > 10) || istype(P, /obj/item/projectile/beam))
			return (base_block_chance - round(damage / 3)) //block bullets and beams using the old block chance
	return base_block_chance

TRACKED(/obj/item/shield/energy, active)
TRACKED(/obj/item/shield/energy, lcolor)

CAPABILITIES(/obj/item/shield/energy)
	op("toggle", in_hand(), label("Toggle shield"), then(PROC_REF(shield_toggled)))
	op("recolor", inputs(hand(), in_hand()), answers(INTENT_TOGGLE), label("Recolor shield"),
		needs(req_adjacent()),
		part_make(/datum/entry/part/asks, list("type" = /datum/prompt/yes_no, "fields" = list("question" = "Are you sure you want to recolor your shield?", "title" = "Confirm Recolor", "timeout" = 0), "step" = "confirm", "resume" = CAPTURE, "keeps" = 0, "confirms" = TRUE)),
		asks(/datum/prompt/color/energy_shield, keeps = 0), then(PROC_REF(shield_recolored)))

/// The color starts from the live shield state when this second request opens, after confirmation.
/datum/prompt/color/energy_shield
	title = "Choose Energy Color"
	timeout = 0

/datum/prompt/color/energy_shield/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/obj/item/shield/energy/shield = asking.target
		if(istype(shield))
			default = shield.lcolor

/obj/item/shield/energy/proc/shield_toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if (CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_warning("You beat yourself in the head with [src]."))
		user.injure(INJURY_BLUNT, 5, source = src)
	set_active(!active)
	if (active)
		force = 10
		w_class = ITEMSIZE_LARGE
		slot_flags = null
		play_sfx(src, SFX_WEAPONS_SABERON)
		to_chat(user, span_notice("\The [src] is now active."))

	else
		force = 3
		w_class = ITEMSIZE_TINY
		slot_flags = SLOT_EARS
		play_sfx(src, SFX_WEAPONS_SABEROFF)
		to_chat(user, span_notice("\The [src] can now be concealed."))

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		H.update_inv_l_hand()
		H.update_inv_r_hand()

	add_fingerprint(user)
	return OP_OK

/// The look: the blade over the hilt in the shield's colour, lit while active.
/obj/item/shield/energy/draw(datum/look/look)
	..()
	var/base = look.state_so_far(src)
	if(lcolor)
		look.set_color(lcolor)
	if(active)
		look.overlay(look_appearance(icon, "[base]_blade", color = lcolor))
		look.held_state("[base]_blade")
		look.light(lrange, lpower, lcolor)
	else
		look.set_color("FFFFFF")
		look.held_state(base)
		look.light_off()

/obj/item/shield/energy/proc/shield_recolored(datum/act/op/A)
	var/datum/prompt/color/choice = A.answer
	if(!istype(choice) || !choice.value)
		return OP_REFUSED
	set_lcolor(sanitize_hexcolor(choice.value))
	return OP_OK

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
TRACKED(/obj/item/shield/riot/tele, active)

CAPABILITIES(/obj/item/shield/riot/tele)
	op("toggle", in_hand(), label("Extend or retract shield"), then(PROC_REF(shield_toggled)))

/obj/item/shield/riot/tele/proc/shield_toggled(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	icon_state = "teleriot[active]"
	play_sfx(src, SFX_WEAPONS_EMPTY)

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
	return OP_OK


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
	name = "green explorer shield"
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

//POURPEL WHY U NO COVER

/// Old attack_self.
/obj/item/shield/riot/explorer/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(brightness_on)
		if(!isturf(user.loc))
			to_chat(user, "You cannot turn the light on while in this [user.loc]")
			return TRUE
		on = !on
		to_chat(user, "You [on ? "enable" : "disable"] the shield light.")
		update_flashlight(user)

		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			H.update_inv_l_hand()
			H.update_inv_r_hand()
	return TRUE

/obj/item/shield/riot/explorer/proc/update_flashlight(mob/user = null)
	if(on && !light_applied)
		set_light(brightness_on)
		light_applied = 1
	else if(!on && light_applied)
		set_light(0)
		light_applied = 0
	changed(src)
	user.update_mob_action_buttons()
	play_sfx(src, SFX_WEAPONS_EMPTY, 0.3, extrarange = -3)

/// The look (the draw sweep: from its template).
/obj/item/shield/riot/explorer/draw(datum/look/look)
	..()
	look.state("explorer_shield[on ? "_lighted" : ""]")

/obj/item/shield/riot/explorer/purple
	name = "purple explorer shield"
	desc = "A shield issued to exploration teams to help protect them when advancing into the unknown. It is lighter and cheaper but less protective than some of its counterparts. It has a flashlight straight in the middle to help draw attention. This one is POURPEL"
	icon_state = "explorer_shield_P"

CAPABILITIES(/obj/item/shield/riot/explorer)
	op("machete_bash", item(/obj/item/material/knife/machete), label("Bash shield"), then(PROC_REF(machete_bashed)), passes())
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/obj/item/shield/riot/explorer/proc/machete_bashed(datum/act/op/A)
	if(COOLDOWN_FINISHED(src, cooldown))
		act_message(A.actor, src, others = span_warning("%U% bashes %T% with [A.held]!"))
		play_sfx(src, SFX_EFFECTS_SHIELDBASH)
		COOLDOWN_START(src, cooldown, 2.5 SECONDS)
	return OP_OK

/// The look (the draw sweep: from its template).
/obj/item/shield/riot/explorer/purple/draw(datum/look/look)
	..()
	look.state("explorer_shield_P[on ? "_lighted" : ""]")

/obj/item/shield/primitive
	name = "primitive shield"
	desc = "A defensive object that is little more than planks strapped your arm"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "buckler"
	w_class = ITEMSIZE_LARGE
	base_block_chance = 30
