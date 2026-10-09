// TO ANYBODY LOOKING AT THIS FILE:
// Everything is mostly commented on to give as much detailed information as possible.
// Some things may be difficult to understand, but every variable in here has a comment explaining what it is/does.
// The base unit, the 'personal_shield_generator' is a backpack, comes with a gun, and has normal numbers for everything.
// The belt units do NOT come with a gun and have a cell that is half the capacity of backpack units.
// These can be VERY, VERY, VERY strong if too many are handed out, the cell is too strong, or the modifier is too strong.
// Additionally, if you are mapping any of these in, ensure you map in the /loaded versions or else they won't have a battery.
// I have also made it so you can modify everything about them, including the modifier they give and the cell, which can be changed via mapping.

// In essence, these can be viewed as an extra layer of armor that has upsides and downsides with more extensive features.
// Shield generators apply PRE armor. Ultimately this shouldn't matter too much, but it makes more sense this way.
// There are a good amount of variants in here, ranging from mining to security to misc ones.
// If you want to make a variant, you need to only change modifier_type and make the modifier desired.

/obj/item/personal_shield_generator
	name = "personal shield generator"
	desc = "A personal shield generator."
	icon = 'icons/obj/items.dmi'
	icon_state = "shieldpack_basic"
	item_state = "defibunit" //Placeholder
	slot_flags = SLOT_BACK
	force = 5
	throwforce = 6
	preserve_item = 1
	w_class = ITEMSIZE_HUGE //It's a giant shield generator!!!
	unacidable = TRUE
	actions_types = list(/datum/action/item_action/toggle_shield)
	var/obj/item/gun/energy/gun/generator/active_weapon
	var/obj/item/cell/device/bcell = null
	var/upgraded = FALSE 									// If the PSG has been upgraded by some method or not. Only used for the mining belt ATM.

	var/generator_hit_cost = 100							// Power used when a special effect (such as a bullet being blocked) is performed! Could also be expanded to other things.
	var/generator_active_cost = 10							// Power used when turned on.
	var/damage_cost = 25									// 40 damage absorbed per 1000 charge.
	var/modifier_type = /datum/body_effect/shield_projection	// What type of modifier will it add? Used for variant modifiers!

	var/has_weapon = 1										// Backpack units generally have weapons.
	var/effect_color = "#99FFFF"							// Allows for changing shield colors. Default cyan.

