// Machine body plans: cyborgs, drones and AI cores.
//
// Machines are synthetic simple bodies. The plan is the only death rule:
//   - load at least DQ_MACHINE_LETHAL_MULT × endurance, or
//   - a robot's core part destroyed, or
//   - an AI's backup capacitor exhausted while unpowered (the capacitor is the
//     AI's pump source).
// Consciousness comes from the plan too: afflictions' consciousness penalties,
// brownout (the power bus can't meet demand) and incapacitation. Nothing else
// sets a machine's stat.

/datum/body/simple/machine
	plan_flag = BODY_PLAN_MACHINE

/// Machines don't breathe: no oxygen debt, and every respiratory query is null.
/datum/body/simple/machine/add_oxygen_debt(amount, source)
	return 0

/datum/body/simple/machine/oxygen_debt()
	return null

/datum/body/simple/machine/is_dead()
	ensure_vitals()
	return total_load >= owner.get_endurance() * DQ_MACHINE_LETHAL_MULT

/datum/body/simple/machine/recompute_vitals()
	..()
	var/max_load = owner.get_endurance() * DQ_MACHINE_LETHAL_MULT
	vitality = max_load > 0 ? clamp(1 - total_load / max_load, 0, 1) : 0
	consciousness = 100
	for(var/datum/affliction/A as anything in afflictions)
		consciousness -= A.consciousness_penalty()
	if(!owner.machine_power_ok())
		consciousness = 0 // brownout

/// Brownout and incapacitation change without any affliction changing, so a
/// machine evaluates its status every tick (cheap: cached vitals).
/datum/body/simple/machine/life_tick()
	if(LAZYLEN(afflictions) || (dirty & BODY_DIRTY_VITALS))
		return ..()
	evaluate_status()

/datum/body/simple/machine/is_unconscious()
	if(SEND_SIGNAL(owner, COMSIG_LIVING_BODY_STATUS) & COMPONENT_BODY_KEEP_ALIVE)
		return FALSE
	ensure_vitals()
	if(consciousness <= CONSCIOUSNESS_THRESHOLD)
		return TRUE
	return owner.paralysis || owner.stunned || owner.weakened

/// The one writer of a machine's conscious/unconscious stat.
/datum/body/simple/machine/update_consciousness()
	if(is_unconscious())
		if(owner.stat == CONSCIOUS)
			owner.set_stat(UNCONSCIOUS)
	else if(owner.stat == UNCONSCIOUS)
		owner.set_stat(CONSCIOUS)

/// Does the machine's power bus meet its demand? Anything that isn't a
/// powered chassis is always "powered".
/mob/living/proc/machine_power_ok()
	return TRUE


// --- Cyborgs ------------------------------------------------------------------------------

/mob/living/silicon/robot
	body_type = /datum/body/simple/machine/robot
	biology = BIOLOGY_SYNTHETIC

/datum/body/simple/machine/robot

/// Robots also die when their processor core is destroyed.
/datum/body/simple/machine/robot/is_dead()
	if(..())
		return TRUE
	var/mob/living/silicon/robot/R = owner
	var/datum/robot_component/core = R.get_component(ROBOT_SLOT_CORE)
	return core?.installed == ROBOT_PART_DESTROYED

/// A zone is a slot number or a component.
/datum/body/simple/machine/robot/resolve_zone(zone)
	if(istype(zone, /datum/robot_component))
		return zone
	if(isnum(zone))
		var/mob/living/silicon/robot/R = owner
		return R.get_component(zone)
	return null

/// The slot a synthetic affliction lives on, or null to go where the injury landed.
/datum/body/simple/machine/robot/proc/home_slot(affliction_type)
	if(ispath(affliction_type, /datum/affliction/synthetic/power_fault))
		return ROBOT_SLOT_POWER
	if(ispath(affliction_type, /datum/affliction/synthetic/coolant_leak) || ispath(affliction_type, /datum/affliction/synthetic/thermal_runaway))
		return ROBOT_SLOT_COOLING
	if(ispath(affliction_type, /datum/affliction/synthetic/actuator_misalignment))
		return ROBOT_SLOT_ACTUATOR
	if(ispath(affliction_type, /datum/affliction/synthetic/processor_corruption))
		return ROBOT_SLOT_CORE
	return null

/// Synthetic afflictions given without a location sit on their home slot.
/datum/body/simple/machine/robot/afflict(affliction_type, location = null, severity = 0)
	if(!location)
		var/slot = home_slot(affliction_type)
		if(slot)
			location = resolve_zone(slot)
	return ..(affliction_type, location, severity)

