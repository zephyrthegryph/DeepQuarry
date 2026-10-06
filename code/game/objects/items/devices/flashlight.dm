#define CAN_USE "can_use"
/*
 * Contains:
 *		Flashlights
 *		Lamps
 *		Flares
 *		Chemlights
 *		Slime Extract
 */

/*
 * Flashlights
 */

MATERIAL_MIX(/obj/item/flashlight, list(MAT_STEEL = 50,MAT_GLASS = 20))
/obj/item/flashlight
	name = "flashlight"
	desc = "A hand-held emergency light."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "flashlight"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	actions_types = list(/datum/action/item_action/toggle_flashlight)

	light_system = MOVABLE_LIGHT_DIRECTIONAL
	light_range = 4 //luminosity when on
	light_power = 0.8	//lighting power when on
	light_color = "#FFFFFF" //LIGHT_COLOR_INCANDESCENT_FLASHLIGHT	//lighting colour when on
	light_cone_y_offset = -7

	var/obj/item/cell/cell
	var/cell_type = /obj/item/cell/device
	var/power_usage = 1
	var/flickering = FALSE
	var/single_use = FALSE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	///Var for attack_self chain
	var/special_handling = FALSE

CAPABILITIES(/obj/item/flashlight)
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell_type))
	drag_onto(PROC_REF(mousedrop_input))
	op("switch", in_hand(), needs(req(PROC_REF(can_switch), because = PROC_REF(switch_refusal))), then(PROC_REF(interaction_self)))
	// held in the other hand, an empty hand takes the cell out (otherwise the click declines to pick up); a device cell goes in
	op("take_cell", hand(), label("Remove cell"), then(PROC_REF(interaction_hand)))
	op("insert_cell", item(/obj/item/cell), label("Install cell"), when(nameof(power_use)), then(PROC_REF(interaction_item)))


/obj/item/flashlight/Initialize(mapload)
	. = ..()
	update_brightness()

OM_FIELD(/obj/item/flashlight, on, 0, CHANGE_EXPLICIT)
OM_FIELD(/obj/item/flashlight, power_use, 1, CHANGE_EXPLICIT)
// Battery drain runs while a powered light is on.
DECLARE_PERIODIC_WHILE_ALL(/obj/item/flashlight, PERIODIC_SLOW, list("on", "power_use"))

/obj/item/flashlight/get_cell()
	return cell

/obj/item/flashlight/periodic_step()
	if(!cell)
		return

	if(power_usage)
		if(cell.use(power_usage) != power_usage) // we weren't able to use our full power_usage amount!
			visible_message(span_warning("\The [src] flickers before going dull."))
			play_sfx(src, SFX_EFFECTS_SPARKS3) // Small cue that your light went dull in your pocket. //
			set_on(0)
			update_brightness()

/obj/item/flashlight/proc/update_brightness()
	if(on)
		icon_state = "[initial(icon_state)]-on"
	else
		icon_state = initial(icon_state)
	set_light_on(on)
	if(light_system == STATIC_LIGHT)
		update_light()

/obj/item/flashlight/examine(mob/user)
	. = ..()
	if(power_use && cell)
		. += "\The [src] has a \the [cell] attached."

		if(cell.charge <= cell.maxcharge*0.25)
			. += "It appears to have a low amount of power remaining."
		else if(cell.charge > cell.maxcharge*0.25 && cell.charge <= cell.maxcharge*0.5)
			. += "It appears to have an average amount of power remaining."
		else if(cell.charge > cell.maxcharge*0.5 && cell.charge <= cell.maxcharge*0.75)
			. += "It appears to have an above average amount of power remaining."
		else if(cell.charge > cell.maxcharge*0.75 && cell.charge <= cell.maxcharge)
			. += "It appears to have a high amount of power remaining."

/// Requirement: the light can be switched now (a spent single-use light and a special one are the effect's business).
/obj/item/flashlight/proc/can_switch(datum/act/op/A)
	return isnull(flashlight_switch_refusal(src, A.actor))

/obj/item/flashlight/proc/switch_refusal(datum/act/op/A)
	return flashlight_switch_refusal(src, A.actor)