CAPABILITIES(/obj/item/personal_shield_generator)
	owns_one(nameof(active_weapon), /obj/item/gun/energy/gun/generator)
	owns_one(nameof(bcell), /obj/item/cell/device, starts = nameof(bcell))
	every(2 SECONDS, then(PROC_REF(personal_shield_generator_step)), when = nameof(shield_active))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(shield_generator_emp)))
	drag_onto(PROC_REF(drop_input))
	// the screwdriver takes the cell out; a built-in shield cell asks first, because taking it out destroys it
	op("remove_cell", tool(TOOL_SCREWDRIVER), wait(0), label("Remove cell"), when(cond_not(PROC_REF(cell_builtin))), then(PROC_REF(screwdriver_used)))
	op("destroy_cell", tool(TOOL_SCREWDRIVER), wait(0), label("Remove cell"), when(PROC_REF(cell_builtin)), needs(req(PROC_REF(cell_builtin), because = MSG(shield_generator/no_cell))),
		asks(/datum/prompt/choice, fields = list("title" = "Selection List", "question" = "A popup appears on the device 'REMOVING THE INTERNAL CELL WILL DESTROY THE BATTERY. DO YOU WISH TO CONTINUE?'...Well, do you?", "choices" = list("Cancel", "Remove"), "buttons" = TRUE, "timeout" = 0)),
		then(PROC_REF(destroy_cell_answered)))
	op("recolor", tool(TOOL_MULTITOOL), wait(0), label("Set the shield colour"),
		asks(/datum/prompt/color, fields = list("question" = "Choose a color to set the shield to!", "default" = "effect_color", "timeout" = 0)),
		then(PROC_REF(shield_color_chosen)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("toggle_shield_effect", menu(), label("Toggle Shield"), needs(carried()), then(PROC_REF(toggle_shield_effect_op)))
	op("weapon_toggle_effect", menu(), label("Toggle Gun"), needs(carried(), req(PROC_REF(pred_has_weapon_holds), because = PROC_REF(pred_has_weapon_refusal))), then(PROC_REF(weapon_toggle_effect_op)))

/obj/item/personal_shield_generator/get_cell()
	return bcell

/obj/item/personal_shield_generator/Initialize(mapload)
	. = ..()
	if(has_weapon)
		if(ispath(active_weapon))
			rel_set(src, nameof(active_weapon), new active_weapon(src, src)) // ALLOW(decl): the holder is built with constructor arguments (a size and its owner) that a bare declaration cannot pass
			rel_set(active_weapon, nameof(active_weapon.power_supply), bcell)
		else
			rel_set(src, nameof(active_weapon), new /obj/item/gun/energy/gun/generator(src, src)) // ALLOW(decl): the holder is built with constructor arguments (a size and its owner) that a bare declaration cannot pass
			rel_set(active_weapon, nameof(active_weapon.power_supply), bcell)

/// If the shield gen is active; it drains power while it is.
/obj/item/personal_shield_generator/var/shield_active = 0
TRACKED(/obj/item/personal_shield_generator, shield_active)

/obj/item/personal_shield_generator/loaded //starts with a cell
	bcell = /obj/item/cell/device/shield_generator/backpack

/// The look (the draw sweep: from its template).
/obj/item/personal_shield_generator/draw(datum/look/look)
	..()
	look.state("shieldpack_basic[shield_active ? "_on" : ""]")

/obj/item/personal_shield_generator/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(upgraded)
			. += "The unit appears to be upgraded."
		if(bcell)
			. += "The internal cell is [round(bcell.percent() )]% charged."
		else
			. += "The device has no cell installed."
			return
		if(damage_cost) //Prevention of dividing by 0 errors.
			. += "It reads that it can take [bcell.charge/damage_cost] more damage before the shield goes down."
		if(bcell.self_recharge && bcell.charge_amount)
			. += "This model is self charging and will take [bcell.maxcharge/bcell.charge_amount] seconds to fully charge from empty."
		if(bcell.rigged)
			. += "A red flashing 'WARNING' is visible on the display, noting that the cell is unstable and requires replacement."

/// An EMP on a running shield may burn or corrupt its cell (on_notice in its CAPABILITIES).
/obj/item/personal_shield_generator/proc/shield_generator_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = N.packet.severity
	if(bcell && shield_active)
		switch(severity)
			if(1) //Point blank EMP shots have a good chance of burning the cell charge.
				if(prob(50))
					bcell.emp_act(severity)
					if(prob(5)) //1 in 20% chance to fry the battery completly, which has a 1/10 chance of making the battery explode on next use.
						bcell.corrupt() //Not too bad if you slotted a battery in. Disasterous if it has a self-charging battery.
					if(bcell.rigged) //Did the above just rig the cell? Turn it off. Don't immediately have it go boom. Instead have the cell blow soon-ish.
						fx_sparks(src, 5)
						set_shield_active(0)
						if(bcell.charge_delay) //It WILL blow up soon. Downside of self-charging cells.
							to_chat(src.loc, span_critical("Your shield generator sparks and suddenly goes down! A warning message pops up on screen: \
							'WARNING, INTERNAL CELL MELTDOWN IMMINENT. TIME TILL EXPLOSION: [bcell.charge_delay/10] SECONDS. DISCARD UNIT IMMEDIATELY!'"))
						else //It won't blow up unless you turn it back on again. Upside of using non-charging cells.
							to_chat(src.loc, span_critical("Your shield generator sparks and suddenly goes down! A warning message pops up on screen: \
							'WARNING, INTERNAL CELL CRITICALLY DAMAGED. REPLACE CELL IMMEDIATELY.'"))
			else
				if(prob(25))
					bcell.emp_act(severity)

/obj/item/personal_shield_generator/ui_action_click(mob/user, actiontype)
	toggle_shield_effect(user)

/// The toggle_shield_effect op: the verb's effect, as the old resolver ran it.
/obj/item/personal_shield_generator/proc/toggle_shield_effect_op(datum/act/op/A)
	toggle_shield_effect(A.actor, A.held)
	return OP_OK

/// Requirement (was REQ_* pred_has_weapon): the legacy check answers TRUE to pass.
/obj/item/personal_shield_generator/proc/pred_has_weapon_holds(datum/act/op/A)
	var/answer = pred_has_weapon(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why pred_has_weapon_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/personal_shield_generator/proc/pred_has_weapon_refusal(datum/act/op/A)
	var/answer = pred_has_weapon(A.actor, src, A.held)
	return istext(answer) ? answer : "it has no gun"

/// The weapon_toggle_effect op: the verb's effect, as the old resolver ran it.
/obj/item/personal_shield_generator/proc/weapon_toggle_effect_op(datum/act/op/A)
	weapon_toggle_effect(A.actor, A.held)
	return OP_OK

/obj/item/personal_shield_generator/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(loc == user)
		toggle_shield_effect(user)
		return TRUE
	return OP_DECLINE

/obj/item/personal_shield_generator/proc/interaction_alt(datum/act/op/A)
	var/mob/living/user = A.actor
	weapon_toggle_effect(user)
	return TRUE

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). The worn pack is dragged into its wearer's hands.
/obj/item/personal_shield_generator/proc/drop_input(datum/act/input/A)
	drag_backpack_with_actor(A.actor)
	return TRUE

/obj/item/personal_shield_generator/proc/drag_backpack_with_actor(mob/user)
	if(ismob(src.loc))
		if(!CanMouseDrop(src, user))
			return
		var/mob/M = src.loc
		if(!M.unEquip(src))
			return
		src.add_fingerprint(user)
		M.put_in_any_hand_if_possible(src)

/obj/item/personal_shield_generator/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W == active_weapon)
		reattach_gun(user)
	else if(istype(W, /obj/item/cell))
		if(bcell)
			to_chat(user, span_notice("\The [src] already has a cell."))
		else if(!istype(W, /obj/item/cell/device/weapon)) //Weapon cells only!
			to_chat(user, span_notice("This cell will not fit in the device."))
		else
			if(!move_into(src, nameof(src.bcell), W, user))
				return TRUE
			if(active_weapon)
				rel_set(active_weapon, nameof(active_weapon.power_supply), bcell)
			to_chat(user, span_notice("You install a cell in \the [src]."))

	else
		return OP_DECLINE
	return TRUE

/// A built-in shield cell (not the parry one): taking it out destroys it.
/obj/item/personal_shield_generator/proc/cell_builtin(datum/act/A)
	return istype(bcell, /obj/item/cell/device/shield_generator) && !istype(bcell, /obj/item/cell/device/shield_generator/parry)

/// The screwdriver takes an ordinary cell out; the parry cell stays.
/obj/item/personal_shield_generator/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!bcell)
		return OP_OK
	if(istype(bcell, /obj/item/cell/device/shield_generator/parry))
		to_chat(user, span_notice("You cannot remove the cell from this device."))
		return OP_OK
	bcell.forceMove(get_turf(src))
	rel_take(src, nameof(bcell))
	if(active_weapon)
		reattach_gun()
		rel_clear(active_weapon, nameof(active_weapon.power_supply))
	to_chat(user, span_notice("You remove the cell from \the [src]."))
	return OP_OK

