#define WELDER_FUEL_BURN_INTERVAL 13
/*
 * Welding Tool
 */
MATERIAL_MIX(/obj/item/weldingtool, list(MAT_STEEL = 70, MAT_GLASS = 30))
/obj/item/weldingtool
	name = "\improper welding tool"
	icon = 'icons/obj/tools.dmi'
	icon_state = "welder"
	item_state = "welder"
	slot_flags = SLOT_BELT

	//Amount of OUCH when it's thrown
	force = 3.0
	throwforce = 5.0
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL

	//Cost to make in the autolathe

	//R&D tech level

	tool_qualities = list(TOOL_WELDER)

	//Welding tool specific stuff
	var/status = 1 		//Whether the welder is secured or unsecured (able to attach rods to it to make a flamethrower)
	var/max_fuel = 20 	//The max amount of fuel the welder can hold

	var/acti_sound = SFX_ITEMS_WELDERACTIVATE
	var/deac_sound = SFX_ITEMS_WELDERDEACTIVATE
	usesound = SFX_ITEMS_WELDER2
	var/change_icons = TRUE
	var/flame_intensity = 2 //how powerful the emitted light is when used.
	var/flame_color = "#FF9933" // What color the welder light emits when its on.  Default is an orange-ish color.
	var/eye_safety_modifier = 0 // Increasing this will make less eye protection needed to stop eye damage.  IE at 1, sunglasses will fully protect.
	var/burned_fuel_for = 0 // Keeps track of how long the welder's been on, used to gradually empty the welder if left one, without RNG.
	var/no_passive_burn = FALSE // If true, the welder will not passively burn fuel. Used for things like electric welders.
	toolspeed = 1
	drop_sound = SFX_ITEMS_DROP_WELDINGTOOL
	pickup_sound = SFX_ITEMS_PICKUP_WELDINGTOOL
	tool_qualities = list(TOOL_WELDER)

//Whether or not the welding tool is off(0), on(1) or currently welding(2)
OM_FIELD(/obj/item/weldingtool, welding, 0, CHANGE_EXPLICIT)
/// If true, keeps the welder processing even while off (fuel regeneration).
OM_FIELD(/obj/item/weldingtool, always_process, FALSE, CHANGE_EXPLICIT)
OM_DERIVE_FIELD(/obj/item/weldingtool, burner_active, list("welding", "always_process"))
/// Burns fuel (or regenerates it, for always_process welders) every 2 s while lit.
DECLARE_PERIODIC_WHILE(/obj/item/weldingtool, PERIODIC_SLOW, "burner_active")

/// Whether the periodic burn/regeneration runs: lit, or a welder that always processes.
/obj/item/weldingtool/proc/burner_active()
	return welding || always_process

/obj/item/weldingtool/Initialize(mapload)
	. = ..()
	var/datum/reagents/R = new/datum/reagents(max_fuel)
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)
	R.add_reagent(REAGENT_ID_FUEL, max_fuel)
	update_icon()

/obj/item/weldingtool/get_welder()
	return src

/obj/item/weldingtool/examine(mob/user)
	. = ..()
	if(max_fuel && loc == user)
		. += "It contains [get_fuel()]/[src.max_fuel] units of fuel!"

