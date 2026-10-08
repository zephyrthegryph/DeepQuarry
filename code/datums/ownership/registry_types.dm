// Registry types (doc/rewrite/ownership.md §2): each getter returns the registered instance D
// stands for, so D is shared iff getter(D) == D. This replaced the fiat OM_STATIC_TYPE list:
// a per-holder copy of a registry type (a mob's species copy, a mutated seed, a holder's
// reagent) is not registered and must be owned (or PROTO) by its holder.

REGISTRY_TYPE(/datum/controller, GLOBAL_PROC_REF(registry_controller))
REGISTRY_TYPE(/datum/ntnet, GLOBAL_PROC_REF(registry_ntnet))
REGISTRY_TYPE(/datum/transcore_db, GLOBAL_PROC_REF(registry_transcore_db))
REGISTRY_TYPE(/datum/property_registry, GLOBAL_PROC_REF(registry_property_registry))
REGISTRY_TYPE(/datum/property_def, GLOBAL_PROC_REF(registry_property_def))
REGISTRY_TYPE(/datum/techweb, GLOBAL_PROC_REF(registry_techweb))
REGISTRY_TYPE(/datum/planet, GLOBAL_PROC_REF(registry_planet))
REGISTRY_TYPE(/datum/asset, GLOBAL_PROC_REF(registry_asset))
REGISTRY_TYPE(/datum/log_category, GLOBAL_PROC_REF(registry_log_category))
REGISTRY_TYPE(/datum/decl, GLOBAL_PROC_REF(registry_decl))
REGISTRY_TYPE(/datum/definition_decl, GLOBAL_PROC_REF(registry_om_decl))
REGISTRY_TYPE(/datum/work_stage, GLOBAL_PROC_REF(registry_om_stage))
REGISTRY_TYPE(/datum/material, GLOBAL_PROC_REF(registry_material))
REGISTRY_TYPE(/datum/body_effect, GLOBAL_PROC_REF(registry_body_effect))
REGISTRY_TYPE(/datum/body_factor_def, GLOBAL_PROC_REF(registry_body_factor_def))
REGISTRY_TYPE(/datum/language, GLOBAL_PROC_REF(registry_language))
REGISTRY_TYPE(/datum/species, GLOBAL_PROC_REF(registry_species))
REGISTRY_TYPE(/datum/sprite_accessory, GLOBAL_PROC_REF(registry_sprite_accessory))
REGISTRY_TYPE(/datum/tgui_state, GLOBAL_PROC_REF(registry_tgui_state))
REGISTRY_TYPE(/datum/rule, GLOBAL_PROC_REF(registry_rule))
REGISTRY_TYPE(/datum/rule_type_table, GLOBAL_PROC_REF(registry_rule_type_table))
REGISTRY_TYPE(/datum/job, GLOBAL_PROC_REF(registry_job))
REGISTRY_TYPE(/datum/access, GLOBAL_PROC_REF(registry_access))
REGISTRY_TYPE(/datum/ore, GLOBAL_PROC_REF(registry_ore))
REGISTRY_TYPE(/datum/pipe_recipe, GLOBAL_PROC_REF(registry_pipe_recipe))
REGISTRY_TYPE(/datum/uplink_item, GLOBAL_PROC_REF(registry_uplink_item))
REGISTRY_TYPE(/datum/supply_pack, GLOBAL_PROC_REF(registry_supply_pack))
REGISTRY_TYPE(/datum/category_collection, GLOBAL_PROC_REF(registry_category_collection))
REGISTRY_TYPE(/datum/category_group, GLOBAL_PROC_REF(registry_category_group))
REGISTRY_TYPE(/datum/category_item, GLOBAL_PROC_REF(registry_category_item))
REGISTRY_TYPE(/datum/instrument, GLOBAL_PROC_REF(registry_instrument))
REGISTRY_TYPE(/datum/map_template, GLOBAL_PROC_REF(registry_map_template))
REGISTRY_TYPE(/datum/suit_cycler_choice, GLOBAL_PROC_REF(registry_suit_cycler_choice))
REGISTRY_TYPE(/datum/trade_destination, GLOBAL_PROC_REF(registry_trade_destination))
REGISTRY_TYPE(/datum/reagent, GLOBAL_PROC_REF(registry_reagent))
REGISTRY_TYPE(/datum/seed, GLOBAL_PROC_REF(registry_seed))
REGISTRY_TYPE(/datum/robot_sprite, GLOBAL_PROC_REF(registry_robot_sprite))
REGISTRY_TYPE(/datum/ai_icon, GLOBAL_PROC_REF(registry_ai_icon))
REGISTRY_TYPE(/datum/robolimb, GLOBAL_PROC_REF(registry_robolimb))

/// Enumerators for the DEF freeze (shared.dm): each returns a list (or assoc) of registered
/// instances whose vars must not change after boot. Services with round state (controllers,
/// techwebs, transcore, planets, logs) are registries but not frozen.
GLOBAL_LIST_INIT(registry_enum_procs, list(
	GLOBAL_PROC_REF(registry_enum_species),
	GLOBAL_PROC_REF(registry_enum_materials),
	GLOBAL_PROC_REF(registry_enum_languages),
	GLOBAL_PROC_REF(registry_enum_decls),
	GLOBAL_PROC_REF(registry_enum_reagents),
	GLOBAL_PROC_REF(registry_enum_jobs),
	GLOBAL_PROC_REF(registry_enum_ores),
))

/proc/registry_controller(datum/controller/D)
	if(D == Kernel || D == config || D == GLOB)
		return D
	return null

