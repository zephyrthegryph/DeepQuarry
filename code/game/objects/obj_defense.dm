/obj
	/// Debris created when the object is destroyed (not disassembled). Declared per
	/// type; atom_destruction() spawns it before the slots' drop policies run.
	/// Types with several kinds of debris override debris_entries().
	var/debris_type
	var/debris_amount = 1

/// An explicit exposure to fire (lava, a flamethrower, a bonfire, a lighter):
/// a pulse of heat into the object's heat node. Ignition, melting, overheating
/// damage and every per-type heat behaviour are rules on that node
/// (code/datums/rules/declarations.dm). Hotspots don't call this: they couple
/// the objects on their tile to the burning gas (heat_objects.dm).
/obj/fire_act(exposed_temperature, exposed_volume)
	if(HAS_TRAIT(src, TRAIT_UNDERFLOOR) || !isnum(exposed_temperature))
		return
	// Heat reaches the holder's contents through its slots' paths (C2).
	if(length(contents))
		propagate_fire(exposed_temperature, exposed_volume)
		if(QDELETED(src))
			return
	expose_heat(exposed_temperature)
	// Generic map machinery remains dormant under nominal room conditions, but
	// crossing into an actual thermal hazard activates its material assembly so
	// continued exposure, cooling, diagnostics, and repair use the same model as
	// custom-built equipment.
	if(ismachinery(src) && exposed_temperature > T0C + 100)
		var/datum/material/hazard_material = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
		material_service_event(MATERIAL_EVENT_TEMPERATURE, hazard_material ? exposed_temperature / max(hazard_material.melting_point, 1) : 0, exposed_temperature)
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

	// Destroyed: each slot's drop policy decides what survives (damage.md §6,
	// doc/rewrite/lifecycle.md §3). Only what is left outside a slot falls
	// out below. This runs the same contents resolution the destroy
	// transaction's phase 3 uses (code/datums/containment/lifecycle.dm),
	// directly -- deconstruct() isn't itself going through qdel() yet here.
	if(!disassembled)
		dq_lifecycle_resolve_contents()

	for(var/obj/item/item in contents)
		if(item.item_flags & ABSTRACT)
			continue
		item.forceMove(get_turf(src))

	//delete our self
	qdel(src)

///what happens when the obj's integrity reaches zero.
/// Destruction (damage.md §6): debris entries first, then each slot's drop policy.
/obj/atom_destruction(damage_flag)
	. = ..()
	if(damage_flag == ACID)
		acid_melt()
	else if(damage_flag == FIRE)
		burn()
	else
		spawn_debris()
		deconstruct(FALSE)

/// This type's debris: path -> amount, or null. A shared list; don't modify it.
/obj/proc/debris_entries()
	if(!debris_type)
		return null
	return list((debris_type) = debris_amount)

/// Create the debris entries on the turf. Stacks get their amount.
/obj/proc/spawn_debris()
	var/turf/T = get_turf(src)
	var/list/entries = debris_entries()
	if(!T || !length(entries))
		return
	for(var/path in entries)
		var/amount = entries[path] || 1
		if(ispath(path, /obj/item/stack))
			new path(T, amount)
			continue
		for(var/i in 1 to amount)
			new path(T)
