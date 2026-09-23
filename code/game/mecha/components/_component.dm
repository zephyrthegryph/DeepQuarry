
/obj/item/mecha_parts/component
	name = "mecha component"
	icon = 'icons/mecha/mech_component.dmi'
	icon_state = "component"
	w_class = ITEMSIZE_HUGE

	var/component_type = null

	var/obj/mecha/chassis = null
	var/start_damaged = FALSE

	var/emp_resistance = 0	// Amount of emp 'levels' removed.

	var/list/required_type = null	// List, if it exists. Exosuits meant to use the component (Unique var changes / effects)

	// A component's condition is its integrity. At zero it is wrecked but stays
	// installed (efficiency 0) until it is repaired or replaced.
	max_integrity = 100
	var/integrity_danger_mod = 0.5	// Multiplier for comparison to max_integrity before problems start.

	var/step_delay = 0

	var/relative_size = 30	// Percent chance for the component to be hit.

	var/internal_damage_flag	// If set, the component will toggle the flag on or off if it is destroyed / severely damaged.

/obj/item/mecha_parts/component/examine(mob/user)
	. = ..()
	var/show_integrity = round(get_integrity()/max_integrity*100, 0.1)
	switch(show_integrity)
		if(85 to 100)
			. += "It's fully intact."
		if(65 to 85)
			. += "It's slightly damaged."
		if(45 to 65)
			. += span_notice("It's badly damaged.")
		if(25 to 45)
			. += span_warning("It's heavily damaged.")
		if(2 to 25)
			. += span_boldwarning("It's falling apart.")
		if(0 to 1)
			. += span_boldwarning("It is completely destroyed.")

/obj/item/mecha_parts/component/Initialize(mapload)
	. = ..()
	if(start_damaged)
		update_integrity(round(max_integrity * integrity_danger_mod))

/obj/item/mecha_parts/component/Destroy()
	detach()
	return ..()

// Damage code.

/obj/item/mecha_parts/component/emp_act(severity = EMP_HARMLESS, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(severity + emp_resistance >= EMP_NONE)
		return

	severity = clamp(severity + emp_resistance, 1, 4)

	take_damage((4 - severity) * round(get_integrity() * 0.1, 0.1))

/// Repairs (positive) or wears (negative) the component. Wear passed on from the
/// chassis has already been through the mech's armour.
/obj/item/mecha_parts/component/proc/adjust_integrity(amt = 0)
	if(amt > 0)
		repair_damage(amt)
	else if(amt < 0)
		take_damage(-amt, BRUTE, null, FALSE)

/// A wrecked component stays a (useless) component. Fire and acid still destroy it.
/obj/item/mecha_parts/component/atom_destruction(damage_flag)
	if(damage_flag == FIRE || damage_flag == ACID)
		return ..()

/obj/item/mecha_parts/component/proc/damage_part(dam_amt = 0, type = BRUTE)
	if(dam_amt <= 0)
		return FALSE

	adjust_integrity(-1 * dam_amt)

	if(chassis && internal_damage_flag)
		if(get_efficiency() < 0.5)
			chassis.check_for_internal_damage(list(internal_damage_flag), TRUE)

	return TRUE

/obj/item/mecha_parts/component/proc/get_efficiency()
	var/integ_limit = round(max_integrity * integrity_danger_mod)

	var/current = get_integrity()
	if(current < integ_limit)
		var/int_percent = round(current / integ_limit, 0.1)

		return int_percent

	return 1

// Attach/Detach code.

/obj/item/mecha_parts/component/proc/attach(obj/mecha/target, mob/living/user)
	if(target)
		if(!(component_type in target.internal_components))
			if(user)
				to_chat(user, span_notice("\The [target] doesn't seem to have anywhere to put \the [src]."))
			return FALSE
		if(target.internal_components[component_type])
			if(user)
				to_chat(user, span_notice("\The [target] already has a [component_type] installed!"))
			return FALSE
		chassis = target
		if(user)
			user.drop_from_inventory(src)
		forceMove(target)

		if(internal_damage_flag)
			if(get_integrity() > (max_integrity * integrity_danger_mod))
				if(chassis.hasInternalDamage(internal_damage_flag))
					chassis.clearInternalDamage(internal_damage_flag)

			else
				chassis.check_for_internal_damage(list(internal_damage_flag))

		chassis.internal_components[component_type] = src

		if(user)
			chassis.visible_message(span_notice("[user] installs \the [src] in \the [chassis]."))
		return TRUE
	return FALSE

/obj/item/mecha_parts/component/proc/detach()
	if(chassis)
		chassis.internal_components[component_type] = null

		if(internal_damage_flag && chassis.hasInternalDamage(internal_damage_flag))	// If the module has been removed, it's kind of unfair to keep it causing problems by being damaged. It's nonfunctional either way.
			chassis.clearInternalDamage(internal_damage_flag)

		forceMove(get_turf(chassis))
	chassis = null
	return TRUE


/obj/item/mecha_parts/component/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W,/obj/item/stack/nanopaste))
		var/obj/item/stack/nanopaste/NP = W

		if(get_integrity() < max_integrity)
			to_chat(user, span_notice("You start to repair damage to \the [src]."))
			while(get_integrity() < max_integrity && NP)
				if(do_after(user, 1 SECOND, target = src))
					NP.use(1)
					adjust_integrity(NP.mech_repair)

					if(get_integrity() >= max_integrity)
						to_chat(user, span_notice("You finish repairing \the [src]."))
						break

					else if(NP.amount == 0)
						to_chat(user, span_warning("Insufficient nanopaste to complete repairs!"))
						break


			return

		else
			to_chat(user, span_notice("\The [src] doesn't require repairs."))

	return ..()

// Various procs to handle different calls by Exosuits. IE, movement actions, damage actions, etc.

/obj/item/mecha_parts/component/proc/get_step_delay()
	return step_delay

/obj/item/mecha_parts/component/proc/handle_move()
	return