/// Why `user` can't switch `light` now, or null.
/proc/flashlight_switch_refusal(obj/item/flashlight/light, mob/user)
	READS_FROM() // a flicker, the user's place and the cell's charge are asked when the switch is flicked
	if((light.single_use && light.on) || light.special_handling)
		return null
	if(light.flickering)
		return "The light is currently malfunctioning and you're unable to adjust it." //To prevent some lighting anomalities.
	if(light.power_use)
		if(!isturf(user.loc))
			return "You cannot turn the light on while in this [user.loc]." //To prevent some lighting anomalities.
		if(!light.cell || light.cell.charge == 0)
			return "You flick the switch on it, but nothing happens."
	return null

/// Old attack_self: switch the light (a flare or a glowstick says more, in its override of switch_light()).
/obj/item/flashlight/proc/interaction_self(datum/act/op/A)
	return switch_light(A.actor) ? OP_OK : OP_DECLINE

/obj/item/flashlight/proc/switch_light(mob/user)
	if(single_use && on)
		return FALSE
	if(special_handling)
		return FALSE
	set_on(!on)
	play_sfx(src, SFX_WEAPONS_EMPTY, 0.3, extrarange = -3)
	update_brightness()
	user.update_mob_action_buttons()
	return CAN_USE

/obj/item/flashlight/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	add_fingerprint(user)
	if(on && user.zone_sel.selecting == O_EYES)

		if(CLUMSY_FAIL_CHANCE(user))	//too dumb to use flashlight properly
			return ..()	//just hit them in the head

		var/mob/living/carbon/human/H = M	//mob has protective eyewear
		if(istype(H))
			for(var/obj/item/clothing/C in list(H.get_equipped_item(SLOT_ID_HEAD),H.get_equipped_item(SLOT_ID_MASK),H.get_equipped_item(SLOT_ID_EYES)))
				if(istype(C) && (C.body_parts_covered & EYES))
					to_chat(user, span_warning("You're going to need to remove [C.name] first."))
					return ITEM_INTERACT_FAILURE

			var/obj/item/organ/vision
			if(H.species.vision_organ)
				vision = H.organ_in(H.species.vision_organ)
			if(!vision)
				act_message(user, src, MSG_SELF(span_notice("You direct %T% at [M]'s face.")), \
					MSG_OTHERS(span_infoplain(span_bold("%U%") + " directs %T% at [M]'s face.")))
				to_chat(user, span_warning("You can't find any [H.species.vision_organ ? H.species.vision_organ : "eyes"] on [H]!"))
				user.setClickCooldown(user.get_attack_speed(src))
				return ITEM_INTERACT_FAILURE

			act_message(user, src, MSG_SELF(span_notice("You direct %T% to [M]'s eyes.")), \
				MSG_OTHERS(span_infoplain(span_bold("%U%") + " directs %T% to [M]'s eyes.")))
			if(H != user)	//can't look into your own eyes buster
				if(M.stat == DEAD || M.blinded)	//mob is dead or fully blind
					to_chat(user, span_warning("\The [M]'s pupils do not react to the light!"))
					return ITEM_INTERACT_SUCCESS
				if(M.has_mutation(XRAY))
					to_chat(user, span_notice("\The [M] pupils give an eerie glow!"))
				if(vision.is_bruised())
					to_chat(user, span_warning("There's visible damage to [M]'s [vision.name]!"))
				else if(M.has_status(STAT_BLURRY))
					to_chat(user, span_notice("\The [M]'s pupils react slower than normally."))
				if(M.injury_load(INJURY_CATEGORY_NEURAL) > 15)
					to_chat(user, span_notice("There's visible lag between left and right pupils' reactions."))

				var/list/pinpoint = list(REAGENT_ID_OXYCODONE=1,REAGENT_ID_TRAMADOL=5)
				var/list/dilating = list(REAGENT_ID_BLISS=5,REAGENT_ID_AMBROSIAEXTRACT=5,REAGENT_ID_MINDBREAKER=1)
				if(M.reagents.has_any_reagent(pinpoint) || H.ingested.has_any_reagent(pinpoint))
					to_chat(user, span_notice("\The [M]'s pupils are already pinpoint and cannot narrow any more."))
				else if(M.reagents.has_any_reagent(dilating) || H.ingested.has_any_reagent(dilating))
					to_chat(user, span_notice("\The [M]'s pupils narrow slightly, but are still very dilated."))
				else
					to_chat(user, span_notice("\The [M]'s pupils narrow."))

			user.setClickCooldown(user.get_attack_speed(src)) //can be used offensively
			M.flash_eyes()
			return ITEM_INTERACT_SUCCESS
	else
		return ..()

