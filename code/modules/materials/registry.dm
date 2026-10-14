/*
	MATERIAL DATUMS
	This data is used by various parts of the game for basic physical properties and behaviors
	of the metals/materials used for constructing many objects. Each var is commented and should be pretty
	self-explanatory but the various object types may have their own documentation. ~Z

	PATHS THAT USE DATUMS
		turf/simulated/wall
		obj/item/material
		obj/structure/barricade
		obj/item/stack/material
		obj/structure/table

	VALID ICONS
		WALLS
			stone
			metal
			solid
			resin
			ONLY WALLS
				cult
				hull
				curvy
				jaggy
				brick
				REINFORCEMENT
					reinf_over
					reinf_mesh
					reinf_cult
					reinf_metal
		DOORS
			stone
			metal
			resin
			wood
*/

// Assoc list containing all material datums indexed by name.
GLOBAL_LIST_INIT(name_to_material, populate_material_list())

//Returns the material the object is made of, if applicable.
//Will we ever need to return more than one value here? Or should we just return the "dominant" material.
/obj/proc/get_material()
	return null

//mostly for convenience
/obj/proc/get_material_name()
	var/datum/material/material = get_material()
	if(material)
		return material.name


/**
 * Returns the material composition of the atom.
 *
 * Used when recycling items, specifically to turn alloys back into their component mats.
 *
 * Exists because I'd need to add a way to un-alloy alloys or otherwise deal
 * with people converting the entire stations material supply into alloys.
 *
 * Arguments:
 * - breakdown_flags: A set of flags determining how exactly the materials are broken down. (unused)
 */
/obj/item/proc/get_material_composition(breakdown_flags=NONE)
	. = list()
	var/list/item_matter = material_totals()
	for(var/mat in item_matter)
		var/datum/material/M = GET_MATERIAL_REF(mat)
		if(M.composite_material && M.composite_material.len)
			for(var/submat in M.composite_material)
				var/datum/material/SM = GET_MATERIAL_REF(submat)
				if(SM in .)
					.[SM] += item_matter[mat]*(M.composite_material[submat]/SHEET_MATERIAL_AMOUNT)
				else
					.[SM] = item_matter[mat]*(M.composite_material[submat]/SHEET_MATERIAL_AMOUNT)
		else
			if(M in .)
				.[M] += item_matter[mat]
			else
				.[M] = item_matter[mat]

/obj/item/proc/set_custom_materials(list/materials, multiplier = 1)
	SHOULD_NOT_OVERRIDE(TRUE)

	if(!LAZYLEN(materials))
		set_material_mix(null)
		return

	materials = materials.Copy()

	if(multiplier != 1)
		for(var/x in materials)
			materials[x] *= multiplier

	set_material_mix(materials)


// Builds the datum list above.
/proc/populate_material_list()
	var/list/materia_list = list()
	for(var/type in subtypesof(/datum/material))
		var/datum/material/new_mineral = new type
		if(!new_mineral.name)
			continue
		materia_list[lowertext(new_mineral.name)] = new_mineral
	return materia_list

// Safety proc to make sure the material list exists before trying to grab from it.
/proc/get_material_by_name(name) as /datum/material
	READS_FROM()
	return GLOB.name_to_material[name]

/proc/material_display_name(name)
	if(istype(name, /datum/material)) //We were fed a datum.
		var/datum/material/M = name
		return M.display_name
	var/datum/material/material = get_material_by_name(name) //If not a datum, we were fed a name.
	if(material)
		return material.display_name
	return null

/** Fetches a cached material singleton when passed sufficient arguments.
 *
 * Arguments:
 * - [arguments][/list]: The list of arguments used to fetch the material ref.
 *   - The first element is a material datum, text string, or material type.
 *     - [Material datums][/datum/material] are assumed to be references to the cached datum and are returned
 *     - Text is assumed to be the text ID of a material and the corresponding material is fetched from the cache
 *     - A material type is checked for bespokeness:
 *       - If the material type is not bespoke the type is assumed to be the id for a material and the corresponding material is loaded from the cache.
 *       - If the material type is bespoke a text ID is generated from the arguments list and used to load a material datum from the cache.
 *   - The following elements are used to generate bespoke IDs
 */
/proc/_GetMaterialRef(list/arguments)
	var/datum/material/key = arguments[1]
	if(istype(key))
		return key // we want to convert anything we're given to a material

	if(istext(key))	// text ID
		. = GLOB.name_to_material[key]
		if(!.)
			WARNING("Attempted to fetch material ref with invalid text id '[key]'")
		return

	if(!ispath(key, /datum/material))
		CRASH("Attempted to fetch material ref with invalid key [key]")
	// Runtime-minted material bases (substances, processed alloys) deliberately have
	// no static registry identity. Generic subtype audits may encounter the abstract
	// path; it is not a missing material and must not be encoded into a bogus key.
	if(!initial(key.name))
		return null

	key = GetIdFromArguments(arguments)
	. = GLOB.name_to_material[key]
	if(!.)
		WARNING("Attempted to fetch nonexistent material with key [key]")

/** I'm not going to lie, this was swiped from the old DCS subsystem.
 * Credit does to ninjanomnom
 *
 * Generates an id for bespoke ~~elements~~ materials when given the argument list
 * Generating the id here is a bit complex because we need to support named arguments
 * Named arguments can appear in any order and we need them to appear after ordered arguments
 * We assume that no one will pass in a named argument with a value of null
 **/
/proc/GetIdFromArguments(list/arguments)
	var/datum/material/mattype = arguments[1]
	var/list/fullid = list("[initial(mattype.name) || mattype]")
	var/list/named_arguments = list()
	for(var/i in 2 to length(arguments))
		var/key = arguments[i]
		var/value
		if(istext(key))
			value = arguments[key]
		if(!(istext(key) || isnum(key)))
			key = REF(key)
		key = "[key]" // Key is stringified so numbers dont break things
		if(!isnull(value))
			if(!(istext(value) || isnum(value)))
				value = REF(value)
			named_arguments["[key]"] = value
		else
			fullid += "[key]"

	if(length(named_arguments))
		named_arguments = sortList(named_arguments)
		fullid += named_arguments
	return replacetext(list2params(fullid), "+", " ")


