// Material traits — component-attached qualitative tags.
//
// Unlike the eleven numeric stat vars and the three behavior components
// (luminescent/radioactive/toxic), traits are presence-only flags. A
// material either has the Resonant trait or it doesn't; there is no
// "30% Resonant." This makes them easy to use as preconditions in
// synergy templates: "If any laser part's material has Resonant AND
// any bin part has Reactive, apply X."
//
// Traits are rolled on dynamic materials at creation time. Static
// materials can attach them in their New() proc if a particular
// upstream material conceptually should have one (e.g. phoron is
// inherently Reactive).
//
// All traits inherit from /datum/component/material_trait, which sits
// under the same dupe_mode = COMPONENT_DUPE_UNIQUE umbrella as the
// behavior components. A material may hold multiple traits (one of
// each subtype).

/datum/component/material_trait
	/// Display name shown in the analyzer.
	var/trait_name = "Unnamed Trait"
	/// One-line description for the analyzer UI.
	var/trait_description = ""
	/// TRUE if this trait is a downside.
	var/debuff = FALSE
	dupe_mode = COMPONENT_DUPE_UNIQUE


// --- Concrete traits --------------------------------------------------------

/datum/component/material_trait/resonant
	trait_name = "Resonant"
	trait_description = "Carrier waves in this material's lattice amplify electromagnetic effects in adjacent components."

/datum/component/material_trait/reactive
	trait_name = "Reactive"
	trait_description = "Catalyses chemical reactions in materials it contacts; reagent yields are amplified."

/datum/component/material_trait/stable
	trait_name = "Stable"
	trait_description = "Resists fatigue and stress; parts made from this material outlast their rated lifetime."

/datum/component/material_trait/fragile
	trait_name = "Fragile"
	trait_description = "Internal stress fractures accumulate under load; parts have a low chance to fail on heavy use."
	debuff = TRUE

/datum/component/material_trait/living
	trait_name = "Living"
	trait_description = "Cellular regeneration: parts slowly heal their damage over time, given ambient reagents."

/datum/component/material_trait/sympathetic
	trait_name = "Sympathetic"
	trait_description = "Self-tuning lattice — machines using multiple parts of materials sharing this material's class gain a bonus."


// --- Roll API ---------------------------------------------------------------

/// Per-class weight tables for trait selection. Higher weights are
/// more likely to roll. Class-specific so each material class has a
/// distinct trait flavor.
/proc/_dq_trait_pool_for_class(material_class)
	var/static/list/pools = list(
		MATCLASS_METAL = list(
			/datum/component/material_trait/resonant    = 25,
			/datum/component/material_trait/stable      = 25,
			/datum/component/material_trait/sympathetic = 20,
			/datum/component/material_trait/fragile     = 5,
		),
		MATCLASS_CRYSTAL = list(
			/datum/component/material_trait/resonant    = 25,
			/datum/component/material_trait/reactive    = 15,
			/datum/component/material_trait/stable      = 20,
			/datum/component/material_trait/fragile     = 30,
		),
		MATCLASS_ORGANIC = list(
			/datum/component/material_trait/reactive    = 30,
			/datum/component/material_trait/living      = 30,
			/datum/component/material_trait/sympathetic = 15,
			/datum/component/material_trait/fragile     = 10,
		),
		MATCLASS_CERAMIC = list(
			/datum/component/material_trait/stable      = 30,
			/datum/component/material_trait/resonant    = 10,
			/datum/component/material_trait/sympathetic = 20,
			/datum/component/material_trait/fragile     = 25,
		),
	)
	return pools[material_class]


/// Roll 0-2 traits onto a material. Each material has a 35% base
/// chance to roll any traits at all; given a roll, picks weighted from
/// the class's pool. Up to 2 distinct traits.
/proc/dq_roll_material_traits(datum/material/M)
	if(!M)
		return
	if(!prob(35))
		return
	var/list/pool = _dq_trait_pool_for_class(M.material_class)
	if(!pool || !length(pool))
		return
	pool = pool.Copy()
	var/want = prob(20) ? 2 : 1
	var/picked = 0
	while(picked < want && length(pool))
		var/chosen = pickweight(pool)
		pool -= chosen
		M.AddComponent(chosen)
		picked++


/// Convenience: TRUE if material carries a trait of the given type.
/proc/dq_material_has_trait(datum/material/M, trait_typepath)
	if(!M)
		return FALSE
	return M.GetComponent(trait_typepath) != null


/// Returns a list of /datum/component/material_trait instances attached
/// to a material (or null if none). Used by the analyzer UI.
/proc/dq_material_traits(datum/material/M)
	if(!M)
		return null
	return M.GetComponents(/datum/component/material_trait)