/obj/item/weldingtool/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(ishuman(M) && stance == I_HELP)
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/S = H.organs_by_name[user.zone_sel.selecting]

		if(!S || !S.is_robotic() || S.open == 3)
			return ..()

		// No welding nanoform limbs
		if(S.robotic > ORGAN_LIFELIKE)
			return ..()

		if(S.organ_tag == BP_HEAD)
			if(H.get_equipped_item(SLOT_ID_HEAD) && istype(H.get_equipped_item(SLOT_ID_HEAD),/obj/item/clothing/head/helmet/space))
				to_chat(user, span_warning("You can't apply [src] through [H.get_equipped_item(SLOT_ID_HEAD)]!"))
				return ITEM_INTERACT_FAILURE
		else
			if(H.get_equipped_item(SLOT_ID_SUIT) && istype(H.get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
				to_chat(user, span_warning("You can't apply [src] through [H.get_equipped_item(SLOT_ID_SUIT)]!"))
				return ITEM_INTERACT_FAILURE

		if(!welding)
			to_chat(user, span_warning("You'll need to turn [src] on to patch the damage on [H]'s [S.name]!"))
			return ITEM_INTERACT_FAILURE

		if(S.robo_repair(15, BRUTE, "some dents", src, user, PROC_REF(robo_repair_used)))
			return ITEM_INTERACT_SUCCESS
		else
			return ITEM_INTERACT_FAILURE //Stops you from accidentally harming someone while on help intent.

	return ..()

/// A robotic limb repair with this welder finished.
/obj/item/weldingtool/proc/robo_repair_used(mob/living/user)
	remove_fuel(1, user)

/// Old attackby.
/obj/item/weldingtool/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(W.has_tool_quality(TOOL_SCREWDRIVER))
		if(welding)
			to_chat(user, span_danger("Stop welding first!"))
			return OP_PASS
		status = !status
		if(status)
			to_chat(user, span_notice("You secure the welder."))
		else
			to_chat(user, span_notice("The welder can now be attached and modified."))
		add_fingerprint(user)
		return OP_PASS

	if((!status) && (istype(W,/obj/item/stack/rods)))
		var/obj/item/stack/rods/R = W
		R.use(1)
		var/obj/item/flamethrower/F = new/obj/item/flamethrower(get_turf(user))
		if(!move_into(F, nameof(F.weldtool), src, user))
			return OP_PASS
		add_fingerprint(user)
		return OP_PASS

	return OP_DECLINE

/obj/item/weldingtool/periodic_step()
	if(welding)
		if(!no_passive_burn)
			++burned_fuel_for
			if(burned_fuel_for >= WELDER_FUEL_BURN_INTERVAL)
				remove_fuel(1)
		if(get_fuel() < 1)
			setWelding(0)
		else			//Only start fires when its on and has enough fuel to actually keep working
			var/turf/location = src.loc
			if(isliving(location))
				var/mob/living/M = location
				if(M.item_is_in_hands(src))
					location = get_turf(M)
			if (istype(location, /turf))
				location.hotspot_expose(700, 5)

/obj/item/weldingtool/afterattack(obj/O as obj, mob/user as mob, proximity)
	if(!proximity) return
	if (istype(O, /obj/structure/reagent_dispensers/fueltank) && get_dist(src,O) <= 1)
		if(!welding && max_fuel)
			O.reagents.trans_to_obj(src, max_fuel)
			to_chat(user, span_notice("Welder refueled"))
			play_sfx(src, SFX_EFFECTS_REFILL)
			return
		else if(!welding)
			to_chat(user, span_notice("[src] doesn't use fuel."))
			return
		else
			message_admins("[key_name_admin(user)] triggered a fueltank explosion with a welding tool.")
			log_game("[key_name(user)] triggered a fueltank explosion with a welding tool.")
			to_chat(user, span_danger("You begin welding on the fueltank and with a moment of lucidity you realize... you are doomed."))
			var/obj/structure/reagent_dispensers/fueltank/tank = O // CHOMPS edit - Readds welderbombing
			tank.explode()
			return
	if (src.welding)
		remove_fuel(1)
		var/turf/location = get_turf(user)
		if(isliving(O))
			var/mob/living/L = O
			L.ignite_mob()
		if (istype(location, /turf))
			location.hotspot_expose(700, 50, 1)
CAPABILITIES(/obj/item/weldingtool)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	drag_onto(PROC_REF(mousedrop_input))

/// Old attack_self.
/obj/item/weldingtool/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	setWelding(!welding, user)
	return TRUE

//Returns the amount of fuel in the welder
/obj/item/weldingtool/proc/get_fuel()
	return reagents.get_reagent_amount(REAGENT_ID_FUEL)

/obj/item/weldingtool/proc/get_max_fuel()
	return max_fuel

//Removes fuel from the welding tool. If a mob is passed, it will perform an eyecheck on the mob. This should probably be renamed to use()
/obj/item/weldingtool/proc/remove_fuel(amount = 1, mob/M = null)
	if(!welding)
		return 0
	if(amount)
		burned_fuel_for = 0 // Reset the counter since we're removing fuel.
	if(get_fuel() >= amount)
		reagents.remove_reagent(REAGENT_ID_FUEL, amount)
		if(M)
			eyecheck(M)
		update_icon()
		return 1
	else
		if(M)
			to_chat(M, span_notice("You need more welding fuel to complete this task."))
		update_icon()
		return 0

//Returns whether or not the welding tool is currently on.
/obj/item/weldingtool/proc/isOn()
	return welding

DECLARE_APPEARANCE_PROC(/obj/item/weldingtool, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/weldingtool/appearance_overlays()
	. = list()
	. += ..()
	// Welding overlay.
	if(welding)
		. += "[icon_state]-on"
		item_state = "[initial(item_state)]1"
	else
		item_state = initial(item_state)

	// Fuel counter overlay.
	if(change_icons && get_max_fuel())
		var/ratio = get_fuel() / get_max_fuel()
		ratio = CEILING(ratio * 4, 1) * 25
		. += "[icon_state][ratio]"

	// Lights
	if(welding && flame_intensity)
		set_light(flame_intensity, flame_intensity, flame_color)
	else
		set_light(0)


//	icon_state = welding ? "[icon_state]1" : "[initial(icon_state)]"
	var/mob/M = loc
	if(istype(M))
		M.update_inv_l_hand()
		M.update_inv_r_hand()

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/weldingtool/proc/mousedrop_input(datum/act/input/A)
	if(!handle_inventory_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/weldingtool/proc/handle_inventory_drop(mob/user, obj/over_object)
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

//Sets the welding state of the welding tool. If you see W.welding = 1 anywhere, please change it to W.setWelding(1)
//so that the welding tool updates accordingly
/obj/item/weldingtool/proc/setWelding(set_welding, mob/M)
	if(!status)	return

	var/turf/T = get_turf(src)
	//If we're turning it on
	if(set_welding && !welding)
		if (get_fuel() > 0)
			if(M)
				to_chat(M, span_notice("You switch the [src] on."))
			else if(T)
				T.visible_message(span_danger("\The [src] turns on."))
			playsound(src, acti_sound, 50, 1)
			src.force = 15
			src.injury_kind = INJURY_BURN
			src.w_class = ITEMSIZE_LARGE
			src.hitsound = 'sound/items/Welder.ogg'
			set_welding(1)
			update_icon()
		else
			if(M)
				var/msg = max_fuel ? "welding fuel" : "charge"
				to_chat(M, span_notice("You need more [msg] to complete this task."))
			return
	//Otherwise
	else if(!set_welding && welding)
		if(M)
			to_chat(M, span_notice("You switch \the [src] off."))
		else if(T)
			T.visible_message(span_warning("\The [src] turns off."))
		playsound(src, deac_sound, 50, 1)
		src.force = 3
		src.injury_kind = initial(src.injury_kind)
		src.w_class = initial(src.w_class)
		set_welding(0)
		src.hitsound = initial(src.hitsound)
		update_icon()

//Decides whether or not to damage a player's eyes based on what they're wearing as protection
//Note: This should probably be moved to mob
/obj/item/weldingtool/proc/eyecheck(mob/living/carbon/user)
	if(!istype(user))
		return 1
	var/safety = user.eyecheck()
	safety = between(-1, safety + eye_safety_modifier, 2)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if(!E)
			return
		if(HAS_SYNTHETIC_BIOLOGY(user)) //Fixes robots going blind when doing the equivalent of a bruise pack.
			return
		if(H.nif && H.nif.flag_check(NIF_V_UVFILTER,NIF_FLAGS_VISION)) return // NIF
		switch(safety)
			if(1)
				to_chat(user, span_warning("Your eyes sting a little."))
				H.injure(INJURY_BURN, rand(1, 2), E, src, flags = INJURE_SILENT)
				if(E.damage > 12)
					user.status_adjust(STAT_BLURRY, rand(3,6))
			if(0)
				to_chat(user, span_warning("Your eyes burn."))
				H.injure(INJURY_BURN, rand(2, 4), E, src, flags = INJURE_SILENT)
				if(E.damage > 10)
					H.injure(INJURY_BURN, rand(4, 10), E, src, flags = INJURE_SILENT)
			if(-1)
				to_chat(user, span_danger("Your thermals intensify the welder's glow. Your eyes itch and burn severely."))
				user.status_adjust(STAT_BLURRY, rand(12,20))
				H.injure(INJURY_BURN, rand(12, 16), E, src, flags = INJURE_SILENT)
		if(safety<2)

			if(E.damage > 10)
				to_chat(user, span_warning("Your eyes are really starting to hurt. This can't be good for you!"))

			if (E.damage >= E.min_broken_damage)
				to_chat(user, span_danger("You go blind!"))
				user.set_sdisabilities(user.sdisabilities | (BLIND))
			else if (E.damage >= E.min_bruised_damage)
				to_chat(user, span_danger("You go blind!"))
				user.status_at_least(STAT_BLINDED, 5)
				user.status_set(STAT_BLURRY, 5)
				user.status_at_least(STAT_NEARSIGHTED, 2)
	return

/obj/item/weldingtool/is_hot()
	return isOn()

MATERIAL_MIX(/obj/item/weldingtool/largetank, list(MAT_STEEL = 70, MAT_GLASS = 60))
/obj/item/weldingtool/largetank
	name = "industrial welding tool"
	desc = "A slightly larger welder with a larger tank."
	icon_state = "indwelder"
	max_fuel = 40

MATERIAL_MIX(/obj/item/weldingtool/hugetank, list(MAT_STEEL = 70, MAT_GLASS = 120))
/obj/item/weldingtool/hugetank
	name = "upgraded welding tool"
	desc = "A much larger welder with a huge tank."
	icon_state = "upindwelder"
	max_fuel = 80
	w_class = ITEMSIZE_NORMAL

MATERIAL_MIX(/obj/item/weldingtool/mini, list(MAT_METAL = 30, MAT_GLASS = 10))
/obj/item/weldingtool/mini
	name = "emergency welding tool"
	desc = "A miniature welder used during emergencies."
	icon_state = "miniwelder"
	max_fuel = 10
	w_class = ITEMSIZE_SMALL
	change_icons = 0
	toolspeed = 2
	eye_safety_modifier = 1 // Safer on eyes.

/obj/item/weldingtool/mini/two
	icon_state = "miniwelder2"

/datum/category_item/catalogue/anomalous/precursor_a/alien_welder
	name = "Precursor Alpha Object - Self Refueling Exothermic Tool"
	desc = "An unwieldly tool which somewhat resembles a weapon, due to \
	having a prominent trigger attached to the part which would presumably \
	have been held by whatever had created this object. When the trigger is \
	held down, a small but very high temperature flame shoots out from the \
	tip of the tool. The grip is able to be held by human hands, however the \
	shape makes it somewhat awkward to hold.\
	<br><br>\
	The tool appears to utilize an unknown fuel to light and maintain the \
	flame. What is more unusual, is that the fuel appears to replenish itself. \
	How it does this is not known presently, however experimental human-made \
	welders have been known to have a similar quality.\
	<br><br>\
	Interestingly, the flame is able to cut through a wide array of materials, \
	such as iron, steel, stone, lead, plasteel, and even durasteel. Yet, it is unable \
	to cut the unknown material that itself and many other objects made by this \
	precursor civilization have made. This raises questions on the properties of \
	that material, and how difficult it would have been to work with. This tool \
	does demonstrate, however, that the alien fuel cannot melt precursor beams, walls, \
	or other structual elements, making it rather limited for their \
	deconstruction purposes."
	value = CATALOGUER_REWARD_EASY

/obj/item/weldingtool/alien
	name = "alien welding tool"
	desc = "An alien welding tool. Whatever fuel it uses, it never runs out."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_welder)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "welder"
	toolspeed = 0.1
	flame_color = "#6699FF" // Light bluish.
	eye_safety_modifier = 2
	change_icons = 0
	always_process = TRUE

/obj/item/weldingtool/alien/periodic_step()
	if(get_fuel() <= get_max_fuel())
		reagents.add_reagent(REAGENT_ID_FUEL, 1)
	..()

MATERIAL_MIX(/obj/item/weldingtool/experimental, list(MAT_STEEL = 70, MAT_GLASS = 120))
/obj/item/weldingtool/experimental
	name = "experimental welding tool"
	desc = "An experimental welder capable of synthesizing its own fuel from waste compounds. It can output a flame hotter than regular welders."
	icon_state = "exwelder"
	max_fuel = 40
	w_class = ITEMSIZE_NORMAL
	toolspeed = 0.5
	change_icons = 0
	flame_intensity = 3
	always_process = TRUE
	var/nextrefueltick = 0

/obj/item/weldingtool/experimental/periodic_step()
	..()
	if(get_fuel() < get_max_fuel() && COOLDOWN_FINISHED(src, nextrefueltick))
		COOLDOWN_START(src, nextrefueltick, 1 SECONDS)
		reagents.add_reagent(REAGENT_ID_FUEL, 1)

/obj/item/weldingtool/experimental/hybrid
	name = "strange welding tool"
	desc = "An experimental welder capable of synthesizing its own fuel from spatial waveforms. It's like welding with a star!"
	icon_state = "hybwelder"
	max_fuel = 80 //more max fuel is better! Even if it doesn't actually use fuel.
	eye_safety_modifier = -2	// Brighter than the sun. Literally, you can look at the sun with a welding mask of proper grade, this will burn through that.
	toolspeed = 0.25
	w_class = ITEMSIZE_NORMAL
	flame_intensity = 5
	reach = 2

/*
 * Backpack Welder.
 */

/obj/item/weldingtool/tubefed
	name = "tube-fed welding tool"
	desc = "A bulky, cooler-burning welding tool that draws from a worn welding tank."
	icon_state = "tubewelder"
	max_fuel = 10
	w_class = ITEMSIZE_NO_CONTAINER
	MATERIAL_NONE
	toolspeed = 1.25
	change_icons = 0
	flame_intensity = 1
	eye_safety_modifier = 1
	always_process = FALSE

/obj/item/weldingtool/tubefed/Initialize(mapload)
	. = ..()
	if(istype(loc, /obj/item/weldpack))
		var/obj/item/weldpack/holder = loc
		rel_set(src, nameof(mounted_pack), holder)
	else
		return INITIALIZE_HINT_QDEL

// The weldpack owns its nozzle (implicit OWN); the nozzle names its pack (one-sided REL).
/// The pack this nozzle belongs to (a relation view, set once in Initialize()): a field, so its
/// automatic clear when the pack is destroyed re-evaluates burner_active.
OM_FIELD_VIEW(/obj/item/weldingtool/tubefed, obj/item/weldpack, mounted_pack, CHANGE_EXPLICIT)
OM_DERIVE_FIELD(/obj/item/weldingtool/tubefed, burner_active, list("mounted_pack", CHANGE_ITEM_LOC))

/// A nozzle works (and watches its hose) only while it is out of its pack.
/obj/item/weldingtool/tubefed/burner_active()
	return mounted_pack && loc != mounted_pack

/obj/item/weldingtool/tubefed/periodic_step()
	if(!ishuman(mounted_pack.loc))
		mounted_pack.return_nozzle()
	else
		var/mob/living/carbon/human/H = mounted_pack.loc
		if(H.get_equipped_item(SLOT_ID_BACK) != mounted_pack)
			mounted_pack.return_nozzle()

	if(mounted_pack.loc != src.loc && src.loc != mounted_pack)
		mounted_pack.return_nozzle()
		visible_message(span_infoplain(span_bold("\The [src]") + " retracts to its fueltank."))

	if(get_fuel() <= get_max_fuel())
		mounted_pack.reagents.trans_to_obj(src, 1)

	..()

/obj/item/weldingtool/tubefed/dropped(mob/user, equipping, slot)
	..()
	if(loc != user)
		mounted_pack.return_nozzle()
		to_chat(user, span_notice("\The [src] retracts to its fueltank."))

/obj/item/weldingtool/tubefed/survival
	name = "tube-fed emergency welding tool"
	desc = "A bulky, cooler-burning welding tool that draws from a worn welding tank."
	icon_state = "tubewelder"
	max_fuel = 5
	toolspeed = 1.75
	eye_safety_modifier = 2

/*
 * Electric/Arc Welder
 */

/obj/item/weldingtool/electric	//AND HIS WELDING WAS ELECTRIC
	name = "electric welding tool"
	desc = "A welder which runs off of electricity."
	icon_state = "arcwelder"
	max_fuel = 0	//We'll handle the consumption later.
	item_state = "ewelder"
	var/obj/item/cell/power_supply //What type of power cell this uses
	var/charge_cost = 24	//The rough equivalent of 1 unit of fuel, based on us wanting 10 welds per battery
	var/cell_type = /obj/item/cell/device
	var/use_external_power = 0	//If in a borg or hardsuit, this needs to = 1
	flame_color = "#00CCFF"  // Blue-ish, to set it apart from the gas flames.
	acti_sound = SFX_EFFECTS_SPARKS4
	deac_sound = SFX_EFFECTS_SPARKS4

/obj/item/weldingtool/electric/unloaded
	cell_type = null

/obj/item/weldingtool/electric/get_cell()
	return power_supply

/obj/item/weldingtool/electric/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(power_supply)
			. += "It [src.name] has [get_fuel()] charge left."
		else
			. += "It [src.name] has no power cell!"

/obj/item/weldingtool/electric/get_fuel()
	if(use_external_power)
		var/obj/item/cell/external = get_external_power_supply()
		if(external)
			return external.charge
	else if(power_supply)
		return power_supply.charge
	else
		return 0

/obj/item/weldingtool/electric/get_max_fuel()
	if(use_external_power)
		var/obj/item/cell/external = get_external_power_supply()
		if(external)
			return external.maxcharge
	else if(power_supply)
		return power_supply.maxcharge
	return 0

/obj/item/weldingtool/electric/remove_fuel(amount = 1, mob/M = null)
	if(!welding)
		return 0
	if(get_fuel() >= amount)
		power_supply.checked_use(charge_cost)
		if(use_external_power)
			var/obj/item/cell/external = get_external_power_supply()
			if(!external || !external.use(charge_cost)) //Take power from the borg...
				power_supply.give(charge_cost)	//Give it back to the cell.
		if(M)
			eyecheck(M)
		update_icon()
		return 1
	else
		if(M)
			to_chat(M, span_notice("You need more energy to complete this task."))
		update_icon()
		return 0

EXTEND_INTERACTIONS(/obj/item/weldingtool/electric, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(electric_interaction_item)), \
)

/// Old attack_hand.
/obj/item/weldingtool/electric/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.get_inactive_hand() == src)
		if(power_supply)
			power_supply.update_icon()
			user.put_in_hands(power_supply)
			own_take(src, nameof(power_supply))
			to_chat(user, span_notice("You remove the cell from the [src]."))
			setWelding(0)
			update_icon()
			return TRUE
		return FALSE
	else
		return FALSE

/// Old attackby.
/obj/item/weldingtool/electric/proc/electric_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/cell))
		if(istype(W, /obj/item/cell/device))
			if(!power_supply)
				if(!move_into(src, nameof(src.power_supply), W, user))
					return FALSE
				to_chat(user, span_notice("You install a cell in \the [src]."))
				update_icon()
			else
				to_chat(user, span_notice("\The [src] already has a cell."))
		else
			to_chat(user, span_notice("\The [src] cannot use that type of cell."))
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/weldingtool/electric/proc/get_external_power_supply()
	if(isrobotmultibelt(src.loc)) //We are in a multibelt
		if(istype(src.loc.loc, /mob/living/silicon/robot))  //We are in a multibelt that is in a robot! This is sanity in case someone spawns a multibelt in via admin commands.
			var/mob/living/silicon/robot/R = src.loc.loc
			return R.cell
	if(isrobot(src.loc))
		var/mob/living/silicon/robot/R = src.loc
		return R.cell
	if(istype(src.loc, /obj/item/rig_module))
		var/obj/item/rig_module/module = src.loc
		if(module.holder && module.holder.wearer())
			var/mob/living/carbon/human/H = module.holder.wearer()
			if(istype(H) && H.get_equipped_item(SLOT_ID_BACK))
				var/obj/item/rig/suit = H.get_equipped_item(SLOT_ID_BACK)
				if(istype(suit))
					return suit.cell
	if(istype(src.loc, /obj/item/mecha_parts/mecha_equipment))
		var/obj/item/mecha_parts/mecha_equipment/mounting = src.loc
		if(mounting.chassis && mounting.chassis.cell)
			return mounting.chassis.cell
	return null

