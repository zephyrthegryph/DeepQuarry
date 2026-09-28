// Mech body model (damage.md §5, "Body model for mechs").
//
// A mech is not a /mob/living, so it cannot own a /datum/body: that datum is typed to a living
// owner and reaches into physiology, reagents and OM events. Instead a mech is a *body host*:
// it hands its hits to a stateless machine body plan, `/datum/mech_body_plan`, which is a
// flyweight shared by every mech (all state already lives on the mech and its components).
//
// - Body parts are the installed components (`/obj/mecha/var/internal_components`), walked in
//   the plan's `part_order`: armour plates first, then hull, then the internal parts
//   (actuators, electrical, life support), each hit by its `relative_size`.
// - Afflictions are the internal-damage conditions (`/datum/mech_affliction`, one flyweight per
//   MECHA_INT_* flag). The bitfield `internal_damage` stays as their compact store.
// - `injure()` is the one sink every hit goes through: packets (`receive_damage`), rounds
//   (`receive_projectile`), throws (`receive_thrown`) and legacy `take_damage` calls. It
//   replaces the old absorbDamage/dynabsorbdamage, components_handle_damage and
//   dynbulletdamage chain.

/// The shared machine body plan for mechs.
/proc/mech_body_plan()
	RETURN_TYPE(/datum/mech_body_plan)
	var/static/datum/mech_body_plan/plan
	if(!plan)
		plan = new /datum/mech_body_plan
	return plan

/datum/mech_body_plan
	var/name = "exosuit"

/// Body parts in the order a hit reaches them. Armour and hull soak first; the rest are
/// internal parts hit by chance.
/datum/mech_body_plan/proc/part_order()
	var/static/list/order = list(MECH_ARMOR, MECH_HULL, MECH_ACTUATOR, MECH_ELECTRIC, MECH_GAS)
	return order

/// The affliction flyweights, keyed by their MECHA_INT_* flag as text.
/datum/mech_body_plan/proc/afflictions()
	var/static/list/table
	if(!table)
		table = list()
		for(var/path in subtypesof(/datum/mech_affliction))
			var/datum/mech_affliction/A = new path
			if(A.flag)
				table["[A.flag]"] = A
	return table

/datum/mech_body_plan/proc/affliction_for(flag)
	return afflictions()["[flag]"]

/// A body part (installed component) by slot, or null.
/datum/mech_body_plan/proc/part(obj/mecha/host, slot)
	var/obj/item/mecha_parts/component/C = host.internal_components[slot]
	return istype(C) ? C : null

/// Chance for the armour plates to turn a hit away outright.
/datum/mech_body_plan/proc/deflect_chance(obj/mecha/host)
	var/obj/item/mecha_parts/component/armor/plates = part(host, MECH_ARMOR)
	if(!plates)
		return 0
	return round(plates.get_efficiency() * plates.deflect_chance + (host.defence_mode ? 25 : 0))

/// Damage multiplier when a hit fails to penetrate (1 without plates).
/datum/mech_body_plan/proc/fail_penetration_factor(obj/mecha/host)
	var/obj/item/mecha_parts/component/armor/plates = part(host, MECH_ARMOR)
	if(!plates)
		return 1
	return round(plates.get_efficiency() * plates.fail_penetration_value)

/// Penetration step for a hit that was not deflected: returns the multiplier (0 = the hit
/// bounced off), and tells the occupant and onlookers what happened.
/datum/mech_body_plan/proc/penetration_factor(obj/mecha/host, amount, penetration, atom/source)
	if(amount < host.damage_minimum)
		host.occupant_message(span_notice("\The [source] bounces off the armor."))
		host.visible_message("\The [source] bounces off \the [host] armor")
		return 0
	if(penetration < host.minimum_penetration)
		host.occupant_message(span_notice("\The [source] struggles to pierce \the [host] armor."))
		host.visible_message("\The [source] struggles to pierce \the [host] armor")
		return fail_penetration_factor(host)
	host.occupant_message(span_notice("\The [source] manages to pierce \the [host] armor."))
	return 1

