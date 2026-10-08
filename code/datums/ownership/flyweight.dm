// Flyweights (doc/rewrite/state_and_relations.md section 2, "Shared values"): datums built once and shared by
// every holder that names them (interned capabilities, reactions, recipe tables, declaration
// entries). A var holding one is not a relation and has no declaration: its type says it. Like a registered
// singleton (REGISTRY_TYPE), a flyweight is never owned, never cleared and never a destroy leak.
//
//	/datum/sys_periodic_table
//		var/datum/sys_periodic_def/while_def      // a registry type: shared by its type, no shares() line
//	/obj/item
//		var/list/datum/stack_recipe/recipes   // a flyweight type: same
//
// tools/ci/ownership_lint.py reads FLYWEIGHT_TYPES (keep the two lists in step).

/// The flyweight roots: every subtype is a flyweight too.
GLOBAL_LIST_INIT(flyweight_types, typecacheof(list(
	/datum/capability,
	/datum/reaction,
	/datum/stack_recipe,
	/datum/stack_recipe_list,
	/datum/own_entry,
	/datum/derived_entry,
	/datum/op_def,
)))

/// TRUE when `D` is a flyweight: shared by type, never owned, skipped by the destroy leak check.