/obj/item/weldingtool/electric/mounted
	use_external_power = 1

/obj/item/weldingtool/electric/mounted/exosuit
	var/obj/item/mecha_parts/mecha_equipment/equip_mount
	flame_intensity = 1
	eye_safety_modifier = 2
	always_process = TRUE

/obj/item/weldingtool/electric/mounted/exosuit/Initialize(mapload)
	. = ..()

	if(istype(loc, /obj/item/mecha_parts/mecha_equipment))
		rel_set(src, nameof(equip_mount), loc)

/obj/item/weldingtool/electric/mounted/exosuit/periodic_step()
	..()

	if(equip_mount() && equip_mount().chassis)
		var/obj/mecha/M = equip_mount().chassis
		if(M.selected == equip_mount() && get_fuel())
			setWelding(TRUE, M?.slot_item(MECHA_SLOT_PILOT))
		else
			setWelding(FALSE, M?.slot_item(MECHA_SLOT_PILOT))

/obj/item/weldingtool/dummy
	name = "dummy welding tool"
	desc = "you shouldn't be reading this. Tell a dev!"
	welding = TRUE

/obj/item/weldingtool/dummy/periodic_step()
	return

/obj/item/weldingtool/dummy/burner_active()
	return FALSE

/obj/item/weldingtool/dummy/get_fuel()
	return get_max_fuel()

/obj/item/weldingtool/dummy/remove_fuel(amount = 1, mob/M = null)
	return TRUE

/obj/item/weldingtool/dummy/isOn()
	return TRUE

#undef WELDER_FUEL_BURN_INTERVAL

/obj/item/weldingtool/electric/ownership()
	. = ..()
	. += owns(nameof(power_supply), policy = OWN_CONTAINED, starts = nameof(cell_type))

/// Relation view: equip mount (reads null once it is gone).
/obj/item/weldingtool/electric/mounted/exosuit/proc/equip_mount() as /obj/item/mecha_parts/mecha_equipment
	return equip_mount