/// Old attack_hand: the hand on a light held in the other hand takes its cell out (anything else is the pick up).
/obj/item/flashlight/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src && cell)
		cell.update_icon()
		user.put_in_hands(cell)
		own_take(src, nameof(cell))
		to_chat(user, span_notice("You remove the cell from the [src]."))
		play_sfx(src, SFX_MACHINES_BUTTON)
		set_on(0)
		update_brightness()
		return OP_OK
	return OP_DECLINE

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/flashlight/proc/mousedrop_input(datum/act/input/A)
	if(!handle_inventory_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/flashlight/proc/handle_inventory_drop(mob/user, obj/over_object)
	if(!canremove)
		return TRUE

	if (ishuman(user) || issmall(user)) //so monkeys can take off their backpacks -- Urist

		if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech. why?
			return TRUE

		if (!( istype(over_object, /atom/movable/screen) ))
			return FALSE

		//makes sure that the thing is equipped, so that we can't drag it into our hand from miles away.
		//there's got to be a better way of doing this.
		if (!(src.loc == user) || (src.loc && src.loc.loc == user))
			return TRUE

		if (( user.restrained() ) || ( user.stat ))
			return TRUE

		if ((src.loc == user) && !(istype(over_object, /atom/movable/screen)) && !user.unEquip(src))
			return TRUE

		switch(over_object.name)
			if("r_hand")
				user.put_in_r_hand(src)
			if("l_hand")
				user.put_in_l_hand(src)
		src.add_fingerprint(user)
	return TRUE

/// Old attackby: a device cell goes into a powered light.
/obj/item/flashlight/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!power_use)
		return OP_DECLINE
	if(istype(W, /obj/item/cell))
		if(istype(W, /obj/item/cell/device))
			if(!cell)
				if(!move_into(src, nameof(src.cell), W, user))
					return OP_DECLINE
				to_chat(user, span_notice("You install a cell in \the [src]."))
				play_sfx(src, SFX_MACHINES_BUTTON)
				update_brightness()
			else
				to_chat(user, span_notice("\The [src] already has a cell."))
		else
			to_chat(user, span_notice("\The [src] cannot use that type of cell."))
	return OP_OK

/obj/item/flashlight/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!on)
		return
	if(light_system == MOVABLE_LIGHT_DIRECTIONAL)
		var/datum/overlay_lighting/OL = overlay_light
		if(!OL)
			return
		var/turf/T = get_turf(target)
		OL.place_directional_light(T)

/obj/item/flashlight/proc/flicker(amount = rand(10, 20), flicker_color, forced)
	if(flickering)
		return
	if(!flicker_color)
		flicker_color = light_color //If we don't have a flicker color, use our current light color.
	if((!power_use && !forced) || (!power_usage && !forced))
		return //We don't use power / have no power, so we're probably a flare or dead.
	flickering = TRUE
	var/original_color = light_color
	var/original_on = on
	var/datum/overlay_lighting/OL = overlay_light //BEWARE, ESOTERIC BULLSHIT HERE.
	if(flicker_color && light_color != flicker_color)
		set_light_color(flicker_color)
		OL.directional_atom.color = flicker_color
	do_flicker(amount, flicker_color, original_color, original_on, OL, 1)

/// Args:
/// amount is how many timer to flicker.
/// flicker_color is what to set the flashlight to when we flicker.
/// original_color is what our original color was prior to flickering
/// original_on is if we were originally on or not.
/// OL is our overlay for lighting.
/// ticker is how many times we have flickered so far.
/obj/item/flashlight/proc/do_flicker(amount = rand(10, 20), flicker_color, original_color, original_on, datum/overlay_lighting/OL, ticker)
	if(ticker >= amount) //We have flickered enough times. Terminate the cycle.
		finish_flicker(original_color, original_on, OL)
		return
	set_on(!on)
	update_brightness()
	if(!on) // Only play when the light turns off.
		play_sfx(src, SFX_EFFECTS_LIGHT_FLICKER)
	after(src, rand(0.5 SECONDS, 1.5 SECONDS), PROC_REF(do_flicker), with = list(amount, flicker_color, original_color, original_on, OL, ++ticker))

/obj/item/flashlight/proc/finish_flicker(original_color, original_on, datum/overlay_lighting/OL)
	set_light_color(original_color)
	OL.directional_atom?.color = original_color
	set_on(original_on)
	flickering = FALSE
	update_brightness()