/// Injury lands on the named part, else the affliction's home part, else a
/// random part (armour first). The hit always lands as load; a named
/// affliction additionally takes hold on its home slot.
/datum/body/simple/machine/robot/receive_injury(kind, amount, zone, atom/source, affliction_type, flags)
	var/datum/robot_component/C = resolve_zone(zone)
	if(!C && affliction_type)
		C = resolve_zone(home_slot(affliction_type))
	if(!C)
		C = pick_damageable_component()
	if(affliction_type && !ispath(affliction_type, /datum/affliction/load))
		afflict(affliction_type)?.receive_injury(amount, kind, source)
	var/load_type = ispath(affliction_type, /datum/affliction/load) ? affliction_type : simple_load_type_for(kind, BIOLOGY_SYNTHETIC)
	if(!load_type)
		return 0
	var/datum/affliction/A = afflict(load_type, C)
	if(!A)
		return 0
	. = A.receive_injury(amount, kind, source)
	C?.on_integrity_changed()

/// Armour plating soaks spread hits first; otherwise a random installed
/// external part takes it. Internal parts (core, cooling) are only reached by
/// their own afflictions or targeted injury. `skip_armour` for surges that
/// bypass plating.
/datum/body/simple/machine/robot/proc/pick_damageable_component(skip_armour = FALSE)
	var/mob/living/silicon/robot/R = owner
	if(!skip_armour)
		var/datum/robot_component/armour = R.get_component(ROBOT_SLOT_ARMOUR)
		if(armour?.installed == ROBOT_PART_INSTALLED)
			return armour
	var/list/candidates = list()
	for(var/datum/robot_component/C as anything in R.components)
		if(C.internal || C.installed != ROBOT_PART_INSTALLED)
			continue
		if(skip_armour && C.slot == ROBOT_SLOT_ARMOUR)
			continue
		candidates += C
	return length(candidates) ? pick(candidates) : null

/// Load located on a part. Only load afflictions count toward a part's
/// damage; synthetic faults act through their own effects.
/datum/body/simple/machine/robot/proc/component_load(datum/robot_component/C, category = null)
	. = 0
	for(var/datum/affliction/load/L in afflictions_by_location?[C])
		if(!category || L.injury_category == category)
			. += L.load

/// Untargeted repair (welder, cable, recharger) spends one budget across the
/// damaged installed parts in random order. Destroyed parts can't be repaired
/// in place: they must be replaced.
/datum/body/simple/machine/robot/mend(tag, amount, zone = null)
	var/mob/living/silicon/robot/R = owner
	if(zone)
		. = ..()
		var/datum/robot_component/target = resolve_zone(zone)
		target?.on_integrity_changed()
		return
	. = 0
	var/list/parts = list()
	for(var/datum/robot_component/C as anything in R.components)
		if(C.installed == ROBOT_PART_INSTALLED)
			parts += C
	while(length(parts) && amount > 0)
		var/datum/robot_component/picked = pick_n_take(parts)
		var/treated = ..(tag, amount, picked)
		. += treated
		amount -= treated
	// Load that landed while no part was installed sits on the chassis.
	if(amount > 0 && (biology_of(null) & treatment_tag_biology(tag)))
		for(var/datum/affliction/A as anything in afflictions?.Copy())
			if(A.location || amount <= 0)
				continue
			var/rate = A.treatment_rate(tag)
			if(!rate)
				continue
			var/treated = A.receive_tagged_treatment(tag, amount * rate, FALSE)
			. += treated
			amount -= treated
		if(.)
			on_status_changed()
	for(var/datum/robot_component/C as anything in R.components)
		C.on_integrity_changed()

/// Rejuvenate: afflictions are cleared by fully_heal(); the mob rebuilds its
/// destroyed parts in /mob/living/silicon/robot/rejuvenate().
/datum/body/simple/machine/robot/restore()
	return


// --- AI cores -------------------------------------------------------------------------------

/mob/living/silicon/ai
	body_type = /datum/body/simple/machine/ai
	biology = BIOLOGY_SYNTHETIC

/// The AI plan: the backup capacitor is the core's pump source when mains
/// and APU power are gone. One death rule: hardware load, or an empty
/// capacitor.
/datum/body/simple/machine/ai

/datum/body/simple/machine/ai/is_dead()
	if(..())
		return TRUE
	var/mob/living/silicon/ai/AI = owner
	return istype(AI) && AI.backup_charge <= 0

/// An AI core doesn't pass out; losing power is handled by its power system.
/datum/body/simple/machine/ai/update_consciousness()
	return


// --- Other synthetic simple bodies ------------------------------------------------------------

/mob/living/silicon
	biology = BIOLOGY_SYNTHETIC

/mob/living/bot
	biology = BIOLOGY_SYNTHETIC
