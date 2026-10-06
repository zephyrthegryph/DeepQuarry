/***************************************************************
** Design Datums   **
** All the data for building stuff.   **
***************************************************************/
/*
For the materials datum, it assumes you need reagents unless specified otherwise. To designate a material that isn't a reagent,
you use one of the material IDs below. These are NOT ids in the usual sense (they aren't defined in the object or part of a datum),
they are simply references used as part of a "has materials?" type proc. They all start with a $ to denote that they aren't reagents.
The currently supporting non-reagent materials. All material amounts are set as the define SHEET_MATERIAL_AMOUNT, which defaults to 100

Don't add new keyword/IDs if they are made from an existing one (such as rods which are made from iron). Only add raw materials.

Design Guidelines
- When adding new designs, check rdreadme.dm to see what kind of things have already been made and where new stuff is needed.
- A single sheet of anything is 100 units of material. Materials besides iron/glass require help from other jobs (mining for
other types of metals and chemistry for reagents).
- Add the AUTOLATHE tag to
*/

//DESIGNS ARE GLOBAL. DO NOT CREATE OR DESTROY THEM AT RUNTIME OUTSIDE OF INIT, JUST REFERENCE THEM TO WHATEVER YOU'RE DOING! //why are you yelling?
//DO NOT REFERENCE OUTSIDE OF SSRESEARCH. USE THE PROCS IN SSRESEARCH TO OBTAIN A REFERENCE.

/datum/design_techweb //Datum for object designs, used in construction
	/// Name of the created object
	var/name = "Name"
	/// Description of the created object
	var/desc = null
	/// The ID of the design. Used for quick reference. Alphanumeric, lower-case, no symbols
	var/id = DESIGN_ID_IGNORE
	/// Bitflags indicating what machines this design is compatable with. ([IMPRINTER]|[AWAY_IMPRINTER]|[PROTOLATHE]|[AWAY_LATHE]|[AUTOLATHE]|[MECHFAB]|[BIOGENERATOR]|[LIMBGROWER]|[SMELTER])
	var/build_type = null
	/// List of materials required to create one unit of the product. Format is (typepath or caregory) -> amount
	var/list/materials = list() // ALLOW(instance_list): the design's material cost table: always filled with its materials, so a lazy list saves nothing
	/// Optional application bridge for ordinary items that do not implement set_material.
	var/material_application = null
	/// Blueprint (a /datum/material_template path) for this design's configurable
	/// parts. When omitted, it comes from the product type's declared template or
	/// from the design's application profile.
	var/material_template
	/// Material units the blueprint splits between its parts.
	var/material_total = 0
	/// Original canonical material costs retained for coverage tests, UI
	/// comparison, and exact standard-configuration accounting.
	var/list/standard_material_costs
	/// Total physical feedstock used by the original recipe. Family blueprints
	/// must conserve this even when they replace abstract ingredients.
	var/original_material_total = 0
	/// The amount of time required to create one unit of the product.
	var/construction_time = 3.2 SECONDS
	/// The typepath of the object produced by this design
	var/build_path = null
	/// Reagent produced by this design. Currently only supported by the biogenerator.
	var/make_reagent
	/// What categories this design falls under. Used for sorting in production machines.
	var/list/category = list() // ALLOW(instance_list): d: every design is in a category (singletons)
	/// List of reagents required to create one unit of the product. Currently only supported by the limb grower.
	var/list/reagents_list // Lazy
	/// How many times faster than normal is this to build on the protolathe
	var/lathe_time_factor = 1
	/// Bitflags indicating what departmental lathes should be allowed to process this design.
	var/departmental_flags = ALL
	/// What techwebs nodes unlock this design. Constructed by SSresearch
	var/list/unlocked_by // Lazy list of node ids; built by SSresearch
	/// Override for the automatic icon generation used for the research console.
	var/research_icon
	/// Override for the automatic icon state generation used for the research console.
	var/research_icon_state

/datum/design_techweb/error_design
	name = "ERROR"
	desc = "This usually means something in the database has corrupted. If this doesn't go away automatically, inform Central Command so their techs can fix this ASAP(tm)"

/datum/design_techweb/New()
	. = ..()

// Designs are immutable global datums registered at startup via SSresearch.
// Destroying one at runtime would corrupt every techweb that holds a reference to its ID,
// so qdel() refuses (the error_design base instance may still be deleted).
/datum/design_techweb/lifecycle_keep(force)
	if(id == DESIGN_ID_IGNORE)
		return FALSE
	stack_trace("Attempted to destroy techweb design '[id]' ([type]) at runtime; designs are immutable global datums")
	return TRUE

/datum/design_techweb/lifecycle_dematerialize()
	SSresearch.techweb_designs -= id
	..()

