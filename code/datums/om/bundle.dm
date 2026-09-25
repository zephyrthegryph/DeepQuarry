// Table-first declarations (doc/rewrite/object_model_core.md, "Tables").
//
// DM cannot read a type's list vars without an instance, so entity tables live
// on small singleton datums instead of on the entity type itself:
//
//	/datum/om/decl/recharger
//		of = /obj/machinery/recharger
//		include = list(/datum/om/bundle/powered_machine)
//		ticks = list(/obj/machinery/recharger/proc/charge = list(every = 2 SECONDS, clock = CLOCK_MACHINE))
//		reacts = list(/obj/machinery/recharger/proc/power_changed = CHANGE_MACHINE_POWER)
//
// A decl applies to `of` and every subtype, so base-type families supply
// defaults; a more specific decl adds to them. Bundles are the same rows with
// no `of`, included by decls, other bundles, and relations. Every row is
// parsed once when the registry builds; a malformed row is a boot error.

/datum/om/bundle
	abstract_type = /datum/om/bundle
	/// Bundles merged into this one (nesting allowed; cycles are boot errors).
	var/list/include
	/// Global effect definitions: id -> list(combine=, stacking=, channel=, default=, expr=, type=).
	var/list/effects
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
	/// /datum/om/event/x = /type/proc/y: calls E.y(event).
	var/list/events
	/// Full behaviour types attached to the entity.
	var/list/behaviours
	/// name -> task row (see task.dm).
	var/list/tasks
	/// UI binding rows: list(list(target = /type/proc/x, watch = mask, stream_rates = list(names))).
	var/list/ui
	/// effect id -> value (number or FROM_VAR) the entity holds on itself while started.
	var/list/self_effects
	/// grant kind -> id or list of ids the entity holds on itself.
	var/list/self_grants
	/// For relations and slots: effect id -> value held on the target (the holder).
	var/list/contributes
	/// For relations and slots: effect id -> value held on the source (the occupant).
	var/list/source_contributes
	/// For relations and slots: grant kind -> id(s) held on the target.
	var/list/grants_target
	/// For relations and slots: grant kind -> id(s) held on the source (the occupant).
	var/list/grants_occupant

	/// Compiled by the registry: inline behaviours synthesised from this bundle's own rows.
	var/list/compiled_behaviours

/// A bundle bound to an entity type.
/datum/om/decl
	parent_type = /datum/om/bundle
	abstract_type = /datum/om/decl
	/// Entity type (and subtypes) these rows apply to.
	var/of

/// The compiled table for one concrete entity type: what om_start() attaches.
/datum/om/type_table
	/// Behaviour defs, sorted by id (run order).
	var/list/behaviours = list()
	/// name -> /datum/om/task
	var/list/tasks = list()
	/// UI rows.
	var/list/ui = list()
	/// Stride 2: effect id, value spec.
	var/list/self_effects = list()
	/// Stride 2: grant kind, id.
	var/list/self_grants = list()
	/// Global observer mask for this type (services).
	var/service_mask = 0
	/// Services observing this type.
	var/list/services

// ---- Combinators (plain lists; used by checks, effects and derived rows). ----


/// Resolves a table value against its holder: FROM_VAR("x") reads holder.x,
/// FROM_DERIVED("n") reads a derived value, FROM_EFFECT(id) an effect value.
/// Anything else is returned as is.
/proc/om_read(datum/holder, spec)
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
			return holder && om_derived(holder, L[2])
		if("effect")
			return holder && om_value_of(holder, L[2])
	return spec