MSG_DEF_SELF(shield_generator/no_cell, "There is no removable cell.")

/// "Remove": the built-in cell comes out and is destroyed (re-checked on the answer: still a built-in one, still beside it).
/obj/item/personal_shield_generator/proc/destroy_cell_answered(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(R?.value != "Remove")
		return OP_OK
	var/mob/user = A.actor
	fx_sparks(src, 5)
	rel_clear(src, nameof(bcell))
	if(active_weapon)
		reattach_gun()
		rel_clear(active_weapon, nameof(active_weapon.power_supply))
	to_chat(user, span_notice("You remove the cell from \the [src], destroying the battery."))
	return OP_OK

/// The multitool sets the shield's colour.
/obj/item/personal_shield_generator/proc/shield_color_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(R?.value)
		effect_color = R.value
	return OP_OK

// TODO: EMAG ACT
// Perhaps make it so emagging the generator gives two options: One to rig the cell (stealthily) and one to disable the safeties (supercharge it)
// Disabling the safeties would make it a stronger variant but boost the 'damage_cost' perhaps. Dunno.
// We're an RP server so emags don't come into play except for random trash finds. Meaning it'd be RNG if you could 'supercharge' your shield genrator.
// This would kind of be like people being able to emag the NIFSoft for bloodletters & all the buffs that come with an emagged NIFSoft.
// Making it so emagging the weapon it comes with would also be a good idea. Different modes, perhaps?

//Gun stuff

/obj/item/personal_shield_generator/proc/toggle_shield_effect(mob/living/carbon/human/user, obj/item/held)

	if(!COOLDOWN_FINISHED(user, last_special))
		return
	COOLDOWN_START(user, last_special, 1 SECONDS) //No spamming!

	if(!bcell || !bcell.check_charge(generator_hit_cost) || !bcell.check_charge(generator_active_cost))
		to_chat(user, span_warning("You require a charged cell to do this!"))
		return

	if(!slot_check())
		to_chat(user, span_warning("You need to equip [src] before starting the shield up!"))
		return
	else
		if(shield_active)
			set_shield_active(!shield_active) //Deactivate the shield!
			to_chat(user, span_warning("You deactive the shield!"))
			user.remove_body_effect(/datum/body_effect/shield_projection)
			play_sfx(src, SFX_WEAPONS_SABEROFF) //Shield turning off! PLACEHOLDER
		else
			set_shield_active(!shield_active)
			to_chat(user, span_warning("You activate the shield!"))
			user.remove_body_effect(/datum/body_effect/shield_projection) //Just to make sure they aren't using two at once!
			user.apply_body_effect(modifier_type)
			user.update_modifier_visuals() //Forces coloration to WORK.
			play_sfx(src, SFX_WEAPONS_SABERON) //Shield turning off! PLACEHOLDER

/obj/item/personal_shield_generator/proc/weapon_toggle_effect(mob/living/carbon/human/user, obj/item/held) //Make this work on Alt-Click

	if(!COOLDOWN_FINISHED(user, last_special))
		return
	COOLDOWN_START(user, last_special, 1 SECONDS) //No spamming!

	if(!active_weapon)
		to_chat(user, span_warning("The gun is missing!"))
		return

	if(!bcell)
		to_chat(user, span_warning("The gun requires a power supply!"))
		return

	if(active_weapon.loc != src)
		reattach_gun(user) //Remove from their hands and back onto the defib unit
		return

	if(!slot_check())
		to_chat(user, span_warning("You need to equip [src] before taking out [active_weapon]."))
	else
		if(!user.put_in_hands(active_weapon)) //Detach the gun into the user's hands
			to_chat(user, span_warning("You need a free hand to hold the gun!"))

/obj/item/personal_shield_generator/proc/personal_shield_generator_step(datum/act/timer/A)
	if(!bcell) //They removed the battery midway.
		if(ishuman(loc)) //We on someone? Tell them it turned off.
			var/mob/living/carbon/human/user = loc
			to_chat(user, span_warning("The shield deactivates! An error message pops up on screen: 'Cell missing. Cell replacement required.'"))
			user.remove_body_effect(/datum/body_effect/shield_projection)
		set_shield_active(0)
		play_sfx(src, SFX_WEAPONS_SABEROFF) //Shield turning off! PLACEHOLDER
		return

	if(shield_active)
		if(bcell.rigged) //They turned it back on after it was rigged to go boom.
			if(ishuman(loc)) //Deactivate the shield, first. You're not getting reduced damage...
				var/mob/living/carbon/human/user = loc
				to_chat(user, span_warning("The shield deactivates, an error message popping up on screen: 'Cell Reactor Critically damaged. Cell replacement required.'"))
				user.remove_body_effect(/datum/body_effect/shield_projection)

			if(active_weapon) //Retract the gun. There's about to be no cell anymore.
				reattach_gun()
				rel_clear(active_weapon, nameof(active_weapon.power_supply))

			bcell.use(generator_active_cost) //Causes it to go boom.
			rel_take(src, nameof(bcell))
			set_shield_active(0)
			return

		else //Normal operation.
			bcell.use(generator_active_cost)

	if(bcell.charge < generator_hit_cost || bcell.charge < generator_active_cost) //Out of charge...
		set_shield_active(0)
		if(ishuman(loc)) //We on someone? Tell them it turned off.
			var/mob/living/carbon/human/user = loc
			to_chat(user, span_warning("The shield deactivates, an error message popping up on screen: 'Cell out of charge.'"))
			user.remove_body_effect(/datum/body_effect/shield_projection)
		play_sfx(src, SFX_WEAPONS_SABEROFF) //Shield turning off! PLACEHOLDER
		return

//checks that the base unit is in the correct slot to be used
/obj/item/personal_shield_generator/proc/slot_check()
	var/mob/M = loc
	if(!istype(M))
		return 0 //not equipped

	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_BACK) == src)
		return 1
	if(HAS_TAG(src, TAG_WEAR_BELT) && M.get_equipped_item(SLOT_ID_BELT) == src)
		return 1
	//RIGSuit compatability. This shouldn't be possible, however, except for select RIGs.
	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src)
		return 1
	if(HAS_TAG(src, TAG_WEAR_BELT) && M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src)
		return 1

	return 0