/// The body sink. `armor_key` is an armour-table key (MELEE, BULLET, LASER, FIRE, ENERGY, BOMB, ...;
/// BRUTE and BURN are accepted and mapped). Distributes the hit over the body parts, takes what
/// is left off the chassis, and returns the chassis integrity lost.
/datum/mech_body_plan/proc/injure(obj/mecha/host, amount, armor_key = BRUTE)
	if(!amount || QDELETED(host))
		return 0
	if(amount < 0)
		// Legacy "negative damage" callers (the repair droid) are repairs.
		host.repair_damage(-amount)
		return 0
	if(armor_key == BRUTE)
		armor_key = MELEE
	else if(armor_key == BURN)
		armor_key = FIRE
	host.update_damage_alerts()

	var/damage = amount
	// Armour plates: the absorption table scales the hit, and the plates wear for it.
	var/obj/item/mecha_parts/component/armor/plates = part(host, MECH_ARMOR)
	if(plates)
		var/efficiency = plates.get_efficiency()
		var/absorb = plates.damage_absorption[armor_key]
		if(isnull(absorb))
			absorb = 1
		if(efficiency > 0.25)
			damage *= absorb
		var/plate_share = efficiency * (damage * 0.5) * absorb
		plates.damage_part(plate_share, armor_key)
		damage -= plate_share
	// Hull: takes 50-100% of what the plates let through while it holds.
	var/obj/item/mecha_parts/component/hull/hull = part(host, MECH_HULL)
	if(hull && hull.get_integrity())
		var/hull_share = round(rand(5, 10) / 10, 0.1) * damage
		hull.damage_part(hull_share, armor_key)
		damage -= hull_share
	// Internal parts: hit by chance, each taking a quarter.
	for(var/slot in part_order())
		if(slot == MECH_ARMOR || slot == MECH_HULL)
			continue
		var/obj/item/mecha_parts/component/C = part(host, slot)
		if(C && prob(C.relative_size))
			var/share = round(damage / 4, 0.1)
			C.damage_part(share)
			damage -= share

	damage = max(damage, 0)
	var/before = host.get_integrity()
	host.update_integrity(before - damage)
	host.update_health()
	host.log_append_to_last("Took [damage] points of damage. Damage type: \"[armor_key]\".", 1)
	return before - host.get_integrity()

/// A round hitting the mech (the old dynbulletdamage). Deflection, equipment, penetration,
/// then injure(); a hard hit may afflict the mech, and AP rounds can reach the pilot.
/datum/mech_body_plan/proc/receive_projectile(obj/mecha/host, obj/item/projectile/P)
	if(prob(deflect_chance(host)))
		host.occupant_message(span_notice("The armor deflects incoming projectile."))
		host.visible_message("The [host.name] armor deflects the projectile")
		host.log_append_to_last("Armor saved.")
		return 0
	if(P.injury_kind == INJURY_PAIN)
		host.use_power(P.agony * 5)
	. = 0
	if(!P.nodamage)
		var/ignore_threshold = istype(P, /obj/item/projectile/beam/pulse)
		var/pass_damage = P.damage
		for(var/obj/item/mecha_parts/mecha_equipment/ME in host.equipment)
			pass_damage = ME.handle_projectile_contact(P, pass_damage)
		var/factor = penetration_factor(host, pass_damage, P.armor_penetration, P)
		if(!factor)
			return 0
		pass_damage *= factor
		if(prob(25))
			host.spark_system.start()
		. = injure(host, pass_damage, injury_armor_key(P.injury_kind))
		if(QDELETED(host))
			return
		var/list/possible = list(MECHA_INT_FIRE, MECHA_INT_TEMP_CONTROL, MECHA_INT_TANK_BREACH, MECHA_INT_CONTROL_LOST, MECHA_INT_SHORT_CIRCUIT)
		if(pass_damage > host.internal_damage_minimum)
			host.check_for_internal_damage(possible.Copy(), ignore_threshold)
		// AP rounds can carry on inside.
		if(P.penetrating)
			var/distance = get_dist(P.starting, get_turf(host.loc))
			var/hit_occupant = TRUE
			for(var/i in 1 to min(P.penetrating, round(P.damage / 15)))
				var/mob/living/pilot = host.slot_item(MECHA_SLOT_PILOT)
				if(pilot && hit_occupant && prob(20))
					P.attack_mob(pilot, distance)
					hit_occupant = FALSE
				else if(pass_damage > host.internal_damage_minimum)
					host.check_for_internal_damage(possible.Copy(), TRUE)
				P.penetrating--
				if(prob(15))
					break
	P.on_hit(host)

