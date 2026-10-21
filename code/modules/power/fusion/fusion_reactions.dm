// Fusion reactions as transformations (doc/rewrite/proposals/transformations.md, wave 4): a reaction is a type under /transformation/fusion in MEDIUM_FIELD,
// REGIME_FUSION. `takes` names its two reactants (a reagent term each; the same reactant twice for a self-reaction), `makes` what it produces per reacting pair,
// and the numbers are energy_in (consumed), energy_out (produced), radiation, instability, min_level (the field energy it needs) and min_heat (the temperature
// it needs; the base says 100). The field's loop (code/modules/power/fusion/core/core_field.dm) picks pairs and amounts as it always did. A reaction with a
// special step overrides handle_reaction_special(field) on its type (called on the rule's owner instance); it returns true to abort the field's reaction.

/transformation/fusion

CAPABILITIES(/transformation/fusion)
	transformation(medium = MEDIUM_FIELD, regime = REGIME_FUSION, min_level = 1, min_heat = 100)

/// The special step of a reaction; true aborts the field's current reaction.
/transformation/fusion/proc/handle_reaction_special(obj/effect/fusion_em_field/holder)
	return 0

/// Reactant => reactant => rule, both ways round (the table is symmetric; a pair two rules name answers the later one). Built on first use.
GLOBAL_LIST(fusion_reactions)

/// The fusion rule for a pair of reactants in either order, or null.
/proc/get_fusion_reaction(p_react, s_react, m_energy)
	RETURN_TYPE(/datum/xform)
	if(!GLOB.fusion_reactions)
		var/list/table = list()
		for(var/datum/xform/rule as anything in xform_rules_in(MEDIUM_FIELD, REGIME_FUSION))
			if(!table[rule.reactant_a])
				table[rule.reactant_a] = list()
			table[rule.reactant_a][rule.reactant_b] = rule
			if(!table[rule.reactant_b])
				table[rule.reactant_b] = list()
			table[rule.reactant_b][rule.reactant_a] = rule
		GLOB.fusion_reactions = table

	if(GLOB.fusion_reactions.Find(p_react))
		var/list/secondary_reactions = GLOB.fusion_reactions[p_react]
		if(secondary_reactions.Find(s_react))
			return GLOB.fusion_reactions[p_react][s_react]

// Material fuels
//  deuterium
//  tritium
//  phoron
//  supermatter

// Virtual fuels
//  helium-3
//  lithium-6
//  boron-11

// Basic power production reactions.
/transformation/fusion/deuterium_deuterium
CAPABILITIES(/transformation/fusion/deuterium_deuterium)
	configure(transformation(takes = list(reagent(REAGENT_ID_DEUTERIUM, 1), reagent(REAGENT_ID_DEUTERIUM, 1)),
		energy_in = 1,
		energy_out = 2))
// Advanced production reactions (todo)

/transformation/fusion/deuterium_helium
CAPABILITIES(/transformation/fusion/deuterium_helium)
	configure(transformation(takes = list(reagent(REAGENT_ID_DEUTERIUM, 1), reagent(REAGENT_ID_HELIUM3, 1)),
		energy_in = 1,
		energy_out = 5))

/transformation/fusion/deuterium_tritium
CAPABILITIES(/transformation/fusion/deuterium_tritium)
	configure(transformation(takes = list(reagent(REAGENT_ID_DEUTERIUM, 1), reagent(REAGENT_ID_SLIMEJELLY, 1)),
		makes = list(reagent(REAGENT_ID_HELIUM3, 1)),
		energy_in = 1,
		energy_out = 1,
		instability = 0.5))

/transformation/fusion/deuterium_lithium
CAPABILITIES(/transformation/fusion/deuterium_lithium)
	configure(transformation(takes = list(reagent(REAGENT_ID_DEUTERIUM, 1), reagent(REAGENT_ID_LITHIUM, 1)),
		makes = list(reagent(REAGENT_ID_SLIMEJELLY, 1)),
		energy_in = 2,
		energy_out = 0,
		radiation = 3,
		instability = 1))

// Unideal/material production reactions
/transformation/fusion/oxygen_oxygen
CAPABILITIES(/transformation/fusion/oxygen_oxygen)
	configure(transformation(takes = list(reagent(REAGENT_ID_OXYGEN, 1), reagent(REAGENT_ID_OXYGEN, 1)),
		makes = list(reagent(REAGENT_ID_SILICON, 1)),
		energy_in = 10,
		energy_out = 0,
		radiation = 5,
		instability = 5))

// Not realistic but w/e
/transformation/fusion/iron_iron
CAPABILITIES(/transformation/fusion/iron_iron)
	configure(transformation(takes = list(reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_IRON, 1)),
		makes = list(reagent(REAGENT_ID_SILVER, 1), reagent(REAGENT_ID_GOLD, 1), reagent(REAGENT_ID_PLATINUM, 1)),
		energy_in = 10,
		energy_out = 0,
		instability = 2,
		min_heat = 10000))

/transformation/fusion/phoron_hydrogen
CAPABILITIES(/transformation/fusion/phoron_hydrogen)
	configure(transformation(takes = list(reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent("mydrogen", 1)),
		energy_in = 10,
		energy_out = 0,
		instability = 5,
		min_heat = 8000))

// VERY UNIDEAL REACTIONS.
/transformation/fusion/phoron_supermatter
CAPABILITIES(/transformation/fusion/phoron_supermatter)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUPERMATTER, 1), reagent(REAGENT_ID_PHORON, 1)),
		energy_in = 0,
		energy_out = 5,
		radiation = 20,
		instability = 20))

/transformation/fusion/phoron_supermatter/handle_reaction_special(obj/effect/fusion_em_field/holder)

	wormhole_event()

	var/turf/origin = get_turf(holder)
	holder.Rupture()
	radiation_pulse(
		holder,
		max_range = 50,
		threshold = RAD_HEAVY_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		strength = 500
	)

	for(var/mob/living/mob in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		var/turf/T = get_turf(mob)
		if(T && (holder.z == T.z))
			if(ishuman(mob))
				var/mob/living/carbon/human/H = mob
				H.status_adjust(STAT_HALLUCINATING, rand(100,150))

	for(var/obj/machinery/fusion_fuel_injector/I in range(world.view, origin))
		if(I.cur_assembly && I.cur_assembly.fuel_type == REAGENT_ID_SUPERMATTER)
			explosion(get_turf(I), 1, 2, 3)
			after(null, 0.5 SECONDS, GLOBAL_PROC_REF(destroyed), with = list(I))
	spent(holder)
	explosion(origin, 1, 2, 5)

	return 1

// High end reactions.
/transformation/fusion/boron_hydrogen
CAPABILITIES(/transformation/fusion/boron_hydrogen)
	configure(transformation(takes = list(reagent(REAGENT_ID_BORON11, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		energy_in = 3,
		energy_out = 15,
		radiation = 3,
		instability = 3,
		min_level = FUSION_HEAT_CAP * 0.5))

/transformation/fusion/hydrogen_hydrogen
CAPABILITIES(/transformation/fusion/hydrogen_hydrogen)
	configure(transformation(takes = list(reagent(REAGENT_ID_HYDROGEN, 1), reagent(REAGENT_ID_HYDROGEN, 1)),
		energy_in = 0,
		energy_out = 20,
		radiation = 5,
		instability = 5,
		min_level = FUSION_HEAT_CAP * 0.75))
