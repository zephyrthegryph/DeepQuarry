// Material synergy framework.
//
// Declarative templates that check property-vector and trait conditions
// across a machine's component_parts and apply effects when matched.
// Each /datum/material_synergy lists its requirements and an apply()
// proc; GLOB.dq_material_synergies holds one instance of each subtype.
//
// Machines invoke dq_apply_material_synergies(machine) at the end of
// their RefreshParts(); the framework walks the registry, finds the
// matching templates, and calls apply() on each. Effects are written
// into machine.dq_synergy_effects (a string→number map) so machine
// code can read them without knowing about specific synergies.

GLOBAL_LIST_EMPTY(dq_material_synergies)


/datum/controller/subsystem/quarry/Initialize()
	. = ..()
	for(var/T in subtypesof(/datum/material_synergy))
		GLOB.dq_material_synergies += new T()


// --- Synergy datum ----------------------------------------------------------

/datum/material_synergy
	/// Display name surfaced when the synergy fires.
	var/name = "Synergy"
	/// One-line description.
	var/description = ""
	/// List of /datum/material_synergy_req children. ALL must be met
	/// for the synergy to trigger.
	var/list/requirements


/datum/material_synergy/proc/met_by(obj/machinery/M)
	if(!requirements)
		return FALSE
	for(var/datum/material_synergy_req/R as anything in requirements)
		if(!R.matched_by(M))
			return FALSE
	return TRUE


/datum/material_synergy/proc/apply(obj/machinery/M)
	return


// --- Requirement primitives -------------------------------------------------

/datum/material_synergy_req
	var/part_type = /obj/item/stock_parts

/datum/material_synergy_req/proc/matched_by(obj/machinery/M)
	return FALSE


/// "There exists a part of `part_type` whose material's `property_var`
/// is at least `min_value`."
/datum/material_synergy_req/property
	var/property_var
	var/min_value = 0

/datum/material_synergy_req/property/matched_by(obj/machinery/M)
	if(!M?.component_parts)
		return FALSE
	for(var/obj/item/stock_parts/P in M.component_parts)
		if(!istype(P, part_type))
			continue
		var/datum/material/mat = P.dq_get_material()
		if(!mat)
			continue
		if(_dq_material_stat(mat, property_var) >= min_value)
			return TRUE
	return FALSE


/// Resolve a stat magnitude on a material, supporting both direct
/// /datum/material vars (the 11 core stats) and component-driven
/// magnitudes (luminescence / radioactivity / toxicity).
/proc/_dq_material_stat(datum/material/M, stat_name)
	if(!M)
		return 0
	switch(stat_name)
		if("luminescence")
			return dq_material_luminescence(M)
		if("radioactivity")
			return dq_material_radioactivity(M)
		if("toxicity")
			return dq_material_toxicity(M)
	return M.vars[stat_name]


/// "There exists a part of `part_type` whose material carries `trait_type`."
/datum/material_synergy_req/trait
	var/trait_type

/datum/material_synergy_req/trait/matched_by(obj/machinery/M)
	if(!M?.component_parts)
		return FALSE
	for(var/obj/item/stock_parts/P in M.component_parts)
		if(!istype(P, part_type))
			continue
		var/datum/material/mat = P.dq_get_material()
		if(!mat)
			continue
		if(dq_material_has_trait(mat, trait_type))
			return TRUE
	return FALSE


/// "Every part has a material whose material_class equals `target_class`."
/// The previous version mutated `target_class` on the requirement instance,
/// but GLOB.dq_material_synergies holds one shared instance reused across
/// every machine — so the second machine inherited the first machine's
/// class and rejected legitimate matches. The class is now computed
/// locally per call.
/datum/material_synergy_req/all_same_class

/datum/material_synergy_req/all_same_class/matched_by(obj/machinery/M)
	if(!M?.component_parts)
		return FALSE
	var/seen_class = null
	for(var/obj/item/stock_parts/P in M.component_parts)
		var/datum/material/mat = P.dq_get_material()
		if(!mat)
			return FALSE
		if(isnull(seen_class))
			seen_class = mat.material_class
		else if(mat.material_class != seen_class)
			return FALSE
	return seen_class != null


// --- Application hook -------------------------------------------------------

/obj/machinery
	/// Map of synergy-effect-name → numeric modifier. Populated by
	/// /datum/material_synergy/apply at RefreshParts time. Machine code
	/// reads this when computing power use, range, damage, etc.
	var/list/dq_synergy_effects


