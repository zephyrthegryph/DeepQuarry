// The wiki's world source: one article per gas (atmos/gas/<id>), per material (material/<name>) and per plant (botany/plant/<name>), read from the
// gas types, the material registry and the seed registry. Nothing here is written out: every number is the type's own, so a changed gas,
// material or seed changes its page.

/proc/wiki_gas_id(gas_type)
	var/datum/gas/G = gas_type
	return "atmos/gas/[initial(G.id) || ckey(initial(G.name))]"

/proc/wiki_material_id(datum/material/M)
	return "material/[ckey(M.name)]"

/proc/wiki_plant_id(datum/seed/S)
	return "botany/plant/[ckey(S.name)]"

/proc/wiki_source_world(list/index)
	for(var/gas_type in subtypesof(/datum/gas))
		var/datum/gas/G = gas_type
		if(!initial(G.name))
			continue
		wiki_set_swatch(wiki_add(index, wiki_gas_id(gas_type), initial(G.name), "Engineering/Atmospherics/Gases", initial(G.dangerous) ? "Dangerous to breathe or handle." : null, null, GLOBAL_PROC_REF(wiki_gas_body), gas_type), initial(G.primary_color))
	for(var/name in GLOB.name_to_material)
		var/datum/material/M = GLOB.name_to_material[name]
		if(!M?.name || index[wiki_material_id(M)])
			continue
		var/list/article = wiki_add(index, wiki_material_id(M), capitalize(M.display_name || M.name), "Engineering/Materials/[M.stack_type ? "Sheets" : "Other materials"]", null, null, GLOBAL_PROC_REF(wiki_material_body), name)
		wiki_set_swatch(article, M.icon_colour)
		if(M.stack_type)
			wiki_set_sprite(article, M.stack_type)
	var/list/seeds = plants_seeds()
	for(var/name in seeds)
		var/datum/seed/S = seeds[name]
		if(!S?.name || S.type == /datum/seed || S.mysterious || (S.wiki_flag & WIKI_SPOILER) || index[wiki_plant_id(S)])
			continue
		wiki_add(index, wiki_plant_id(S), capitalize(S.display_name || S.seed_name || S.name), "Civilian/Botany/Plants", null, null, GLOBAL_PROC_REF(wiki_plant_body), name)

// ---- gases ----

/proc/wiki_gas_body(gas_type)
	var/datum/gas/G = gas_type
	var/list/blocks = list(wiki_p(initial(G.desc) || "A gas."))
	var/list/facts = list(list("Specific heat", "[initial(G.specific_heat)] J/(mol K)"))
	facts += list(list("Dangerous", initial(G.dangerous) ? "Yes" : "No"))
	if(initial(G.purchaseable))
		facts += list(list("Cargo", "Sold in canisters"))
	if(initial(G.base_value))
		facts += list(list("Sells for", "[initial(G.base_value)] per mole"))
	if(initial(G.fusion_power))
		facts += list(list("Fusion power", "[initial(G.fusion_power)]"))
	blocks += list(wiki_kv(facts))
	var/list/reactions = list()
	for(var/datum/xform/X as anything in xform_rules_in(MEDIUM_GAS, REGIME_GAS))
		if(!(gas_type in X.gas_takes))
			continue
		var/list/needs = list()
		for(var/other in X.gas_takes)
			var/datum/gas/O = other
			needs += "[X.gas_takes[other]] mol [initial(O.name)]"
		var/window = ""
		if(!isnull(X.min_temp) && !isnull(X.max_temp))
			window = " between [X.min_temp] K and [X.max_temp] K"
		else if(!isnull(X.min_temp))
			window = " above [X.min_temp] K"
		else if(!isnull(X.max_temp))
			window = " below [X.max_temp] K"
		reactions += "[capitalize(X.name || "A reaction")]: needs at least [english_list(needs)][window][X.expands_hotspot ? "; it spreads fire" : ""]."
	if(length(reactions))
		blocks += list(wiki_h("Reactions"), wiki_ul(reactions))
	blocks += list(wiki_note("See [wiki_ref("guide/engineering/atmos", "atmospherics basics")] for how gas moves and how to handle it."))
	return blocks