/obj/item/flashlight/pen
	name = "penlight"
	desc = "A pen-sized light, used by medical staff."
	icon_state = "penlight"
	item_state = "pen"
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY
	slot_flags = SLOT_EARS
	light_range = 2
	w_class = ITEMSIZE_TINY
	power_use = 0
	cell_type = null

/obj/item/flashlight/color	//Default color is blue
	name = "blue flashlight"
	desc = "A small flashlight. This one is blue."
	icon_state = "flashlight_blue"

/obj/item/flashlight/color/green
	name = "green flashlight"
	desc = "A small flashlight. This one is green."
	icon_state = "flashlight_green"

/obj/item/flashlight/color/purple
	name = "purple flashlight"
	desc = "A small flashlight. This one is purple."
	icon_state = "flashlight_purple"

/obj/item/flashlight/color/red
	name = "red flashlight"
	desc = "A small flashlight. This one is red."
	icon_state = "flashlight_red"

/obj/item/flashlight/color/orange
	name = "orange flashlight"
	desc = "A small flashlight. This one is orange."
	icon_state = "flashlight_orange"

/obj/item/flashlight/color/yellow
	name = "yellow flashlight"
	desc = "A small flashlight. This one is yellow."
	icon_state = "flashlight_yellow"

MATERIAL_MIX(/obj/item/flashlight/maglight, list(MAT_STEEL = 200,MAT_GLASS = 50))
/obj/item/flashlight/maglight
	name = "maglight"
	desc = "A very, very heavy duty flashlight."
	icon_state = "maglight"
	light_color = LIGHT_COLOR_FLUORESCENT_FLASHLIGHT
	force = 10
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	attack_verb = list ("smacked", "thwacked", "thunked")
	hitsound = SFX_SWING_HIT

/obj/item/flashlight/drone
	name = "low-power flashlight"
	desc = "A miniature lamp, that might be used by small robots."
	icon_state = "penlight"
	item_state = null
	light_range = 2
	w_class = ITEMSIZE_TINY
	power_use = 0
	cell_type = null

/*
 * Lamps
 */

// pixar desk lamp
/obj/item/flashlight/lamp
	name = "desk lamp"
	desc = "A desk lamp with an adjustable mount."
	icon_state = "lamp"
	force = 10
	center_of_mass_x = 13
	center_of_mass_y = 11
	light_range = 5
	w_class = ITEMSIZE_LARGE
	power_use = 0
	cell_type = null
	on = 1
	light_system = STATIC_LIGHT

/obj/item/flashlight/lamp/proc/lamp_toggle_light_effect(datum/act/op/A)
	var/mob/user = A.actor

	if(!user.stat)
		attack_self(user)

// green-shaded desk lamp
/obj/item/flashlight/lamp/green
	desc = "A classic green-shaded desk lamp."
	icon_state = "lampgreen"
	center_of_mass_x = 15
	center_of_mass_y = 11
	light_color = "#FFC58F"

// clown lamp
/obj/item/flashlight/lamp/clown
	desc = "A whacky banana peel shaped lamp."
	icon_state = "bananalamp"
	center_of_mass_x = 15
	center_of_mass_y = 11

/*
 * Flares
 */

/obj/item/flashlight/flare
	name = "flare"
	desc = "A red standard-issue flare. There are instructions on the side reading 'pull cord, make light'."
	w_class = ITEMSIZE_TINY // These can fit in more places.
	light_range = 8 // Pretty bright.
	light_power = 0.8
	light_color = LIGHT_COLOR_FLARE
	icon_state = "flare"
	item_state = "flare"
	actions_types = list() //just pull it manually, neckbeard.
	var/fuel = 800
	var/on_damage = 7
	var/produce_heat = 1500
	power_use = 0
	cell_type = null
	drop_sound = SFX_ITEMS_DROP_GLOVES
	pickup_sound = SFX_ITEMS_PICKUP_GLOVES
	light_system = MOVABLE_LIGHT
	single_use = TRUE

// Flares burn fuel while lit (they have no cell, so power_use is off).
DECLARE_PERIODIC_WHILE(/obj/item/flashlight/flare, PERIODIC_SLOW, "on")

CAPABILITIES(/obj/item/flashlight/flare)
	rolls(nameof(fuel), PROC_REF(roll_fuel))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/flashlight/flare/proc/roll_fuel(datum/roller/R)
	return fuel + (R.number(0, 200))