/proc/dq_apply_material_synergies(obj/machinery/M)
	if(!M)
		return
	M.dq_synergy_effects = list()
	for(var/datum/material_synergy/S as anything in GLOB.dq_material_synergies)
		if(S.met_by(M))
			S.apply(M)


/// Read a single synergy-effect modifier from a machine. Returns the
/// default if the key isn't set (i.e. no synergy fired for this effect).
/// Used at call sites that integrate effects into machine behavior
/// (e.g. use_power_oneoff multiplies by dq_synergy_value(M, "power_use_mod", 1)).
/proc/dq_synergy_value(obj/machinery/M, key, default = 1)
	if(!M?.dq_synergy_effects)
		return default
	var/val = M.dq_synergy_effects[key]
	if(isnull(val))
		return default
	return val


// --- Starter templates ------------------------------------------------------

/datum/material_synergy/resonance_cascade
	name = "Resonance Cascade"
	description = "A high-conductivity capacitor pairs with a Reactive scanning module, amplifying sensor range."

/datum/material_synergy/resonance_cascade/New()
	. = ..()
	requirements = list(
		new /datum/material_synergy_req/property(/obj/item/stock_parts/capacitor, "conductivity", 70),
		new /datum/material_synergy_req/trait(/obj/item/stock_parts/scanning_module, /datum/component/material_trait/reactive),
	)

/datum/material_synergy/resonance_cascade/apply(obj/machinery/M)
	M.dq_synergy_effects["range_mod"] = 2.0


/datum/material_synergy/catalytic_imprint
	name = "Catalytic Imprint"
	description = "A Reactive-trait matter bin and a high-reactivity micro-laser produce extra reagent yields."

/datum/material_synergy/catalytic_imprint/New()
	. = ..()
	requirements = list(
		new /datum/material_synergy_req/trait(/obj/item/stock_parts/matter_bin, /datum/component/material_trait/reactive),
		new /datum/material_synergy_req/property(/obj/item/stock_parts/micro_laser, "reactivity", 60),
	)

/datum/material_synergy/catalytic_imprint/apply(obj/machinery/M)
	M.dq_synergy_effects["reagent_yield_mod"] = 1.5


/datum/material_synergy/stable_lattice
	name = "Stable Lattice"
	description = "Every component carries the Stable trait — the machine never wears out."

/datum/material_synergy/stable_lattice/New()
	. = ..()
	requirements = list(
		new /datum/material_synergy_req/trait(/obj/item/stock_parts/capacitor, /datum/component/material_trait/stable),
		new /datum/material_synergy_req/trait(/obj/item/stock_parts/scanning_module, /datum/component/material_trait/stable),
		new /datum/material_synergy_req/trait(/obj/item/stock_parts/manipulator, /datum/component/material_trait/stable),
	)

/datum/material_synergy/stable_lattice/apply(obj/machinery/M)
	M.dq_synergy_effects["wear_immunity"] = 1


/datum/material_synergy/cold_forge
	name = "Cold Forge"
	description = "Insulated capacitor + manipulator cut power consumption."

/datum/material_synergy/cold_forge/New()
	. = ..()
	requirements = list(
		new /datum/material_synergy_req/property(/obj/item/stock_parts/capacitor, "thermal_insulation", 50),
		new /datum/material_synergy_req/property(/obj/item/stock_parts/manipulator, "thermal_insulation", 50),
	)

/datum/material_synergy/cold_forge/apply(obj/machinery/M)
	M.dq_synergy_effects["power_use_mod"] = 0.5


/datum/material_synergy/symphony
	name = "Symphony of Materials"
	description = "Every component is built from the same material class — a small uniform-tuning bonus across the board."

/datum/material_synergy/symphony/New()
	. = ..()
	requirements = list(
		new /datum/material_synergy_req/all_same_class(),
	)

/datum/material_synergy/symphony/apply(obj/machinery/M)
	M.dq_synergy_effects["uniform_bonus"] = 1.2


/datum/material_synergy/quantum_coupling
	name = "Quantum Coupling"
	description = "Luminescent laser and magnetic scanner cohere — sensor sharpness is enhanced."

/datum/material_synergy/quantum_coupling/New()
	. = ..()
	requirements = list(
		new /datum/material_synergy_req/property(/obj/item/stock_parts/micro_laser, "luminescence", 50),
		new /datum/material_synergy_req/property(/obj/item/stock_parts/scanning_module, "magnetism", 50),
	)

/datum/material_synergy/quantum_coupling/apply(obj/machinery/M)
	M.dq_synergy_effects["sensor_sharpness"] = 2.0
