///Called when the obj is exposed to fire.
/obj/fire_act(exposed_temperature, exposed_volume)
	if(HAS_TRAIT(src, TRAIT_UNDERFLOOR))
		return
	// Objects whose rules watch their temperature take the exposure on their heat node.
	dq_rule_expose_heat(src, exposed_temperature)
	// Heat reaches the holder's contents through its slots' paths (C2).
	if(length(contents))
		propagate_fire(exposed_temperature, exposed_volume)
		if(QDELETED(src))
			return
	// Generic map machinery remains dormant under nominal room conditions, but
	// crossing into an actual thermal hazard activates its material assembly so
	// continued exposure, cooling, diagnostics, and repair use the same model as
	// custom-built equipment.
	if(ismachinery(src) && exposed_temperature > T0C + 100)
		var/datum/material/hazard_material = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
		material_service_event(MATERIAL_EVENT_TEMPERATURE, hazard_material ? exposed_temperature / max(hazard_material.melting_point, 1) : 0, exposed_temperature)
	var/potential_damage = 0.02 * exposed_temperature
	var/datum/material/exterior_material = material_for_role(MATERIAL_ROLE_JACKET) || material_for_role(MATERIAL_ROLE_INSULATION) || material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	if(exterior_material)
		var/thermal_load = exposed_temperature / max(exterior_material.melting_point, T20C)
		potential_damage *= clamp(thermal_load, 0.1, 4)
	// guard take_damage with uses_integrity; LINDA hotspots iterate
	// every atom on a turf, including landmarks/effects that opt out of the
	// damage system. Without this guard, fires runtime-error in CI maps.
	if(exposed_temperature && uses_integrity && !(resistance_flags & FIRE_PROOF) && (potential_damage > damage_deflection))
		deal_damage(DAMAGE_THERMAL, clamp(potential_damage, 0, 20), FIRE, flags = DAMAGE_PACKET_SILENT)
	if(QDELETED(src)) // take_damage() can send our obj to an early grave, let's stop here if that happens
		return
	// Types with an ignition rule (code/datums/rules/declarations.dm) catch fire from the rule instead.
	if(!(resistance_flags & ON_FIRE) && (resistance_flags & FLAMMABLE) && !(resistance_flags & FIRE_PROOF) && !RULES_REPLACE(type, RULE_REPLACES_IGNITION))
		AddComponent(/datum/component/burning, custom_fire_overlay() || GLOB.fire_overlay, burning_particles)
		SEND_SIGNAL(src, COMSIG_ATOM_FIRE_ACT, exposed_temperature, exposed_volume)
		return TRUE
	return ..()

/// Explosion adapter: blast from the propagated severity, delivered in type
/// batches by SSexplosions. Objects are destroyed by integrity.
/obj/ex_act(severity)
	if(..())
		return
	receive_explosion(severity)

/// EMP adapter: an ionic packet from the shared ladder. Only types with an
/// emp_integrity_factor lose integrity to it.
/obj/emp_act(severity, recursive)
	. = ..()
	if(. & EMP_PROTECT_SELF || !emp_integrity_factor)
		return
	receive_emp(severity)

/// Returns a custom fire overlay, if any
/obj/proc/custom_fire_overlay()
	return custom_fire_overlay

///called when the obj is destroyed by acid.
/obj/proc/acid_melt()
	deconstruct(FALSE)

/// Should be called when the atom is destroyed by fire, comparable to acid_melt() proc
/obj/proc/burn()
	deconstruct(FALSE)

/**
 * Custom behaviour per atom subtype on how they should deconstruct themselves
 * Arguments
 *
 * * disassembled - TRUE means we cleanly took this atom apart using tools. FALSE means this was destroyed in a violent way
 */
/obj/proc/atom_deconstruct(disassembled = TRUE)
	PROTECTED_PROC(TRUE)

	return

/**
 * The interminate proc between deconstruct() & atom_deconstruct(). By default this delegates deconstruction to
 * atom_deconstruct if NO_DEBRIS_AFTER_DECONSTRUCTION is absent but subtypes can override this to handle NO_DEBRIS_AFTER_DECONSTRUCTION in their
 * own unique way. Override this if for example you want to dump out important content like mobs from the
 * atom before deconstruction regardless if NO_DEBRIS_AFTER_DECONSTRUCTION is present or not
 * Arguments
 *
 * * disassembled - TRUE means we cleanly took this atom apart using tools. FALSE means this was destroyed in a violent way
 */
/obj/proc/handle_deconstruct(disassembled = TRUE)
	SHOULD_CALL_PARENT(FALSE)

	if(!(obj_flags & NO_DEBRIS_AFTER_DECONSTRUCTION))
		atom_deconstruct(disassembled)

/obj/proc/deconstruct(disassembled = TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)

	//allow objects to deconstruct themselves
	handle_deconstruct(disassembled)

	//inform objects we were deconstructed
	SEND_SIGNAL(src, COMSIG_OBJ_DECONSTRUCT, disassembled)

	for(var/obj/item/item in contents)
		if(item.item_flags & ABSTRACT)
			continue
		item.forceMove(get_turf(src))

	//delete our self
	qdel(src)

///what happens when the obj's integrity reaches zero.
/obj/atom_destruction(damage_flag)
	. = ..()
	if(damage_flag == ACID)
		acid_melt()
	else if(damage_flag == FIRE)
		burn()
	else
		deconstruct(FALSE)