/proc/registry_ntnet(datum/D)
	return GLOB.ntnet_global

/proc/registry_transcore_db(datum/transcore_db/D)
	for(var/key in SStranscore?.databases)
		if(SStranscore.databases[key] == D)
			return D
	return null

/proc/registry_property_registry(datum/D)
	return dq_property_registry()

/proc/registry_property_def(datum/property_def/D)
	return dq_property_registry().defs[D.id]

/// Only the round's techwebs (science, admin, autounlock) are registered; a disk's or a
/// console's scratch web is owned by its holder.
/proc/registry_techweb(datum/techweb/D)
	return (D in SSresearch?.techwebs) ? D : null

/proc/registry_planet(datum/D)
	return (D in SSplanets?.planets) ? D : null

/proc/registry_asset(datum/D)
	return GLOB.asset_datums[D.type]

/proc/registry_log_category(datum/log_category/D)
	return logger?.log_categories[D.category]

/proc/registry_decl(datum/D)
	return GET_DECL(D.type)

/proc/registry_om_decl(datum/D)
	return (D in om_registry().decls) ? D : null

/proc/registry_om_stage(datum/D)
	return om_registry().stage_by_type[D.type]

/proc/registry_material(datum/material/D)
	return GLOB.name_to_material[D.name]

/proc/registry_body_effect(datum/D)
	return body_effect_def(D.type) // a def is made once per type and never replaced

/proc/registry_body_factor_def(datum/body_factor_def/D)
	var/list/defs = GLOBAL_TABLE_GET(body_factor_defs)
	return (D.id > 0 && D.id <= length(defs)) ? defs[D.id] : null

/proc/registry_language(datum/language/D)
	return GLOB.all_languages[D.name]

/proc/registry_species(datum/species/D)
	return GLOB.all_species[D.name]

/proc/registry_sprite_accessory(datum/sprite_accessory/D)
	for(var/list/L as anything in list(GLOB.hair_styles_list, GLOB.facial_hair_styles_list, GLOB.body_marking_styles_list))
		if(L[D.name] == D)
			return D
	for(var/list/L as anything in list(GLOB.ear_styles_list, GLOB.tail_styles_list, GLOB.wing_styles_list, GLOB.hair_accesories_list))
		if(L[D.type] == D)
			return D
	return null

/proc/registry_tgui_state(datum/D)
	return D // every tgui state is a GLOB.tgui_*_state singleton; nothing else makes one

/proc/registry_rule(datum/D)
	return GLOBAL_TABLE_GET(dq_rules)[D.type]

/proc/registry_rule_type_table(datum/rule_type_table/D)
	return dq_rule_table_for(D.rules) == D ? D : null

/proc/registry_job(datum/D)
	return SSjob?.type_occupations[D.type]

/proc/registry_access(datum/access/D)
	return SSaccess?.get_access_by_id(D.id)

/proc/registry_ore(datum/ore/D)
	return GLOB.ore_data[D.name]

/proc/registry_pipe_recipe(datum/D)
	for(var/list/recipes as anything in list(GLOB.atmos_pipe_recipes, GLOB.disposal_pipe_recipes))
		for(var/category in recipes)
			if(D in recipes[category])
				return D
	return null

/proc/registry_uplink_item(datum/D)
	return GLOB.uplink?.items_assoc[D.type]

/proc/registry_supply_pack(datum/supply_pack/D)
	return SSsupply?.supply_pack[D.name]

/proc/registry_category_collection(datum/D)
	return (D == GLOB.global_underwear || D == GLOB.catalogue_data) ? D : null

/proc/registry_category_group(datum/category_group/D)
	return D.collection_static?.categories_by_name[D.name]

/proc/registry_category_item(datum/category_item/D)
	return D.category_static?.items_by_name[D.name]

/proc/registry_instrument(datum/instrument/D)
	return SSinstruments?.instrument_data[D.id]

/proc/registry_map_template(datum/map_template/D)
	return (SSmapping?.map_templates[D.name] == D || (D in SSmapping?.shelter_templates)) ? D : null

/proc/registry_suit_cycler_choice(datum/D)
	return ((D in GLOB.suit_cycler_departments) || (D in GLOB.suit_cycler_species) || (D in GLOB.suit_cycler_emagged)) ? D : null

/proc/registry_trade_destination(datum/D)
	return (D in GLOB.weighted_randomevent_locations) ? D : null

/proc/registry_reagent(datum/reagent/D)
	return SSchemistry.ready()?.chemical_reagents[D.id]

/proc/registry_seed(datum/seed/D)
	return SSplants?.seeds[D.name]

/proc/registry_robot_sprite(datum/D)
	return (D in SSrobot_sprites?.all_cyborg_sprites) ? D : null

/proc/registry_ai_icon(datum/D)
	return (D == GLOB.default_ai_icon || (D in GLOB.ai_icons)) ? D : null

/proc/registry_robolimb(datum/robolimb/D)
	if(D == GLOB.basic_robolimb)
		return D
	return GLOB.all_robolimbs[D.company]

/proc/registry_enum_species()
	return GLOB.all_species
/proc/registry_enum_materials()
	return GLOB.name_to_material
/proc/registry_enum_languages()
	return GLOB.all_languages
/proc/registry_enum_decls()
	return GLOB.decls_repository?.fetched_decls
/proc/registry_enum_reagents()
	return SSchemistry.ready()?.chemical_reagents
/proc/registry_enum_jobs()
	return SSjob?.type_occupations
/proc/registry_enum_ores()
	return GLOB.ore_data
