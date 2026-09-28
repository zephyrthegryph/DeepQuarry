// Singleton / flyweight / definition types (doc/rewrite/object_model_core.md, "Ownership").
//
// Every datum has exactly one owner. Instances of the types below are owned by a
// registry, a subsystem or the round itself and are shared by everything that
// uses them, so a reference to one is REF_STATIC (a strong var, never cleared,
// never a leak) or, better, no var at all: read it from the registry at the use
// site. An om_handle() to one of these is refused by tools/ci/handle_kinds_lint.py.
//
// Add a type here (or put OM_STATIC_TYPE(...) next to its definition) when every
// instance is either a round-long singleton, or a shared flyweight nobody deletes
// (a diverged seed, an engineered material). tools/ci/ref_kinds.py collects every
// OM_STATIC_TYPE line in code/.

// World services and controllers.
OM_STATIC_TYPE(/datum/controller)
OM_STATIC_TYPE(/datum/ntnet)
OM_STATIC_TYPE(/datum/transcore_db)
OM_STATIC_TYPE(/datum/property_registry)
OM_STATIC_TYPE(/datum/techweb)
OM_STATIC_TYPE(/datum/planet)
OM_STATIC_TYPE(/datum/asset)
OM_STATIC_TYPE(/datum/log_category)

// Definitions: one instance per type or per id, built at init, read for the round.
OM_STATIC_TYPE(/datum/decl)
OM_STATIC_TYPE(/datum/om/decl)
OM_STATIC_TYPE(/datum/om/stage)
OM_STATIC_TYPE(/datum/material)
OM_STATIC_TYPE(/datum/property_def)
OM_STATIC_TYPE(/datum/body_effect)
OM_STATIC_TYPE(/datum/body_factor_def)
OM_STATIC_TYPE(/datum/language)
OM_STATIC_TYPE(/datum/species)
OM_STATIC_TYPE(/datum/sprite_accessory)
OM_STATIC_TYPE(/datum/tgui_state)
OM_STATIC_TYPE(/datum/rule)
OM_STATIC_TYPE(/datum/job)
OM_STATIC_TYPE(/datum/access)
OM_STATIC_TYPE(/datum/ore)
OM_STATIC_TYPE(/datum/pipe_recipe)
OM_STATIC_TYPE(/datum/uplink_item)
OM_STATIC_TYPE(/datum/supply_pack)
OM_STATIC_TYPE(/datum/category_collection)
OM_STATIC_TYPE(/datum/category_group)
OM_STATIC_TYPE(/datum/category_item)
OM_STATIC_TYPE(/datum/instrument)
OM_STATIC_TYPE(/datum/map_template)
OM_STATIC_TYPE(/datum/expedition_biome)
OM_STATIC_TYPE(/datum/generated_station_department_definition)
OM_STATIC_TYPE(/datum/suit_cycler_choice)
OM_STATIC_TYPE(/datum/trade_destination)
OM_STATIC_TYPE(/datum/malf_research_ability)

// Shared flyweight data: many holders share one instance and nobody deletes it;
// a holder may be the only thing keeping one alive (a diverged seed, the
// geosample of a mined-out turf), which is exactly why a handle is wrong here.
OM_STATIC_TYPE(/datum/seed)
OM_STATIC_TYPE(/datum/geosample)
OM_STATIC_TYPE(/datum/artifact_find)
