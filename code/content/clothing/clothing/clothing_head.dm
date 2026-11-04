///////////////////////////////////////////////////////////////////////
//Head


/obj/item/clothing/head
	light_on = FALSE // its declared light starts switched off (code/modules/lighting/glow.dm)
	name = DEVELOPER_WARNING_NAME // "Head"
	icon = 'icons/inventory/head/item.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_hats.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_hats.dmi',
		)
	w_class = ITEMSIZE_SMALL
	blood_sprite_state = "helmetblood"


	var/light_overlay = "helmet_light"
	/// The helmet lamp is switched on. The light it casts is derived from this by the look (head_glow()).
	var/lamp_lit = FALSE

	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/head/mob_vox.dmi'
		)
	helmet_handling = TRUE

CAPABILITIES(/obj/item/clothing/head)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	configure(atom_rules(light_system = MOVABLE_LIGHT_DIRECTIONAL))
	configure(movable_motion(cone_y = 11))
	look_glow(PROC_REF(head_glow), when = nameof(lamp_lit))
	configure(item_worn(covers = HEAD, slots = SLOT_HEAD))
	configure(item_protection(heat_parts = HEAD, cold_parts = HEAD))
	configure(item_sounds(drop = SFX_ITEMS_DROP_HAT, pickup = SFX_ITEMS_PICKUP_HAT))
	op("head_light_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 2), label("Head light self"), then(PROC_REF(head_light_self)))
	op("head_robot_pick_up", remote(), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), priority(OP_PRIORITY_DEFAULT - 1), label("Pick up hat"), then(PROC_REF(head_robot_pick_up)))
	// A cyborg picking the hat up (head_robot_pick_up()): three seconds beside it.
	op("robot_hat_pickup", ai(), needs(req_capable()), wait(3 SECONDS), then(PROC_REF(robot_hat_done)))
	op("head_silicon_wear", remote(), priority(OP_PRIORITY_DEFAULT - 2), label("Wear hat"), then(PROC_REF(head_silicon_wear)))

/// Old attack_self: toggle the helmet light. Returns FALSE as the old body returned nothing,
/// so subtypes' legacy attack_self bodies that ran after ..() still run.
/obj/item/clothing/head/proc/head_light_self(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling)
		return OP_DECLINE
	if(glow_of_type(type).range)
		if(!isturf(user.loc))
			to_chat(user, "You cannot toggle the light while in this [user.loc]")
			return OP_DECLINE
		update_flashlight(user)
		to_chat(user, "You [lamp_lit ? "enable" : "disable"] the helmet light.")
	return OP_DECLINE

/// The light the lamp casts: its type's range (a look that goes dark zeroes the instance's range), the power and colour it has.
/obj/item/clothing/head/proc/head_glow(datum/act/A)
	return GLOW(glow_of_type(type).range, glow_of(src).power, glow_of(src).color)

/obj/item/clothing/head/proc/update_flashlight(mob/user = null)
	set_lamp_lit(!lamp_lit)

	user.update_mob_action_buttons()

/// Old attack_ai: a silicon wears the hat; otherwise the default.
/obj/item/clothing/head/proc/head_silicon_wear(datum/act/op/A)
	var/mob/user = A.actor
	return mob_wear_hat(user) ? OP_OK : OP_DECLINE

/obj/item/clothing/head/proc/smashed_by(datum/act/hit/generic/A)
	if(!mob_wear_hat(A.attacker))
		return HOOK_DECLINE
	return OP_OK

/obj/item/clothing/head/proc/mob_wear_hat(mob/user)
	if(!Adjacent(user))
		return 0
	var/success = user.receive_loose_hat(src)

	if(!success)
		return 0
	else if(success == 2)
		to_chat(user, span_warning("You are already wearing a hat."))
	else if(success == 1)
		to_chat(user, span_notice("You crawl under \the [src]."))
	return 1

/// The helmet's lit lamp on the item; the worn lamp is built by make_worn_icon() (clothing_icons.dm). A change of the lamp redraws the head slot
/// of whoever wears it (an effect of the look: the worn overlay stays the mob's own path).
/obj/item/clothing/head/draw(datum/look/look)
	..()
	if(lamp_lit)
		look.overlay(look_cached_image("[light_overlay]-item", 'icons/obj/light_overlays.dmi', light_overlay))

/obj/item/clothing/head/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	. = ..()

/// Old attack_robot: ran ..() first (attack_ai: wear the hat, else the item default), then an
/// adjacent cyborg starts picking the hat up.
/obj/item/clothing/head/proc/head_robot_pick_up(datum/act/op/A)
	var/mob/living/silicon/robot/user = A.actor
	if(!mob_wear_hat(user))
		actor_use_default(/datum/input_adapter/ai, user, src)

	if(!Adjacent(user))
		return OP_OK

	balloon_alert(user, "picking up hat...")
	perform_op(user, src, "robot_hat_pickup", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
	return OP_OK

/obj/item/clothing/head/proc/robot_hat_done(datum/act/op/A)
	var/mob/living/silicon/robot/user = A.actor
	if(!Adjacent(user) || user.incapacitated())
		return
	user.place_on_head(src)
	balloon_alert(user, "picked up hat")

/obj/item/clothing/head
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/head/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/head/mob_werebeast.dmi')