// ---- materials ----

/proc/wiki_material_body(name)
	var/datum/material/M = GLOB.name_to_material[name]
	var/list/blocks = list(wiki_p("[capitalize(M.display_name || M.name)]: a material the station builds with, read from its material card."))
	var/list/facts = list()
	facts += list(list("Strength", "[M.strength]"), list("Toughness", "[M.toughness]"), list("Melting point", "[round(M.melting_point())] K"))
	facts += list(list("Conducts", M.conductive() ? "Yes ([M.conductivity])" : "No"), list("Corrosion resistance", "[M.corrosion_resistance]"), list("Weight", "[M.weight] per sheet"))
	if(M.radiation_resistance)
		facts += list(list("Radiation resistance", "[M.radiation_resistance]"))
	if(M.opacity < 1)
		facts += list(list("See-through", "Yes"))
	if(M.supply_conversion_value)
		facts += list(list("Sells for", "[M.supply_conversion_value] per sheet"))
	if(M.is_fusion_fuel)
		facts += list(list("Fusion fuel", "Yes"))
	blocks += list(wiki_kv(facts))
	if(length(M.traits))
		var/list/traits = list()
		for(var/id in M.traits)
			traits += "[capitalize("[id]")] ([M.traits[id]])"
		blocks += list(wiki_h("Traits"), wiki_ul(traits))
	if(length(M.composite_material))
		var/list/parts = list()
		for(var/part in M.composite_material)
			parts += "[M.composite_material[part]] [part]"
		blocks += list(wiki_h("Made of"), wiki_p("Each sheet holds [english_list(parts)]."))
	if(M.stack_type)
		var/stack_id = wiki_cat_id(M.stack_type)
		if(wiki_title(stack_id))
			blocks += list(wiki_links("Sheets", list(wiki_link(stack_id, wiki_title(stack_id), null, null, M.stack_type))))
		blocks += list(wiki_note("Use a stack of sheets in hand to see what it builds. The strength and toughness above set how much an object made of it takes before it breaks."))
	return blocks

// ---- plants ----

/proc/wiki_plant_body(name)
	var/datum/seed/S = plants_seeds()[name]
	var/list/blocks = list(wiki_p("[capitalize(S.display_name || S.name)]: a plant grown in a hydroponics tray from [S.seed_name || S.name] [S.seed_noun]."))
	var/list/facts = list()
	facts += list(list("Matures in", "[S.get_trait(TRAIT_MATURATION)] growth cycles"))
	facts += list(list("Yield", S.get_trait(TRAIT_YIELD) > 0 ? "[S.get_trait(TRAIT_YIELD)]" : "Nothing to harvest"))
	facts += list(list("Harvests", S.get_trait(TRAIT_HARVEST_REPEAT) ? "Again and again (every [S.get_trait(TRAIT_PRODUCTION)] cycles)" : "Once"))
	facts += list(list("Potency", "[S.get_trait(TRAIT_POTENCY)]"))
	facts += list(list("Ideal light", "[S.get_trait(TRAIT_IDEAL_LIGHT)] (tolerates [S.get_trait(TRAIT_LIGHT_TOLERANCE)] either way)"))
	facts += list(list("Ideal temperature", "[S.get_trait(TRAIT_IDEAL_HEAT)] K (tolerates [S.get_trait(TRAIT_HEAT_TOLERANCE)] either way)"))
	facts += list(list("Pressure", "[S.get_trait(TRAIT_LOWKPA_TOLERANCE)] to [S.get_trait(TRAIT_HIGHKPA_TOLERANCE)] kPa"))
	facts += list(list("Needs", english_list(list(S.get_trait(TRAIT_REQUIRES_WATER) ? "water" : null, S.get_trait(TRAIT_REQUIRES_NUTRIENTS) ? "nutrients" : null) - null, nothing_text = "Nothing")))
	blocks += list(wiki_kv(facts))
	var/list/traits = list()
	if(S.get_trait(TRAIT_SPREAD) == 1)
		traits += "Creeps beyond its tray."
	else if(S.get_trait(TRAIT_SPREAD) == 2)
		traits += "Grows as a vine and spreads."
	if(S.get_trait(TRAIT_CARNIVOROUS))
		traits += S.get_trait(TRAIT_CARNIVOROUS) == 2 ? "Carnivorous: it eats living things." : "Eats pests in its tray."
	if(S.get_trait(TRAIT_STINGS))
		traits += "Stings whoever handles it."
	if(S.get_trait(TRAIT_EXPLOSIVE))
		traits += "Explodes when thrown."
	if(S.get_trait(TRAIT_JUICY))
		traits += "Splatters when thrown."
	if(S.get_trait(TRAIT_TELEPORTING))
		traits += "Teleports whatever it hits."
	if(S.get_trait(TRAIT_BIOLUM))
		traits += "Glows."
	if(S.get_trait(TRAIT_PRODUCES_POWER))
		traits += "Its produce can power a battery."
	if(S.get_trait(TRAIT_IMMUTABLE) > 0)
		traits += "Never mutates."
	if(length(traits))
		blocks += list(wiki_h("Traits"), wiki_ul(traits))
	if(length(S.chems))
		var/list/chems = list()
		for(var/id in S.chems)
			chems += list(wiki_chem_link(id))
		blocks += list(wiki_links("Its produce contains", chems))
	if(length(S.consume_gasses) || length(S.exude_gasses))
		var/list/gas_lines = list()
		for(var/gas in S.consume_gasses)
			gas_lines += "Takes in [gas]."
		for(var/gas in S.exude_gasses)
			gas_lines += "Gives off [gas]."
		blocks += list(wiki_h("Air"), wiki_ul(gas_lines))
	if(length(S.mutants))
		var/list/mutants = list()
		var/list/seeds = plants_seeds()
		for(var/mutant in S.mutants)
			var/datum/seed/other = seeds[mutant]
			if(other)
				var/id = wiki_plant_id(other)
				mutants += list(wiki_link(wiki_title(id) ? id : null, capitalize(other.display_name || other.name)))
		if(length(mutants))
			blocks += list(wiki_links("Can mutate into", mutants))
	return blocks