/obj/item/personal_shield_generator/dropped(mob/user, equipping, slot)
	..()
	reattach_gun(user) //A gun attached to a base unit should never exist outside of their base unit or the mob equipping the base unit

/obj/item/personal_shield_generator/proc/reattach_gun(mob/user)
	if(!active_weapon) return

	if(ismob(active_weapon.loc))
		var/mob/M = active_weapon.loc
		if(M.drop_from_inventory(active_weapon, src))
			to_chat(user, span_notice("\The [active_weapon] snaps back into the main unit."))
	else
		active_weapon.forceMove(src)


//The gun

/obj/item/gun/energy/gun/generator //The gun attached to the personal shield generator.
	name = "generator gun"
	desc = "A gun that is attached to the battery of the personal shield generator."
	icon_state = "egunstun"
	item_state = null //so the human update icon uses the icon_state instead.
	fire_delay = 8
	use_external_power = TRUE
	cell_type = null //No cell! It runs off the cell in the shield_gen!

	projectile_type = /obj/item/projectile/beam/stun/med
	modifystate = "egunstun"

	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun/med, modifystate="egunstun", fire_sound=SFX_WEAPONS_TASER, charge_cost = 240),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam, modifystate="egunkill", fire_sound=SFX_WEAPONS_LASER, charge_cost = 480),
		)

	/// Relation view: the generator we are linked to!
	var/obj/item/personal_shield_generator/linked_generator
	var/wielded = 0
	var/cooldown = 0

