/*
 * /datum/rig_component_registry
 *
 * Owns lifecycle management for the six physical pieces that make up a
 * hardsuit (chest, helmet, boots, gloves, cell, air_supply).
 *
 * Responsibilities:
 *   - Spawn pieces on Initialize and track which types were requested
 *   - Propagate rig-level stats (armor, temperature, siemens) to pieces
 *   - Destroy pieces and null refs on rig teardown
 *   - Provide the canonical list of equippable pieces for iteration
 *
 * The piece vars themselves (holder.chest, holder.helmet, etc.) stay on
 * /obj/item/rig so the TGUI, modules, and existing proc code remain unmodified.
 */

/datum/rig_component_registry
	/// The rig this datum belongs to.  Nulled on Destroy().
	var/tmp/obj/item/rig/holder

/datum/rig_component_registry/New(obj/item/rig/new_holder)
	rel_set(src, nameof(holder), new_holder)

/*
 * proc/initialize_pieces()
 *
 * Spawns all physical rig pieces based on the holder's *_type vars and
 * populates the holder's piece vars.  Propagates shared stats (armor,
 * temperature limits, siemens) to each piece.  Must be called from
 * /obj/item/rig/Initialize().
 */
/datum/rig_component_registry/proc/initialize_pieces()
	// Spawn modules first so they exist before pieces reference back to the rig
	if(holder().initial_modules && holder().initial_modules.len)
		for(var/path in holder().initial_modules)
			var/obj/item/rig_module/module = new path(holder())
			rel_add(holder(), nameof(/obj/item/rig::installed_modules), module)
			module.installed(holder())

	// Spawn the six physical components
	if(holder().cell_type)
		var/new_cell_type_path = holder().cell_type
		rel_set(holder(), nameof(/obj/mecha::cell), new new_cell_type_path(holder()))
	if(holder().air_type)
		var/new_air_type_path = holder().air_type
		rel_set(holder(), nameof(/obj/item/rig::air_supply), new new_air_type_path(holder()))
	if(holder().glove_type)
		var/new_glove_type_path = holder().glove_type
		rel_set(holder(), nameof(/obj/item/rig::gloves), new new_glove_type_path(holder()))
	if(holder().helm_type)
		var/new_helm_type_path = holder().helm_type
		rel_set(holder(), nameof(/obj/item/rig::helmet), new new_helm_type_path(holder()))
	if(holder().boot_type)
		var/new_boot_type_path = holder().boot_type
		rel_set(holder(), nameof(/obj/item/rig::boots), new new_boot_type_path(holder()))
	if(holder().chest_type)
		var/new_chest_type_path = holder().chest_type
		rel_set(holder(), nameof(/obj/item/rig::chest), new new_chest_type_path(holder()))
		holder().chest.adopt_constraint(CONSTRAINT_SUIT_STORAGE, holder())

	// Apply shared stats to equippable pieces
	propagate_stats()

/*
 * proc/propagate_stats()
 *
 * Copies the rig's armor, temperature limits, siemens coefficient,
 * permeability, and unacidable flag to each equippable piece (chest,
 * helmet, boots, gloves).  Called after Initialize; can also be called
 * when subtype overrides change these values at runtime.
 */
/datum/rig_component_registry/proc/propagate_stats()
	for(var/obj/item/piece in get_equippable_pieces())
		if(!istype(piece))
			continue
		piece.canremove = FALSE
		piece.name = "[holder().suit_type] [initial(piece.name)]"
		piece.desc = "It seems to be part of a [holder().name]."
		piece.icon_state = "[holder().suit_state]"
		piece.min_cold_protection_temperature = holder().min_cold_protection_temperature
		piece.max_heat_protection_temperature = holder().max_heat_protection_temperature
		// Preserve insulated gloves that already have a lower coefficient
		if(piece.siemens_coefficient > holder().siemens_coefficient)
			piece.siemens_coefficient = holder().siemens_coefficient
		piece.permeability_coefficient = holder().permeability_coefficient
		piece.unacidable = holder().unacidable
		piece.set_armor(holder().get_armor())
		piece.worn_protection_changed()

/*
 * proc/destroy_pieces()
 *
 * Drops and disposes all six physical pieces through their owning slots.
 * Called from /obj/item/rig/on_destroy() with the rig itself: the holder
 * handle no longer resolves once the rig is being destroyed.
 */
/datum/rig_component_registry/proc/destroy_pieces(obj/item/rig/R)
	if(!R)
		return
	var/list/pieces = list(
		nameof(R.gloves) = R.gloves,
		nameof(R.boots) = R.boots,
		nameof(R.helmet) = R.helmet,
		nameof(R.chest) = R.chest,
		nameof(R.cell) = R.cell,
		nameof(R.air_supply) = R.air_supply)
	for(var/slot in pieces)
		var/obj/item/piece = pieces[slot]
		if(!istype(piece))
			continue
		// Orderly teardown: clear the back-ref so the piece's dropped() self-detach
		// safety net stays inert while we deliberately drop and delete it.
		if(istype(piece, /obj/item/clothing))
			var/obj/item/clothing/deployed = piece
			rel_clear(deployed, nameof(deployed.master_rig))
		var/mob/living/M = piece.loc
		if(istype(M))
			M.drop_from_inventory(piece)
		rel_clear(R, slot)

	rel_clear(R, nameof(R.installed_modules))

/*
 * proc/get_equippable_pieces()
 *
 * Returns a flat list of the four deployable pieces: gloves, helmet, boots,
 * chest.  Nulls are filtered.  Used by propagate_stats() and any code that
 * needs to iterate over pieces without touching cell or air_supply.
 */
/datum/rig_component_registry/proc/get_equippable_pieces()
	var/list/pieces = list()
	if(holder().gloves)
		pieces += holder().gloves
	if(holder().helmet)
		pieces += holder().helmet
	if(holder().boots)
		pieces += holder().boots
	if(holder().chest)
		pieces += holder().chest
	return pieces

/*
 * proc/get_all_pieces()
 *
 * Returns all six physical pieces (including cell and air_supply).
 * Nulls are filtered.  Used by Destroy() and Moved() grab-back logic.
 */
/datum/rig_component_registry/proc/get_all_pieces()
	var/list/pieces = list()
	if(holder().gloves)    pieces += holder().gloves
	if(holder().boots)     pieces += holder().boots
	if(holder().helmet)    pieces += holder().helmet
	if(holder().chest)     pieces += holder().chest
	if(holder().cell)      pieces += holder().cell
	if(holder().air_supply) pieces += holder().air_supply
	return pieces

/// the holder this refers to (a relation view: null once it is deleted).
/datum/rig_component_registry/proc/holder() as /obj/item/rig
	return holder
