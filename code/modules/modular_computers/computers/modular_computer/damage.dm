/obj/item/modular_computer/examine(mob/user)
	. = ..()
	if(computer_broken())
		. += span_danger("It is heavily damaged!")
	else if(get_integrity_damage())
		. += "It is damaged."

/obj/item/modular_computer/proc/break_apart()
	visible_message("\The [src] breaks apart!")
	var/turf/newloc = get_turf(src)
	new /obj/item/stack/material/steel(newloc, round(steel_sheet_cost/2))
	for(var/obj/item/computer_hardware/H in get_all_components())
		uninstall_component(null, H)
		H.forceMove(newloc)
		if(prob(25))
			H.take_damage(rand(10,30), BRUTE, null, FALSE)
	qdel(src)

/// Below integrity_failure the computer ceases to operate.
/obj/item/modular_computer/proc/computer_broken()
	return get_integrity() < max_integrity * integrity_failure

/obj/item/modular_computer/atom_break(damage_flag)
	. = ..()
	if(enabled)
		shutdown_computer()

/// At zero integrity the chassis breaks apart and drops its parts. Fire and acid still destroy it outright.
/obj/item/modular_computer/atom_destruction(damage_flag)
	if(damage_flag == FIRE || damage_flag == ACID)
		return ..()
	break_apart()

/// Damages the casing and, with `component_probability`% chance each, the
/// installed hardware (half as hard). The casing takes no armour.
/obj/item/modular_computer/proc/damage_computer(amount, component_probability, damage_casing = TRUE, randomize = TRUE)
	if(randomize)
		// 75%-125%, rand() works with integers, apparently.
		amount *= (rand(75, 125) / 100.0)
	amount = round(amount)
	if(amount <= 0)
		return 0

	if(component_probability)
		for(var/obj/item/computer_hardware/H in get_all_components())
			if(prob(component_probability))
				H.take_damage(round(amount / 2), BRUTE, null, FALSE)

	if(damage_casing)
		return take_damage(amount, BRUTE, null, FALSE)
	return 0

// Stronger explosions cause serious damage to internal components
// Minor explosions are mostly mitigitated by casing.
/obj/item/modular_computer/ex_act(severity)
	damage_computer(rand(100,200) / severity, 30 / severity, TRUE)

// EMPs are similar to explosions, but don't cause physical damage to the casing. Instead they screw up the components
/obj/item/modular_computer/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	damage_computer(rand(100,200) / severity, 50 / severity, FALSE)

// "Stun" weapons can cause minor damage to components (short-circuits?)
// "Burn" damage is equally strong against internal components and exterior casing
// "Brute" damage mostly damages the casing.
/// Packet sink for the casing/component pool. Stun rounds cause minor
/// component damage (short-circuits), burns hit components and casing
/// equally, and physical damage mostly hits the casing.
/obj/item/modular_computer/receive_damage(datum/damage_packet/packet)
	var/list/amounts = packet.amounts
	var/physical = amounts[DAMAGE_BLUNT] + amounts[DAMAGE_SHARP] + amounts[DAMAGE_PIERCE] + amounts[DAMAGE_BLAST]
	var/thermal = amounts[DAMAGE_THERMAL] + amounts[DAMAGE_CORROSIVE]
	var/pain = amounts[DAMAGE_PAIN]
	if(physical > 0)
		damage_computer(physical, physical / 2)
	if(thermal > 0 && !QDELETED(src))
		damage_computer(thermal, thermal / 1.5)
	if(pain > 0 && !QDELETED(src))
		damage_computer(pain, pain / 3, FALSE)
	return physical + thermal