// ALLOW(init/INSTANCE_STATE): the generator's gun draws from its generator's cell, in place of the one its parents made
/obj/item/gun/energy/gun/generator/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(power_supply), shield_generator()?.bcell)

/obj/item/gun/energy/gun/generator/proc/can_use(mob/user, mob/M)
	if(!check_charge(charge_cost))
		to_chat(user, span_warning("\The [src] doesn't have enough charge left to do that."))
		return 0
	if(!wielded && !isrobot(user))
		to_chat(user, span_warning("You need to wield the gun with both hands before you can use it on someone!"))
		return 0
	if(cooldown)
		to_chat(user, span_warning("\The [src] are re-energizing!"))
		return 0
	return 1

/obj/item/gun/energy/gun/generator/dropped(mob/user, equipping, slot)
	..() //update twohanding
	if(shield_generator())
		shield_generator().reattach_gun(user)

/obj/item/gun/energy/proc/check_charge(charge_amt) //In case using any other guns.
	return 0

/obj/item/gun/energy/proc/checked_use(charge_amt) //In case using any other guns.
	return 0

/obj/item/gun/energy/gun/generator/check_charge(charge_amt)
	return (shield_generator().bcell && shield_generator().bcell.check_charge(charge_amt))

/obj/item/gun/energy/gun/generator/checked_use(charge_amt)
	return (shield_generator().bcell && shield_generator().bcell.checked_use(charge_amt))

//VARIANTS.

/obj/item/personal_shield_generator/belt
	name = "personal shield generator"
	desc = "A personal shield generator."
	icon_state = "shieldpack_basic"
	item_state = "defibunit"
	w_class = ITEMSIZE_LARGE //No putting these in backpacks!
	slot_flags = SLOT_BELT
	has_weapon = 0 //No gun with the belt!

