// Table-first declarations (doc/rewrite/object_model_core.md, "Tables").
//
// DM cannot read a type's list vars without an instance, so entity tables live
// on small singleton datums instead of on the entity type itself:
//
//	/datum/definition_decl/recharger
//		of = /obj/machinery/recharger
//		include = list(/datum/definition_bundle/powered_machine)
//		ticks = list(/obj/machinery/recharger/proc/charge = list(every = 2 SECONDS))
//		reacts = list(/obj/machinery/recharger/proc/power_changed = CHANGE_MACHINE_POWER)
//
// A decl applies to `of` and every subtype, so base-type families supply
// defaults; a more specific decl adds to them. Bundles are the same rows with
// no `of`, included by decls, other bundles, and relations. Every row is
// parsed once when the registry builds; a malformed row is a boot error.

/datum/definition_bundle
	parent_type = /datum/core_definition
	abstract_type = /datum/definition_bundle
	/// Bundles merged into this one (nesting allowed; cycles are boot errors).
	var/list/include
	/// Global clock domains: id -> list(min=, max=).
	var/list/clocks
	/// Named checks: name -> check spec (usable anywhere a spec is).
	var/list/checks
	/// DERIVE*() rows (derived values, names are global).
	var/list/derived
	/// /type/proc/x = channel mask: calls E.x(changes) on change.
	var/list/reacts
	/// /type/proc/x = list(every=, clock=, lane=, max_interval=, max_dt=, relevance=, order_after=): calls E.x(dt).
	var/list/ticks
	/// /datum/definition_event/x = /type/proc/y: calls E.y(event).
	var/list/events
	/// Full behaviour types attached to the entity.
	var/list/behaviours
	/// Pipeline stages this entity type runs besides its pipelines' own (each stage names its
	/// pipeline; a family root listed here resolves to the entity's variant).
	var/list/stages
	/// UI binding rows: list(list(target = /type/proc/x, watch = mask)).
	var/list/ui

	/// Compiled by the registry: inline behaviours synthesised from this bundle's own rows.
	var/list/compiled_behaviours

/// A bundle bound to an entity type.
/datum/definition_decl
	parent_type = /datum/definition_bundle
	abstract_type = /datum/definition_decl
	/// Entity type (and subtypes) these rows apply to, or a list of types.
	var/of

/// The compiled table for one concrete entity type: what entity_start() attaches.
/datum/scheduler_type_table
	/// Behaviour defs, sorted by id (run order).
	var/list/behaviours
	/// Stage types from `stages` rows (pipeline.dm).
	var/list/stages
	/// UI rows.
	var/list/ui
	/// Global observer mask for this type (services).
	var/service_mask = 0
	/// Cross-entity derived inputs ("rel.field", fields.dm): stride 2, relation var name, field name.
	var/list/derived_relays
	/// The channels of those relation vars: a raise resubscribes (scheduler_field_derived_relink()).
	var/relay_mask = 0
	/// Services observing this type.
	var/list/services
	/// Parallel to services: the channels each service observes on this type (per-(service, type) mask).
	var/list/service_masks
	/// Declared caches (declared_cache_vars(), read from the first instance by
	/// entity_cache_scan()): the change bits that clear one, and stride-2 rules
	/// (bits, var) / (event path, var) / (relation id, var).
	var/cache_scanned = FALSE
	/// Declared appearance watch mask (appearance_mask_of(), code/datums/sys/appearance.dm), read once.
	var/appearance_scanned = FALSE
	var/appearance_mask = 0
	var/cache_mask = 0
	var/list/cache_change
	var/list/cache_events
	var/list/cache_relations

// ---- Combinators (plain lists; used by checks and derived rows). ----


/// Resolves a table value against its holder: FROM_VAR("x") reads holder.x,
/// FROM_DERIVED("n") reads a derived value.
/// Anything else is returned as is.
/proc/definition_read(datum/holder, spec)
	if(!islist(spec))
		return spec
	var/list/L = spec
	if(length(L) != 2 || !istext(L[1]))
		return spec
	switch(L[1])
		if("var")
			if(!holder)
				return null
			return holder.vars[L[2]]
		if("derived")
			return holder && derived_derived(holder, L[2])
	return spec

/datum/scheduler_type_table/New()
	if(!behaviours)
		behaviours = list()
	if(!stages)
		stages = list()
	if(!ui)
		ui = list()
	..()