/datum/design_techweb/proc/InitializeMaterials()
	var/list/temp_list = list()
	for(var/i in materials) //Go through all of our materials, get the subsystem instance, and then replace the list.
		var/amount = materials[i]
		if(!istext(i)) //Not a category, so get the ref the normal way
			var/datum/material/M = GET_MATERIAL_REF(i)
			temp_list[M] = amount
		else
			temp_list[i] = amount
	materials = temp_list
	initialize_material_slots_from_costs()

/proc/material_application_for_product(build_path, explicit_application = null)
	if(ispath(build_path, /obj/item/material/knife) || ispath(build_path, /obj/item/material/kitchen/utensil) || ispath(build_path, /obj/item/stock_parts/spring) || ispath(build_path, /obj/item/stock_parts/gear) || ispath(build_path, /obj/item/stock_parts/console_screen))
		return MATERIAL_APPLICATION_MONOLITHIC
	if(ispath(build_path, /obj/item/cell))
		return MATERIAL_APPLICATION_CELL
	if(ispath(build_path, /obj/item/stock_parts/capacitor))
		return MATERIAL_APPLICATION_CAPACITOR
	if(ispath(build_path, /obj/item/stock_parts/manipulator))
		return MATERIAL_APPLICATION_MANIPULATOR
	if(ispath(build_path, /obj/item/stock_parts/matter_bin))
		return MATERIAL_APPLICATION_MATTER_BIN
	if(ispath(build_path, /obj/item/stock_parts/scanning_module))
		return MATERIAL_APPLICATION_SCANNER
	if(ispath(build_path, /obj/item/stock_parts/micro_laser))
		return MATERIAL_APPLICATION_LASER
	if(ispath(build_path, /obj/item/stock_parts))
		return MATERIAL_APPLICATION_MECHANICAL
	if(ispath(build_path, /obj/item/circuitboard))
		return MATERIAL_APPLICATION_CIRCUIT_BOARD
	if(ispath(build_path, /obj/item/multitool))
		return MATERIAL_APPLICATION_ELECTRONICS
	if(ispath(build_path, /obj/item/analyzer) || ispath(build_path, /obj/item/healthanalyzer) || ispath(build_path, /obj/item/t_scanner) || ispath(build_path, /obj/item/gps) || ispath(build_path, /obj/item/radio) || ispath(build_path, /obj/item/pda) || ispath(build_path, /obj/item/reagent_scanner) || ispath(build_path, /obj/item/slime_scanner) || ispath(build_path, /obj/item/robotanalyzer) || ispath(build_path, /obj/item/motiontracker) || ispath(build_path, /obj/item/flashlight))
		return MATERIAL_APPLICATION_ELECTRONICS
	if(ispath(build_path, /obj/item/ammo_casing))
		return MATERIAL_APPLICATION_PROJECTILE
	if(ispath(build_path, /obj/item/ammo_magazine))
		return MATERIAL_APPLICATION_MAGAZINE
	if(ispath(build_path, /obj/item/gun/energy) || ispath(build_path, /obj/item/gun/magnetic))
		return MATERIAL_APPLICATION_ENERGY_DEVICE
	if(ispath(build_path, /obj/item/gun))
		return MATERIAL_APPLICATION_FIREARM
	if(ispath(build_path, /obj/item/surgical/bonegel))
		return null
	if(ispath(build_path, /obj/item/surgical))
		return MATERIAL_APPLICATION_SURGICAL
	if(ispath(build_path, /obj/item/tool))
		return MATERIAL_APPLICATION_TOOL
	if(ispath(build_path, /obj/item/material/armor_plating) || ispath(build_path, /obj/item/rig))
		return MATERIAL_APPLICATION_ARMOR
	if(ispath(build_path, /obj/item/clothing) || ispath(build_path, /obj/item/storage/backpack) || ispath(build_path, /obj/item/storage/belt) || ispath(build_path, /obj/item/storage/pouch))
		return MATERIAL_APPLICATION_SOFT_GOODS
	if(ispath(build_path, /obj/item/tank) || ispath(build_path, /obj/item/pipe))
		return MATERIAL_APPLICATION_PRESSURE
	if(ispath(build_path, /obj/item/reagent_containers))
		return MATERIAL_APPLICATION_CONTAINER
	if(ispath(build_path, /obj/item/stack/cable_coil))
		return MATERIAL_APPLICATION_CABLE
	if(ispath(build_path, /obj/item/light))
		return MATERIAL_APPLICATION_LIGHT
	if(ispath(build_path, /obj/item/robot_parts) || ispath(build_path, /obj/item/mecha_parts/part) || ispath(build_path, /obj/item/mecha_parts/component) || ispath(build_path, /obj/item/mecha_parts/chassis) || ispath(build_path, /obj/item/mecha_parts/fighter) || ispath(build_path, /obj/item/smes_coil))
		return MATERIAL_APPLICATION_MECHANICAL
	return explicit_application