/obj/item/personal_shield_generator/belt/loaded
	bcell = /obj/item/cell/device/shield_generator

/// The look (the draw sweep: from its template).
/obj/item/personal_shield_generator/belt/draw(datum/look/look)
	..()
	look.state("shieldpack_basic[shield_active ? "_on" : ""]")

/obj/item/personal_shield_generator/belt/bruteburn //Example of a modified generator.
	modifier_type = /datum/body_effect/shield_projection/bruteburn
/obj/item/personal_shield_generator/belt/bruteburn/loaded //If mapped in, ONLY put loaded ones down.
	bcell = /obj/item/cell/device/shield_generator

// Mining belts
/obj/item/personal_shield_generator/belt/mining
	name = "PSG Variant-M"
	desc = "A personal shield generator designed for mining and combat with hostile creatures. \
	It has a warning on the back: 'Do NOT expose the shield to stun-based weaponry.'"
	modifier_type = /datum/body_effect/shield_projection/mining

/obj/item/personal_shield_generator/belt/mining/loaded
	bcell = /obj/item/cell/device/shield_generator

/obj/item/personal_shield_generator/belt/mining/upgraded
	upgraded = TRUE
	modifier_type = /datum/body_effect/shield_projection/mining/strong

/obj/item/personal_shield_generator/belt/mining/upgraded/loaded
	bcell = /obj/item/cell/device/shield_generator

/// The look (the draw sweep: from its template).
/obj/item/personal_shield_generator/belt/mining/draw(datum/look/look)
	..()
	look.state("shieldpack_mining[shield_active ? "_on" : ""]")

/obj/item/borg/upgrade/shield_upgrade
	name = "mining PSG upgrade disk."
	desc = "A upgrade disk that, when slotted into a mining shield generator, upgrades the efficiency of the internal software, providing a stronger shield \
	in exchange for being weaker to stun-based weaponry."
	icon = 'icons/obj/objects_vr.dmi'
	icon_state = "modkit"
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/personal_shield_generator/belt/mining)
	op("upgrade", item(/obj/item/borg/upgrade/shield_upgrade), label("Upgrade"), then(PROC_REF(interaction_upgrade)))

