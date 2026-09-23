/// Destructible, event-driven bridge between physical station damage and the
/// authoritative department simulation.
/obj/machinery/generated_station_department_control
	name = "department control node"
	desc = "A hardened automation core coordinating this department's systems."
	icon = 'icons/obj/machines/research.dmi'
	icon_state = "server"
	density = TRUE
	anchored = TRUE
	max_integrity = 200
	var/station_id
	var/department_id
	var/captured = FALSE
	var/captured_by

/obj/machinery/generated_station_department_control/on_update_integrity(old_value, new_value)
	. = ..()
	publish_integrity()

/obj/machinery/generated_station_department_control/atom_destruction(damage_flag)
	var/datum/generated_station_simulation/simulation = generated_station_runtime(station_id)
	simulation?.set_integrity(department_id, 0)
	return ..()

/obj/machinery/generated_station_department_control/proc/publish_integrity()
	var/datum/generated_station_simulation/simulation = generated_station_runtime(station_id)
	if(simulation)
		simulation.set_integrity(department_id, round(100 * get_integrity() / max_integrity))

/obj/machinery/generated_station_department_control/examine(mob/user)
	. = ..()
	var/datum/generated_station_simulation/simulation = generated_station_runtime(station_id)
	var/state = simulation?.department_state(department_id) || GENERATED_DEPARTMENT_OFFLINE
	var/state_name = state == GENERATED_DEPARTMENT_OPERATIONAL ? "operational" : (state == GENERATED_DEPARTMENT_DEGRADED ? "degraded" : "offline")
	. += span_notice("Department status: [state_name]. Control integrity: [round(100 * get_integrity() / max_integrity)]%.")
	if(captured)
		. += span_notice("Control authority has been captured by [captured_by || "an expedition team"].")

/obj/machinery/generated_station_department_control/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/department_control_override,
	)
	..()

/datum/interaction/machine_hand/department_control_override
	id = "department_control_override"
	name = "Override"
	behind_gate = FALSE
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/generated_station_department_control/proc/capturable, null))
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/generated_station_department_control/proc/interaction_override

/obj/machinery/generated_station_department_control/proc/capturable(mob/actor, atom/target, obj/item/held)
	return !captured && get_integrity() > 0

/obj/machinery/generated_station_department_control/proc/interaction_override(mob/user, obj/item/held, datum/interaction/interaction)
	user.visible_message(span_notice("[user] begins overriding [src]."), span_notice("You begin overriding [src]."))
	if(!do_after(user, 3 SECONDS, target = src) || QDELETED(src) || get_integrity() <= 0)
		return TRUE
	captured = TRUE
	captured_by = user.ckey || user.name
	visible_message(span_notice("[src] accepts the new control authority."))
	return TRUE

/obj/machinery/generated_station_department_control/Destroy()
	captured_by = null
	return ..()

/datum/generated_station_director
	var/list/registered_defenders
	var/security_reserves = 6

/datum/generated_station_director/proc/register_defender(mob/living/defender)
	if(!defender || QDELETED(defender))
		return FALSE
	LAZYOR(registered_defenders, defender)
	return TRUE

/datum/generated_station_director/proc/unregister_defender(mob/living/defender)
	LAZYREMOVE(registered_defenders, defender)

/datum/generated_station_director/proc/medical_heal(mob/living/defender, amount)
	if(!(defender in registered_defenders) || simulation.department_state("medical-1") == GENERATED_DEPARTMENT_OFFLINE)
		return FALSE
	var/cost = max(1, CEILING(amount / 10, 1))
	if(!simulation.consume_stockpile("medical-1", "medicine", cost))
		return FALSE
	defender.mend(TREAT_TISSUE_REPAIR, amount)
	defender.mend(TREAT_BURN_CARE, amount)
	defender.mend(TREAT_PLATING_REPAIR, amount)
	defender.mend(TREAT_WIRING_REPAIR, amount)
	on_capabilities_changed()
	return TRUE

/datum/generated_station_director/proc/engineering_repair(department_id, amount)
	if(amount <= 0 || simulation.department_state("engineering-1") == GENERATED_DEPARTMENT_OFFLINE)
		return FALSE
	var/datum/generated_station_department_runtime/target = simulation.departments[department_id]
	var/datum/generated_station_department_runtime/engineering = simulation.departments["engineering-1"]
	var/datum/generated_station_department_runtime/logistics = simulation.departments["logistics-1"]
	var/cost = max(1, CEILING(amount / 10, 1))
	if(!target || (engineering.stockpiles["fuel"] || 0) < cost || (logistics.stockpiles["supplies"] || 0) < cost)
		return FALSE
	simulation.consume_stockpile("engineering-1", "fuel", cost)
	simulation.consume_stockpile("logistics-1", "supplies", cost)
	simulation.set_integrity(department_id, target.integrity + amount)
	on_capabilities_changed()
	return TRUE

/datum/generated_station_director/proc/logistics_resupply(department_id, resource_id, amount)
	if(amount <= 0 || simulation.department_state("logistics-1") == GENERATED_DEPARTMENT_OFFLINE)
		return FALSE
	var/datum/generated_station_department_runtime/logistics = simulation.departments["logistics-1"]
	if(!simulation.departments[department_id] || (logistics.stockpiles["supplies"] || 0) < amount)
		return FALSE
	simulation.consume_stockpile("logistics-1", "supplies", amount)
	simulation.add_stockpile(department_id, resource_id, amount)
	on_capabilities_changed()
	return TRUE

/datum/generated_station_director/proc/request_security_reserve()
	if(security_reserves <= 0 || simulation.department_state("security-1") == GENERATED_DEPARTMENT_OFFLINE)
		return FALSE
	security_reserves--
	return TRUE