/// A thrown thing hitting the mech (the old dynhitby).
/datum/mech_body_plan/proc/receive_thrown(obj/mecha/host, atom/movable/A)
	if(istype(A, /obj/item/mecha_parts/mecha_tracking))
		A.forceMove(host)
		host.visible_message("The [A] fastens firmly to [host].")
		return 0
	if(prob(deflect_chance(host)) || ismob(A))
		host.occupant_message(span_notice("\The [A] bounces off the armor."))
		host.visible_message("\The [A] bounces off \the [host] armor")
		host.log_append_to_last("Armor saved.")
		if(isliving(A))
			var/mob/living/M = A
			M.injure(INJURY_BLUNT, 10, null, host)
		return 0
	if(!isitem(A))
		return 0
	var/obj/item/O = A
	if(!O.throwforce)
		return 0
	var/pass_damage = O.throwforce
	var/factor = penetration_factor(host, pass_damage, O.armor_penetration, O)
	if(!factor)
		return 0
	for(var/obj/item/mecha_parts/mecha_equipment/ME in host.equipment)
		pass_damage = ME.handle_ranged_contact(A, pass_damage)
	pass_damage *= factor
	. = injure(host, pass_damage, MELEE)
	if(!QDELETED(host) && pass_damage > host.internal_damage_minimum)
		host.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL, MECHA_INT_TANK_BREACH, MECHA_INT_CONTROL_LOST))

// ---------------------------------------------------------------------------------------------
// Afflictions: the mech's internal-damage conditions.

/datum/mech_affliction
	var/name = "internal damage"
	/// MECHA_INT_* flag this affliction is stored as.
	var/flag = 0
	/// Pilot alarm text.
	var/alarm = "INTERNAL DAMAGE"
	/// Shown to the pilot when the affliction clears, if any.
	var/cleared_message

/// Called when the affliction clears.
/datum/mech_affliction/proc/on_cleared(obj/mecha/host)
	if(cleared_message)
		host.occupant_message(span_infoplain(span_blue(span_bold(cleared_message))))

/datum/mech_affliction/fire
	name = "internal fire"
	flag = MECHA_INT_FIRE
	alarm = "INTERNAL FIRE"
	cleared_message = "Internal fire extinquished."

/datum/mech_affliction/life_support
	name = "life support failure"
	flag = MECHA_INT_TEMP_CONTROL
	alarm = "LIFE SUPPORT SYSTEM MALFUNCTION"
	cleared_message = "Life support system reactivated."

/datum/mech_affliction/life_support/on_cleared(obj/mecha/host)
	..()
	host.start_process(MECHA_PROC_INT_TEMP)

/datum/mech_affliction/tank_breach
	name = "tank breach"
	flag = MECHA_INT_TANK_BREACH
	alarm = "GAS TANK BREACH"
	cleared_message = "Damaged internal tank has been sealed."

/datum/mech_affliction/control_damage
	name = "control damage"
	flag = MECHA_INT_CONTROL_LOST
	alarm = "COORDINATION SYSTEM CALIBRATION FAILURE"

/datum/mech_affliction/short_circuit
	name = "short circuit"
	flag = MECHA_INT_SHORT_CIRCUIT
	alarm = "SHORT CIRCUIT"