/// The blueprint for a product: its type's own functional template when it declares
/// one (cells, tanks, special tools), else the application's generic template.
/proc/material_template_for_product(build_path, application)
	var/obj/product = build_path
	var/declared = ispath(build_path, /obj) ? initial(product.material_template) : null
	if(declared && !ispath(declared, /datum/material_template/bulk) && !ispath(declared, /datum/material_template/mix))
		return declared
	if(!application)
		return null
	var/datum/material_template/template = material_template_for_application(application)
	return template?.type

/datum/design_techweb/proc/inferred_material_application()
	return material_application_for_product(build_path, material_application)

/// Converts ordinary fixed material costs into configurable construction
/// parts. The total material quantity is preserved; role-appropriate defaults
/// make an immediately usable product. Non-material categories remain fixed.
/datum/design_techweb/proc/initialize_material_slots_from_costs()
	if(!ispath(build_path, /obj))
		return
	var/list/fixed_costs = list()
	var/list/material_cost_keys = list()
	for(var/key in materials)
		var/datum/material/material
		if(istype(key, /datum/material))
			material = key
		else if(istext(key))
			material = get_material_by_name(key)
		if(material)
			fixed_costs[material] = (fixed_costs[material] || 0) + materials[key]
			material_cost_keys += key
	if(!length(fixed_costs))
		return
	for(var/datum/material/material in fixed_costs)
		original_material_total += fixed_costs[material]
	var/application = inferred_material_application()
	if(!material_template)
		// A fixed recipe is preferable to fictional placeholder parts. Every
		// configurable family must have an explicit physical blueprint.
		if(!application)
			return
		var/total = 0
		for(var/datum/material/material in fixed_costs)
			total += fixed_costs[material]
		if(total < 1)
			return
		material_template = material_template_for_product(build_path, application)
		material_total = total
		if(!material_template)
			return
	// Recognized blueprints replace abstract resource costs with the same total
	// quantity distributed across real parts and sensible standard materials.
	// Their standard configuration is therefore defined by the blueprint, not
	// by arbitrary legacy resource ingredients.
	for(var/key in material_cost_keys)
		materials -= key
	material_application = application
	standard_material_costs = list()
	var/datum/material_template/template = material_template_singleton(material_template)
	var/list/defaults = template.resolve()
	var/list/amounts = template.role_amounts(material_total)
	for(var/role in defaults)
		var/default_material = defaults[role]
		standard_material_costs[default_material] = (standard_material_costs[default_material] || 0) + amounts[role]

/// Returns the description of the design
/datum/design_techweb/proc/get_description()
	var/obj/object_build_item_path = build_path

	return isnull(desc) ? initial(object_build_item_path.desc) : desc

/datum/design_techweb/proc/create_item(target, list/material_choices)
	// Material items (and material clothing) take a material key as their second
	// Initialize arg, so passing the chosen material makes the product be made of it.
	var/obj/product = new build_path(target)
	if(!material_template)
		return product
	if(!product.apply_material_construction(material_choices, material_template, material_total))
		spent(product)
		return null
	if(istype(product, /obj/item/material))
		var/obj/item/material/material_item = product
		var/datum/material/primary = product.primary_construction_material()
		if(primary)
			material_item.set_material(primary.name)
	return product

// Effective per-unit cost given the user's chosen construction materials.
/datum/design_techweb/proc/effective_materials(list/material_choices)
	if(!material_template)
		return materials
	var/list/out = materials.Copy()
	var/datum/material_template/template = material_template_singleton(material_template)
	var/list/resolved = template.resolve(material_choices)
	if(!resolved)
		return null
	var/list/amounts = template.role_amounts(material_total)
	for(var/role in resolved)
		var/datum/material/chosen = get_material_by_name(resolved[role])
		var/amount = amounts[role]
		if(chosen && amount > 0)
			out[chosen] = (out[chosen] || 0) + amount
	return out

// Is the chosen material a valid pick for this design (exists, and matches the class filter)?
/datum/design_techweb/proc/material_choice_valid(list/material_choices)
	if(!material_template)
		return TRUE
	var/datum/material_template/template = material_template_singleton(material_template)
	return !!template.resolve(material_choices)

// The techweb nodes that unlock this design: frozen definitions.

/// Designs are immutable round definitions in SSresearch.techweb_designs: shared.
REGISTRY_TYPE(/datum/design_techweb, GLOBAL_PROC_REF(registry_design_techweb))

/// The registered design D stands for (D itself when it is the table's entry for its id).
/proc/registry_design_techweb(datum/design_techweb/D)
	var/datum/design_techweb/entry = SSresearch?.techweb_designs[D.id]
	return entry == D ? D : null
