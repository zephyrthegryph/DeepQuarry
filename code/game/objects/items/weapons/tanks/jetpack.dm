// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/obj/item/tank/jetpack
	name = "jetpack (empty)"
	desc = "A tank of compressed gas for use as propulsion in zero-gravity areas. Use with caution."
	icon = 'icons/obj/tank_vr.dmi'
	icon_state = "jetpack"
	gauge_icon = null
	w_class = ITEMSIZE_LARGE
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
			)
	item_state_slots = list(slot_r_hand_str = "jetpack", slot_l_hand_str = "jetpack")
	distribute_pressure = ONE_ATMOSPHERE*O2STANDARD
	var/datum/effect/effect/system/ion_trail_follow/ion_trail
	var/on = 0.0
	var/stabilization_on = 0
	var/volume_rate = 500              //Needed for borg jetpack transfer
	actions_types = list(/datum/action/item_action/toggle_jetpack)

/obj/item/tank/jetpack/Initialize(mapload)
	. = ..()
	ion_trail.set_up(src)

CAPABILITIES(/obj/item/tank/jetpack)
	owns_one(nameof(ion_trail), /datum/effect/effect/system/ion_trail_follow, starts = /datum/effect/effect/system/ion_trail_follow)
	op("toggle_rockets_effect", menu(), label("Toggle Jetpack Stabilization"), needs(carried()), then(PROC_REF(toggle_rockets_effect_op)))
	op("jetpack_toggle_effect", menu(), label("Toggle Jetpack"), needs(carried()), then(PROC_REF(jetpack_toggle_effect_op)))

/obj/item/tank/jetpack/examine(mob/user)
	. = ..()
	if(air_contents.total_moles() < 5)
		. += span_danger("The meter on \the [src] indicates you are almost out of gas!")
		play_sfx(src, SFX_EFFECTS_ALERT)

/obj/item/tank/jetpack/proc/toggle_rockets_effect(mob/user, obj/item/held)
	stabilization_on = !( stabilization_on )
	to_chat(user, "You toggle the stabilization [stabilization_on? "on":"off"].")

/obj/item/tank/jetpack/proc/jetpack_toggle_effect(mob/user, obj/item/held)

	on = !on
	if(on)
		icon_state = "[icon_state]-on"
		ion_trail.start()
	else
		icon_state = initial(icon_state)
		ion_trail.stop()

	if (ismob(user))
		var/mob/M = user
		M.update_inv_back()
		M.update_mob_action_buttons()

	to_chat(user, "You toggle the thrusters [on? "on":"off"].")

/obj/item/tank/jetpack/proc/get_gas_supply()
	return air_contents

/obj/item/tank/jetpack/proc/can_thrust(num)
	if(!on)
		return 0

	var/datum/gas_mixture/fuel = get_gas_supply()
	if(num < 0.005 || !fuel || fuel.total_moles() < num)
		ion_trail.stop()
		return 0

	return 1

/obj/item/tank/jetpack/proc/do_thrust(num, mob/living/user)
	if(!can_thrust(num))
		return 0

	var/datum/gas_mixture/fuel = get_gas_supply()
	fuel.remove(num)
	return 1

/obj/item/tank/jetpack/ui_action_click(mob/user, actiontype)
	jetpack_toggle_effect(user)

/obj/item/tank/jetpack/void
	name = "void jetpack (oxygen)"
	desc = "It works well in a void."
	icon_state = "jetpack-void"
	item_state_slots = list(slot_r_hand_str = "jetpack-void", slot_l_hand_str = "jetpack-void")

DECLARE_GAS(/obj/item/tank/jetpack/void, "air_contents", "volume", T20C, list(GAS_O2 = 6*ONE_ATMOSPHERE))
/obj/item/tank/jetpack/oxygen
	name = "jetpack (oxygen)"
	desc = "A tank of compressed oxygen for use as propulsion in zero-gravity areas. Use with caution."
	icon_state = "jetpack"
	item_state_slots = list(slot_r_hand_str = "jetpack", slot_l_hand_str = "jetpack")

DECLARE_GAS(/obj/item/tank/jetpack/oxygen, "air_contents", "volume", T20C, list(GAS_O2 = 6*ONE_ATMOSPHERE))
/obj/item/tank/jetpack/breaker
	name = "CSC industrial jetpack"
	desc = "A JetFast EVA thruster pack. A warning label clearly states \'WARNING: CONTAINS VOLATILE REACTION MASS TOXIC TO MOST LIFEFORMS. NOT TO BE USED WITH CLOSED CYCLE BREATHING SYSTEMS.\'"
	icon_state = "jetpack-breaker"
	item_state_slots = list(slot_r_hand_str = "jetpack", slot_l_hand_str = "jetpack")

DECLARE_GAS(/obj/item/tank/jetpack/breaker, "air_contents", "volume", T20C, list(GAS_VOLATILE_FUEL = 6*ONE_ATMOSPHERE))
/obj/item/tank/jetpack/carbondioxide
	name = "jetpack (carbon dioxide)"
	desc = "A tank of compressed carbon dioxide for use as propulsion in zero-gravity areas. Painted black to indicate that it should not be used as a source for internals."
	distribute_pressure = 0
	icon_state = "jetpack-black"
	item_state_slots = list(slot_r_hand_str = "jetpack-black", slot_l_hand_str = "jetpack-black")

DECLARE_GAS(/obj/item/tank/jetpack/carbondioxide, "air_contents", "volume", T20C, list(GAS_CO2 = 6*ONE_ATMOSPHERE))
/obj/item/tank/jetpack/rig
	name = "jetpack"
	var/obj/item/rig/holder

/obj/item/tank/jetpack/rig/examine()
	. = ..()
	. += "It's a jetpack. If you can see this, report it on the bug tracker."

/obj/item/tank/jetpack/rig/get_gas_supply()
	return holder_ref()?.air_supply?.air_contents

/// Relation view: holder (reads null once it is gone).
/obj/item/tank/jetpack/rig/proc/holder_ref() as /obj/item/rig
	return holder
/// Old object verbs.
/// The toggle_rockets_effect op: the verb's effect, as the old resolver ran it.
/obj/item/tank/jetpack/proc/toggle_rockets_effect_op(datum/act/op/A)
	toggle_rockets_effect(A.actor, A.held)
	return OP_OK

/// The jetpack_toggle_effect op: the verb's effect, as the old resolver ran it.
/obj/item/tank/jetpack/proc/jetpack_toggle_effect_op(datum/act/op/A)
	jetpack_toggle_effect(A.actor, A.held)
	return OP_OK
