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
	var/obj/item/rig/holder

/datum/rig_component_registry/New(obj/item/rig/new_holder)
	holder = new_holder

/datum/rig_component_registry/Destroy()
	holder = null
	return ..()

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
	if(holder.initial_modules && holder.initial_modules.len)
		for(var/path in holder.initial_modules)
			var/obj/item/rig_module/module = new path(holder)
			holder.installed_modules += module
			module.installed(holder)

	// Spawn the six physical components
	if(holder.cell_type)
		holder.cell = new holder.cell_type(holder)
	if(holder.air_type)
		holder.air_supply = new holder.air_type(holder)
	if(holder.glove_type)
		holder.gloves = new holder.glove_type(holder)
		holder.verbs |= /obj/item/rig/proc/toggle_gauntlets
	if(holder.helm_type)
		holder.helmet = new holder.helm_type(holder)
		holder.verbs |= /obj/item/rig/proc/toggle_helmet
	if(holder.boot_type)
		holder.boots = new holder.boot_type(holder)
		holder.verbs |= /obj/item/rig/proc/toggle_boots
	if(holder.chest_type)
		holder.chest = new holder.chest_type(holder)
		if(holder.allowed)
			holder.chest.allowed = holder.allowed
		holder.verbs |= /obj/item/rig/proc/toggle_chest

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
		piece.name = "[holder.suit_type] [initial(piece.name)]"
		piece.desc = "It seems to be part of a [holder.name]."
		piece.icon_state = "[holder.suit_state]"
		piece.min_cold_protection_temperature = holder.min_cold_protection_temperature
		piece.max_heat_protection_temperature = holder.max_heat_protection_temperature
		// Preserve insulated gloves that already have a lower coefficient
		if(piece.siemens_coefficient > holder.siemens_coefficient)
			piece.siemens_coefficient = holder.siemens_coefficient
		piece.permeability_coefficient = holder.permeability_coefficient
		piece.unacidable = holder.unacidable
		if(islist(holder.armor))
			piece.armor = holder.armor.Copy()

/*
 * proc/destroy_pieces()
 *
 * Drops and qdels all six physical pieces, nulling their vars on the holder.
 * Called from /obj/item/rig/Destroy().
 */
/datum/rig_component_registry/proc/destroy_pieces()
	for(var/obj/item/piece in list(
			holder.gloves,
			holder.boots,
			holder.helmet,
			holder.chest,
			holder.cell,
			holder.air_supply))
		if(!istype(piece))
			continue
		var/mob/living/M = piece.loc
		if(istype(M))
			M.drop_from_inventory(piece)
		qdel(piece)

	holder.gloves    = null
	holder.boots     = null
	holder.helmet    = null
	holder.chest     = null
	holder.cell      = null
	holder.air_supply = null

	for(var/obj/item/rig_module/module in holder.installed_modules)
		qdel(module)
	// installed_modules list is a var on holder; leave nulling to rig/Destroy()

/*
 * proc/get_equippable_pieces()
 *
 * Returns a flat list of the four deployable pieces: gloves, helmet, boots,
 * chest.  Nulls are filtered.  Used by propagate_stats() and any code that
 * needs to iterate over pieces without touching cell or air_supply.
 */
/datum/rig_component_registry/proc/get_equippable_pieces()
	var/list/pieces = list()
	if(holder.gloves)
		pieces += holder.gloves
	if(holder.helmet)
		pieces += holder.helmet
	if(holder.boots)
		pieces += holder.boots
	if(holder.chest)
		pieces += holder.chest
	return pieces

/*
 * proc/get_all_pieces()
 *
 * Returns all six physical pieces (including cell and air_supply).
 * Nulls are filtered.  Used by Destroy() and Moved() grab-back logic.
 */
/datum/rig_component_registry/proc/get_all_pieces()
	var/list/pieces = list()
	if(holder.gloves)    pieces += holder.gloves
	if(holder.boots)     pieces += holder.boots
	if(holder.helmet)    pieces += holder.helmet
	if(holder.chest)     pieces += holder.chest
	if(holder.cell)      pieces += holder.cell
	if(holder.air_supply) pieces += holder.air_supply
	return pieces