/obj/item/flashlight/flare/periodic_step()
	var/turf/pos = get_turf(src)
	if(pos)
		pos.hotspot_expose(produce_heat, 5)
	fuel = max(fuel - 1, 0)
	if(!fuel)
		turn_off()
		src.icon_state = "[initial(icon_state)]-empty"

/obj/item/flashlight/flare/proc/turn_off()
	set_on(0)
	src.force = initial(src.force)
	src.injury_kind = initial(src.injury_kind)
	update_brightness()

/obj/item/flashlight/flare/switch_light(mob/user)
	. = ..()
	if(.)
		return TRUE
	// Usual checks
	if(!fuel || on)
		to_chat(user, span_notice("It's out of fuel."))
		return
	// All good, turn it on.
	if(. == CAN_USE)
		act_message(user, null, MSG_SELF(span_notice("You pull the cord on the flare, activating it!")), MSG_OTHERS(span_notice("%U% activates the flare.")))
		force = on_damage
		injury_kind = INJURY_BURN

/obj/item/flashlight/flare/proc/ignite() //Used for flare launchers.
	set_on(!on)
	update_brightness()
	force = on_damage
	injury_kind = INJURY_BURN
	return 1

/*
 * Chemlights
 */

/obj/item/flashlight/glowstick
	name = "green glowstick"
	desc = "A green military-grade chemical light."
	w_class = ITEMSIZE_TINY // These can fit in more places.
	light_system = MOVABLE_LIGHT
	light_range = 4
	light_power = 0.9
	light_color = "#49F37C"
	icon_state = "glowstick_green"
	item_state = "glowstick_green"
	var/fuel = 1600
	power_use = FALSE
	cell_type = null
	single_use = TRUE

DECLARE_PERIODIC_WHILE(/obj/item/flashlight/glowstick, PERIODIC_SLOW, "on")

CAPABILITIES(/obj/item/flashlight/glowstick)
	rolls(nameof(fuel), PROC_REF(roll_fuel))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/flashlight/glowstick/proc/roll_fuel(datum/roller/R)
	return fuel + (R.number(0, 400))

/obj/item/flashlight/glowstick/periodic_step()
	fuel = max(fuel - 1, 0)
	if(!fuel)
		turn_off()
		src.icon_state = "[initial(icon_state)]-empty"

/obj/item/flashlight/glowstick/proc/turn_off()
	set_on(FALSE)
	update_brightness()

/obj/item/flashlight/glowstick/switch_light(mob/user)
	. = ..()
	if(.)
		return TRUE
	if(!fuel || on)
		to_chat(user, span_notice("The glowstick has already been turned on."))
		return

	if(. == CAN_USE)
		act_message(user, src, MSG_SELF(span_notice("You crack and shake %T%, turning it on!")), MSG_OTHERS(span_notice("%U% cracks and shakes \the [name].")))

/obj/item/flashlight/glowstick/red
	name = "red glowstick"
	desc = "A red military-grade chemical light."
	light_color = "#FC0F29"
	icon_state = "glowstick_red"
	item_state = "glowstick_red"

/obj/item/flashlight/glowstick/blue
	name = "blue glowstick"
	desc = "A blue military-grade chemical light."
	light_color = "#599DFF"
	icon_state = "glowstick_blue"
	item_state = "glowstick_blue"

/obj/item/flashlight/glowstick/orange
	name = "orange glowstick"
	desc = "A orange military-grade chemical light."
	light_color = "#FA7C0B"
	icon_state = "glowstick_orange"
	item_state = "glowstick_orange"

/obj/item/flashlight/glowstick/yellow
	name = "yellow glowstick"
	desc = "A yellow military-grade chemical light."
	light_color = "#FEF923"
	icon_state = "glowstick_yellow"
	item_state = "glowstick_yellow"

/obj/item/flashlight/glowstick/radioisotope
	name = "radioisotope glowstick"
	desc = "A radioisotope powered chemical light. Escaping particles light up the area far brighter on similar levels to flares and for longer"
	icon_state = "glowstick_isotope"
	item_state = "glowstick_isotope"

	light_range = 8
	light_power = 0.1
	light_color = "#49F37C"

#undef CAN_USE

/// Old object verbs.
CAPABILITIES(/obj/item/flashlight/lamp)
	op("lamp_toggle_light_effect", menu(), label("Toggle light"), then(PROC_REF(lamp_toggle_light_effect)))