// ---- creatures ----

/proc/wiki_fauna_id(path)
	return "fauna/[replacetext("[path]", "/mob/living/simple_mob/", "")]"

/// A creature the wiki files: every simple mob type with a name and a living sprite (a type without one is a base that never spawns as itself).
/proc/wiki_fauna_types()
	. = list()
	for(var/path in subtypesof(/mob/living/simple_mob))
		var/mob/living/simple_mob/M = path
		if(initial(M.name) && initial(M.icon_living))
			. += path

/proc/wiki_source_fauna(list/index)
	for(var/path in wiki_fauna_types())
		var/mob/living/simple_mob/M = path
		var/list/parts = splittext(replacetext("[path]", "/mob/living/simple_mob/", ""), "/")
		var/group = length(parts) > 1 ? capitalize(replacetext(parts[1], "_", " ")) : "Other"
		wiki_set_sprite(wiki_add(index, wiki_fauna_id(path), capitalize(initial(M.name)), "Creatures/[group]", null, null, GLOBAL_PROC_REF(wiki_fauna_body), path), path)

/proc/wiki_fauna_body(path)
	var/mob/living/simple_mob/M = path
	var/list/blocks = list(wiki_p(initial(M.desc) || "A creature."))
	var/list/facts = list()
	if(initial(M.melee_damage_upper) > 0)
		facts += list(list("Bites or strikes for", "[initial(M.melee_damage_lower)] to [initial(M.melee_damage_upper)] damage"))
	var/projectile = initial(M.projectiletype)
	if(ispath(projectile, /atom))
		var/atom/P = projectile
		facts += list(list("Ranged attack", "Fires [initial(P.name)]"))
	facts += list(list("Comfortable between", "[initial(M.minbodytemp)] K and [initial(M.maxbodytemp)] K"))
	facts += list(list("Breathes", initial(M.min_oxy) > 0 ? "Needs oxygen" : "Needs no oxygen"))
	if(initial(M.taser_kill))
		facts += list(list("Stun weapons", "Hurt by them (an electrical injury, not a stun)"))
	blocks += list(wiki_kv(facts))
	return blocks