/obj/item/personal_shield_generator/belt/mining/proc/interaction_upgrade(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/borg/upgrade/shield_upgrade/W = A.held
	if(modifier_type == /datum/body_effect/shield_projection/mining/strong)
		to_chat(user, span_warning("This shield generator is already upgraded!"))
		return TRUE
	var/upgrade_name = "[W]"
	if(!consume(W, user))
		return TRUE
	modifier_type = /datum/body_effect/shield_projection/mining/strong
	upgraded = TRUE
	to_chat(user, span_notice("You upgrade the [src] with the [upgrade_name]!"))
	return TRUE

//Security belts

/obj/item/personal_shield_generator/belt/security
	name = "PSG Variant-S"
	desc = "A personal shield generator designed for security."
	modifier_type = /datum/body_effect/shield_projection/security/weak

/obj/item/personal_shield_generator/belt/security/loaded
	bcell = /obj/item/cell/device/shield_generator

/// The look (the draw sweep: from its template).
/obj/item/personal_shield_generator/belt/security/draw(datum/look/look)
	..()
	look.state("shieldpack_security[shield_active ? "_on" : ""]")

//PvE focused belt
/obj/item/personal_shield_generator/belt/melee
	name = "PSG Variant-B"
	desc = "A personal shield generator that creates a field that prevents the functionality of firearms in exchange \
	for enhanceing melee potential. The shield makes its user more resistant to brute and burn, \
	makes them harder to hit, able to hit harder, able to hit faster, allows faster movement, and \
	allows the user to get up from disabling strikes faster."
	damage_cost = 5

	modifier_type = /datum/body_effect/shield_projection/melee_focus

/obj/item/personal_shield_generator/belt/melee/loaded
	bcell = /obj/item/cell/device/shield_generator

//Misc belts.

/obj/item/personal_shield_generator/belt/medical
	name = "PSG Variant-BIO"
	desc = "A personal shield generator that creates a field that helps against biohazards \
	for enhanceing melee potential. The shield makes its user resistant to toxic attacks, suffocating attacks, and DNA attacks"

	modifier_type = /datum/body_effect/shield_projection/biohazard

/obj/item/personal_shield_generator/belt/medical/loaded
	bcell = /obj/item/cell/device/shield_generator

/obj/item/personal_shield_generator/belt/parry 	//The 'provides one second of pure immunity to brute/burn/halloss' belt.
	name = "PSG Variant-P" 		//Not meant to be used in any serious capacity.
	desc = "A personal shield generator that sacrifices long-term usability in exchange for a strong, short-lived shield projection, enabling the user to be nigh \
	impervious for a second."
	modifier_type = /datum/body_effect/shield_projection/parry
	generator_hit_cost = 0 //No cost for being hit.
	damage_cost = 0//No cost for blocking effects.
	generator_active_cost = 100 //However, it disables the tick immediately after being turned on.
	shield_active = 0
	bcell = /obj/item/cell/device/shield_generator/parry

//Badmin belt
/obj/item/personal_shield_generator/belt/adminbus
	desc = DEVELOPER_WARNING_NAME + " You REALLY should not see this. If you do, you have either been blessed or are about to be the target of some sick prank."
	modifier_type = /datum/body_effect/shield_projection/admin
	generator_hit_cost = 0
	generator_active_cost = 0
	shield_active = 0
	damage_cost = 0
	bcell = /obj/item/cell/device/shield_generator

// Backpacks. These are meant to be MUCH stronger in exchange for the fact that you are giving up a backpack slot.
// HOWEVER, be careful with these. They come loaded with a gun in them, so they shouldn't be handed out willy-nilly.

/obj/item/personal_shield_generator/security
	name = "Backpack PSG Variant-S"
	desc = "A personal shield generator designed for security. Comes with a built in defense pistol."
	modifier_type = /datum/body_effect/shield_projection/security

/obj/item/personal_shield_generator/security/loaded
	bcell = /obj/item/cell/device/shield_generator/backpack

/obj/item/personal_shield_generator/security/strong
	modifier_type = /datum/body_effect/shield_projection/security/strong

/obj/item/personal_shield_generator/security/strong/loaded
	bcell = /obj/item/cell/device/shield_generator/backpack

/// The look (the draw sweep: from its template).
/obj/item/personal_shield_generator/security/draw(datum/look/look)
	..()
	look.state("shieldpack_security[shield_active ? "_on" : ""]")

//Power cells.
/obj/item/cell/device/shield_generator //The base power cell the shield gen comes with.
	name = "shield generator battery"
	desc = "A self charging battery which houses a micro-nuclear reactor. Takes a while to start charging."
	maxcharge = 2400
	self_recharge = TRUE
	charge_amount = 80 //After the charge_delay is over, charges the cell over 30 seconds.
	charge_delay = 600 //Takes a minute before it starts to recharge.

/obj/item/cell/device/shield_generator/backpack //The base power cell the backpack units come with. Double the charge vs the belt.
	maxcharge = 4800
	charge_amount = 160

/obj/item/cell/device/shield_generator/upgraded //A stronger version of the normal cell. Double the maxcharge, halved charge time.
	maxcharge = 4800
	charge_amount = 320
	charge_delay = 300

/obj/item/cell/device/shield_generator/parry //The cell for the 'parry' shield gen.
	maxcharge = 200 // 100 to 200.
	charge_amount = 200 // 100 to 200.
	charge_delay = 30 // Starts charging three seconds after it's discharged.

/// The relation view `linked_generator` (null once it is gone).
/obj/item/gun/energy/gun/generator/proc/shield_generator() as /obj/item/personal_shield_generator
	return linked_generator

// The generator gun runs off the generator's cell: a view, not an owned cell.
CAPABILITIES(/obj/item/gun/energy/gun/generator)
	ref_one(nameof(power_supply))
	param(nameof(linked_generator), pos = 1)

/// Old object verbs.

/// Requirement for "Toggle Gun" (old: the verb was removed from generators without a weapon).
/obj/item/personal_shield_generator/proc/pred_has_weapon(mob/actor, atom/target, obj/item/held)
	return has_weapon
