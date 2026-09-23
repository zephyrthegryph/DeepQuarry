/obj/item/modular_computer/examine(mob/user)
	. = ..()
	if(damage > broken_damage)
		. += span_danger("It is heavily damaged!")
	else if(damage)
		. += "It is damaged."

/obj/item/modular_computer/proc/break_apart()
	visible_message("\The [src] breaks apart!")
	var/turf/newloc = get_turf(src)
	new /obj/item/stack/material/steel(newloc, round(steel_sheet_cost/2))
	for(var/obj/item/computer_hardware/H in get_all_components())
		uninstall_component(null, H)
		H.forceMove(newloc)
		if(prob(25))
			H.take_damage(rand(10,30))
	qdel(src)

/obj/item/modular_computer/take_damage(amount, component_probability, damage_casing = 1, randomize = 1)
	if(randomize)
		// 75%-125%, rand() works with integers, apparently.
		amount *= (rand(75, 125) / 100.0)
	amount = round(amount)
	if(damage_casing)
		damage += amount
		damage = between(0, damage, max_damage)

	if(component_probability)
		for(var/obj/item/computer_hardware/H in get_all_components())
			if(prob(component_probability))
				H.take_damage(round(amount / 2))

	if(damage >= max_damage)
		break_apart()

// Stronger explosions cause serious damage to internal components
// Minor explosions are mostly mitigitated by casing.
/obj/item/modular_computer/ex_act(severity)
	take_damage(rand(100,200) / severity, 30 / severity)

// EMPs are similar to explosions, but don't cause physical damage to the casing. Instead they screw up the components
/obj/item/modular_computer/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	take_damage(rand(100,200) / severity, 50 / severity, 0)

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
		take_damage(physical, physical / 2)
	if(thermal > 0)
		take_damage(thermal, thermal / 1.5)
	if(pain > 0)
		take_damage(pain, pain / 3, 0)
	return physical + thermal