/datum/generated_station_director/proc/ai_can_coordinate()
	process_dirty()
	return strategic_online

/datum/expedition_site
	var/datum/generated_station_simulation/station_simulation
	var/datum/generated_station_director/station_director
	var/list/station_controls

/// Finds a clear, inspectable department position for the destructible control.
/proc/generated_station_control_turf(atom/core)
	var/turf/origin = get_turf(core)
	var/area/department_area = get_area(origin)
	var/turf/fallback
	for(var/turf/simulated/floor/T in range(8, origin))
		if(get_area(T) != department_area || T.density || locate(/obj/machinery/door) in T)
			continue
		var/blocked = FALSE
		for(var/atom/movable/occupant in T)
			if(occupant.density || istype(occupant, /obj/machinery))
				blocked = TRUE
				break
		if(blocked)
			continue
		if(!fallback)
			fallback = T
		if(generated_station_adjacent_wall_direction(T))
			return T
	// A department core is a semantic anchor, not a promise that an otherwise
	// suitable control tile exists within eight tiles. Large and irregular
	// departments can put their authored core farther from the nearest free wall.
	// Search the complete department before accepting the local fallback so every
	// planned department deterministically receives its control node.
	for(var/turf/simulated/floor/T in department_area)
		if(T.density || locate(/obj/machinery/door) in T)
			continue
		var/blocked = FALSE
		for(var/atom/movable/occupant in T)
			if(occupant.density || istype(occupant, /obj/machinery))
				blocked = TRUE
				break
		if(blocked)
			continue
		if(!fallback)
			fallback = T
		if(generated_station_adjacent_wall_direction(T))
			return T
	return fallback

/datum/expedition_site/proc/initialize_generated_station_runtime()
	if(!station_spec || station_simulation)
		return FALSE
	station_simulation = new(station_spec)
	station_director = new(station_simulation)
	station_controls = list()
	var/list/controlled_departments = list()
	for(var/obj/effect/landmark/generated_station_department_core/core in station_materialization?.control_landmarks)
		var/datum/generated_station_layout_node/node
		for(var/datum/generated_station_layout_node/candidate in station_spec.layout_nodes)
			if(candidate.id == core.department_node_id)
				node = candidate
				break
		if(!node)
			continue
		var/datum/generated_station_department_instance/department
		for(var/datum/generated_station_department_instance/candidate in station_spec.departments)
			if(candidate.id == node.department_instance_id)
				department = candidate
				break
		if(!department)
			continue
		var/turf/control_turf = generated_station_control_turf(core)
		if(!control_turf)
			qdel(core)
			continue
		var/obj/machinery/generated_station_department_control/control = new(control_turf)
		control.station_id = station_spec.id
		control.department_id = department.id
		station_controls += control
		controlled_departments[department.id] = TRUE
		qdel(core)
	// Landmarks are useful publication anchors, but they must not be a failure
	// route for a required gameplay object. A late structural/furnishing pass can
	// legitimately replace a landmark's original turf. Reconstruct any missing
	// department anchor from the authoritative module footprint instead.
	for(var/datum/generated_station_department_instance/department in station_spec.departments)
		if(controlled_departments[department.id])
			continue
		var/datum/generated_station_layout_node/department_node
		for(var/datum/generated_station_layout_node/candidate_node in station_spec.layout_nodes)
			if(candidate_node.department_instance_id == department.id)
				department_node = candidate_node
				break
		if(!department_node)
			continue
		var/turf/control_turf
		for(var/datum/generated_station_module/module in station_materialization.modules)
			if(module.department_node_id != department_node.id)
				continue
			for(var/key in module.footprint)
				var/list/parts = splittext(key, ",")
				var/turf/module_turf = station_materialization.world_turf(text2num(parts[1]), text2num(parts[2]))
				control_turf = generated_station_control_turf(module_turf)
				if(control_turf)
					break
			if(control_turf)
				break
		if(!control_turf)
			continue
		var/obj/machinery/generated_station_department_control/control = new(control_turf)
		control.station_id = station_spec.id
		control.department_id = department.id
		station_controls += control
		controlled_departments[department.id] = TRUE
	return TRUE

/// Re-runs the room-access solver after utility and strategic machinery exists.
/// Utility sockets are authoritative and remain fixed; authored furnishings are
/// relocated or degraded when their combination with those sockets creates an
/// articulation pocket. This makes the published live map playable by
/// construction rather than merely detecting the defect afterward.
/datum/expedition_site/proc/repair_generated_station_runtime_access()
	if(!station_materialization)
		return FALSE
	var/datum/generated_station_materializer/repairer = new
	repairer.result = station_materialization
	repairer.min_x = station_materialization.origin_x
	repairer.min_y = station_materialization.origin_y
	var/succeeded = repairer.finalize_furnishing_access()
	repairer.result = null
	qdel(repairer)
	return succeeded

/datum/expedition_site/proc/generated_station_status_text()
	if(!station_simulation)
		return null
	var/power = station_simulation.capability_available("power") ? "Power online" : "POWER OFFLINE"
	var/atmosphere = station_simulation.capability_available("atmosphere") ? "life support online" : "LIFE SUPPORT OFFLINE"
	var/coordination = station_director?.ai_can_coordinate() ? "AI coordinated" : "local control only"
	var/profile = station_spec ? "[station_spec.faction_id] [station_spec.architecture_style], security [station_spec.security_tier], [station_spec.size_class]" : "unprofiled"
	return "[power] · [atmosphere] · [coordination] · [profile]"
