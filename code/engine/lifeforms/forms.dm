// The lifecycle forms (doc/rewrite/final_api.html section 6 "Lifecycle forms"; the conversion guide's "Lifecycle forms" section).
//
// Nine declaration forms take over what Initialize() overrides, qdel(src) and `usr` did by hand. Each is an entry of a CAPABILITIES block
// (built by a constructor in this folder, interned by entry_make()) or a call the engine owns:
//
//	rolls(target, generator, when =, from =)             per-instance randomness rolled before init, seeded             rolls.dm
//	param(var, schema, default =, required =, pos =)     a named constructor argument, set before init; make(type, at, ...)  params.dm
//	built_from(var)                                      the construction parts a make(..., parts =) hands over          params.dm
//	registry(REGISTRY_X, key =, by =)                    a keyed, re-keyed, auto-removed registry membership             registry.dm
//	radio_listen(freq =, filter =)                       a radio listener that retunes when its var changes             registry.dm
//	adjacency(KIND, dirs =, connects =, into =, when =)  a tracked neighbour relation the engine keeps (index in Rust)    adjacency.dm
//	per_type(var, PROC_REF(build))                       a lazily built read-only per-type table                        per_type.dm
//	variants(var, PROC_REF(table))                       a variant key's row of vars, applied at preinit                variants.dm
//	initial_contents(type, slot =, count =) · knows(LANGUAGE)    initial contents and languages; OWNER in starts_args           contents.dm
//	starts_as(STATE) · derives(target, PROC_REF, from =) an op's effects at creation; a tracked computed value           derives.dm
//	lives_while(scope, watches =) · on_ending(PROC_REF)  a scoped lifetime; spent()/consumed()/destroyed()/dissolved()  lifetimes.dm
//	click_on/drag_onto/hover(op) · tooltip(PROC_REF)     input with an actor bound to ops; with_actor(actor, CALLBACK)   input.dm
//
// This file is the shared part: the per-type plan (which forms a type declares, in order, resolved once), the lifecycle dispatch the declaration
// engine calls (preinit, init, destroy), and the change watch the forms that follow a var use (registry keys, radio frequencies, derives inputs,
// lives_while watches). A var a form watches must publish its writes: TRACKED(T, var), or a setter that calls tracked_changed().
//
// Order for one instance, inside the root of the Initialize() chain (section 6 "Order for one instance", steps 1a and 5a):
//	preinit:  make() arguments were applied in /atom/New(); positional constructor arguments map to param(pos =); params are checked; per_type
//	          tables are bound; rolls() roll (a map-edited or param-given value suppresses its roll)
//	init:     initial_contents() and knows() create contents; param(apply =) setters run; starts_as() runs; derives() compute; registry(), radio_listen() and adjacency() join;
//	          lives_while() arms its scope
//	destroy:  on_ending() runs, the "ended" notice goes out with its cause, then registries, radio and adjacency are left

/// The forms one type declares, resolved from its compiled table once and shared by every instance of the type. Read-only after build.
/datum/lifeform_plan
	var/owner_type
	/// centry lists, by kind, in effective order (a later entry for the same target replaced an earlier one).
	var/list/rolls
	var/list/params
	var/list/built_from
	var/list/registries
	var/list/radios
	var/list/adjacencies
	var/list/per_types
	var/list/variants
	var/list/contains
	var/list/knows
	var/list/starts_as
	var/list/derives
	var/list/lives_while
	var/list/on_ending
	var/list/inputs
	var/datum/centry/tooltip
	/// var name -> list of /datum/centry of the forms that follow that var (registry keys, radio frequencies, derives inputs, lives_while).
	var/list/watch
	/// param pos -> var name (positional constructor arguments).
	var/list/param_pos
	/// The params declared with apply =, in order: their setters run at init.
	var/list/param_applies
	/// The params declared keep = FALSE: dropped once the setters ran.
	var/list/param_drops
	/// TRUE when anything must run at preinit / init / destroy.
	var/pre = FALSE
	var/init = FALSE
	var/destroy = FALSE

/// The lifeform plan of D's type (built on first use).
/proc/lifeform_plan_of(datum/D)
	RETURN_TYPE(/datum/lifeform_plan)
	var/static/list/plans = list()
	var/datum/lifeform_plan/P = plans[D.type]
	if(P)
		return P
	P = lifeform_plan_build(table_of(D), D)
	plans[D.type] = P
	return P

/// The kinds each plan list collects (kind -> the plan's list var). A target-keyed kind keeps the last entry per target (a subtype re-declares
/// to change it). A static, not a GLOB list: tables are built while the globals are still being made.
/proc/lifeform_kinds()
	var/static/list/kinds = list( // ALLOW(sys_static_getter): the declaration tables are built while the globals are still being made
		ENTRY_ROLLS = "rolls", ENTRY_PARAM = "params", ENTRY_BUILT_FROM = "built_from", ENTRY_REGISTRY = "registries",
		ENTRY_RADIO_LISTEN = "radios", ENTRY_ADJACENCY = "adjacencies", ENTRY_PER_TYPE = "per_types", ENTRY_VARIANTS = "variants", ENTRY_CONTAINS = "contains",
		ENTRY_KNOWS = "knows", ENTRY_STARTS_AS = "starts_as", ENTRY_DERIVES = "derives", ENTRY_LIVES_WHILE = "lives_while",
		ENTRY_ON_ENDING = "on_ending", ENTRY_INPUT = "inputs")
	return kinds

/proc/lifeform_plan_build(datum/type_table/T, datum/D)
	var/datum/lifeform_plan/P = new
	P.owner_type = T.owner_type
	var/list/by_target = list()
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(!istype(E))
			continue
		if(E.kind == ENTRY_TOOLTIP)
			P.tooltip = C // ALLOW(ownership): a per-type plan names a compiled entry of its own table, never freed
			continue
		var/list_name = lifeform_kinds()[E.kind]
		if(!list_name)
			continue
		var/target = E.key
		if(target)
			var/datum/centry/old = by_target[target]
			if(old)
				P.vars[list_name] -= old
		var/list/into = P.vars[list_name]
		if(!into)
			into = list()
			P.vars[list_name] = into // ALLOW(api): the plan's lists are filled by kind name from one table walk
		into += C
		if(target)
			by_target[target] = C
	lifeform_plan_finish(P, D)
	return P

/// Works out what runs when, the watched vars and the positional params; validates against the first instance.
/proc/lifeform_plan_finish(datum/lifeform_plan/P, datum/D)
	P.pre = !!(P.rolls || P.params || P.per_types || P.built_from || P.variants)
	P.destroy = !!(P.registries || P.radios || P.adjacencies || P.on_ending || P.lives_while || P.derives)
	for(var/datum/centry/C as anything in P.params)
		var/datum/entry/E = C.item
		if(!(E.args["var"] in D.vars))
			declare_report("[C.origin]: param(\"[E.args["var"]]\") on [D.type]: no such var")
		if(isnum(E.args["pos"]))
			LAZYSET(P.param_pos, "[E.args["pos"]]", E.args["var"])
		if(E.args["apply"])
			if(!hascall(D, E.args["apply"]))
				declare_report("[C.origin]: param(\"[E.args["var"]]\", apply = [E.args["apply"]]) on [D.type]: no such proc")
			else
				LAZYADD(P.param_applies, C) // ALLOW(ownership): a per-type plan indexes compiled entries of its own table, never freed
		if(E.args["keep"] == FALSE)
			LAZYADD(P.param_drops, C) // ALLOW(ownership): a per-type plan indexes compiled entries of its own table, never freed
	P.init = !!(P.contains || P.knows || P.param_applies || P.param_drops || P.starts_as || P.derives || P.registries || P.radios || P.adjacencies || P.lives_while)
	for(var/kind_list in list(P.registries, P.radios, P.derives, P.lives_while, P.adjacencies))
		for(var/datum/centry/C as anything in kind_list)
			var/datum/entry/E = C.item
			for(var/var_name in lifeform_watched_vars(E))
				if(!(var_name in D.vars))
					declare_report("[C.origin]: [E.kind]() on [D.type] watches '[var_name]', which it doesn't have")
					continue
				LAZYINITLIST(P.watch)
				LAZYADD(P.watch[var_name], C) // ALLOW(ownership): a per-type plan indexes compiled entries of its own table, never freed
				if(!lifeform_watch_keys)
					lifeform_watch_keys = list()
				lifeform_watch_keys[var_name] = TRUE

/// The vars an entry follows: its changes re-key, retune, recompute or re-check the scope.
/proc/lifeform_watched_vars(datum/entry/E)
	. = list()
	switch(E.kind)
		if(ENTRY_REGISTRY)
			if(istext(E.args["key"]))
				. += E.args["key"]
		if(ENTRY_RADIO_LISTEN)
			if(istext(E.args["freq"]))
				. += E.args["freq"]
		if(ENTRY_ADJACENCY)
			if(istext(E.args["when"]))
				. += E.args["when"]
		if(ENTRY_DERIVES, ENTRY_LIVES_WHILE)
			for(var/read in E.args["from"])
				if(istext(read))
					. += read

/// ENGINE_HOOK_* bits the forms of a compiled table ask of the lifecycle (table_hook_flags()).
/proc/lifeform_hook_flags(datum/type_table/T)
	. = 0
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(!istype(E))
			continue
		if(lifeform_kinds()[E.kind] || E.kind == ENTRY_TOOLTIP)
			return ENGINE_HOOK_LIFEFORMS | ENGINE_HOOK_PREINIT | ENGINE_HOOK_INIT | ENGINE_HOOK_DESTROY

// ---- the lifecycle dispatch (engine_holder_preinit/init/destroy, code/engine/declare/scopes.dm) ----

/// Before the type's init code reads the instance: positional params, param checks, per_type tables, rolls.
/proc/lifeform_preinit(datum/holder, mapload)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	if(!P.pre)
		return
	if(P.params || P.built_from)
		params_preinit(holder, P, mapload)
	if(P.per_types)
		per_type_bind(holder, P)
	if(P.variants)
		variant_apply(holder) // before the rolls: a roll of a var the row sets still wins, as it did after the old apply_variant()
	if(P.rolls)
		rolls_run(holder, P, mapload)

/// After the capabilities initialized: contents, languages, starting state, derived values, registries, radio, adjacency, scopes.
/proc/lifeform_init(datum/holder, mapload)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	if(!P.init)
		return
	if(P.contains)
		roll_creator_push(holder) // what it creates rolls from its stream
		contains_init(holder, P)
		roll_creator_pop(holder)
	else if(P.rolls)
		GLOB.roll_rollers -= holder // its own rolls are done
	if(P.knows)
		knows_init(holder, P)
	if(P.param_applies || P.param_drops)
		params_apply(holder, P)
		if(QDELETED(holder))
			return
	if(P.starts_as)
		starts_as_init(holder, P)
	if(P.derives)
		derives_init(holder, P)
	if(P.registries)
		registry_init(holder, P)
	if(P.radios)
		radio_listen_init(holder, P)
	if(P.adjacencies)
		adjacency_init(holder, P)
	if(P.lives_while)
		lives_while_init(holder, P)

/// First in the destroy transaction: the ending's hooks and notice, then what the forms joined is left.
/proc/lifeform_destroy(datum/holder)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	ending_announce(holder, P)
	if(!P.destroy)
		return
	if(P.lives_while)
		lives_while_teardown(holder)
	if(P.registries)
		registry_teardown(holder, P)
	if(P.radios)
		radio_listen_teardown(holder, P)
	if(P.adjacencies)
		adjacency_teardown(holder, P)
	if(P.derives)
		LAZYREMOVE(GLOB.derives_running, holder)

// ---- the change watch ----

/// Var names some lifeform watches on some type: a write of one is published (rx_readers()) so lifeform_published() hears it. A real global
/// (not GLOB): plans are built while the globals are still being made, and rx_readers() reads it on every tracked write.
GLOBAL_REAL_VAR(list/lifeform_watch_keys)

/// TRUE when a form of E's type follows `key` (rx_readers() asks, so changed() publishes the write).
/proc/lifeform_watching(datum/E, key)
	if(!lifeform_watch_keys?[key])
		return FALSE
	var/datum/type_table/T = type_table_cache()[E.type]
	if(!T || !(T.hook_flags & ENGINE_HOOK_LIFEFORMS))
		return FALSE
	var/datum/lifeform_plan/P = lifeform_plan_of(E)
	return !!P.watch?[key]

/// `key` of E was written: each form that follows it reacts now (a re-key, a retune, a recompute, a scope check). Synchronous: the reaction is
/// part of the write, so a registry lookup on the next line sees the new key.
/proc/lifeform_published(datum/E, key)
	if(!lifeform_watch_keys?[key] || QDELING(E))
		return
	var/datum/type_table/T = type_table_cache()[E.type]
	if(!T || !(T.hook_flags & ENGINE_HOOK_LIFEFORMS))
		return
	var/datum/lifeform_plan/P = lifeform_plan_of(E)
	for(var/datum/centry/C as anything in P.watch?[key])
		var/datum/entry/F = C.item
		switch(F.kind)
			if(ENTRY_REGISTRY)
				registry_rekey(E, C)
			if(ENTRY_RADIO_LISTEN)
				radio_listen_tune(E, C)
			if(ENTRY_DERIVES)
				derives_compute(E, C)
			if(ENTRY_LIVES_WHILE)
				lives_while_check(E, C)
			if(ENTRY_ADJACENCY)
				adjacency_when_changed(E, C)

// ---- plain datums ----

/// A non-atom datum whose type declares a lifecycle form runs it from New(): /datum/New() calls this when the generated flag
/// `lifeform_declared` is set (analyze gen declare sets it for a non-atom CAPABILITIES block that names a form or an owns_* with starts =).
/datum/var/tmp/lifeform_declared = FALSE

/proc/lifeform_datum_new(datum/D)
	if(length(GLOB?.make_pending))
		make_pending_for(D) // a make() of this type: its params, before anything else
	lifecycle_decls_init(D) // preinit (rolls, params) and owns_one/owns_many starts =
	var/datum/type_table/T = table_of(D)
	if(T.hook_flags & ENGINE_HOOK_MODES)
		modes_init(D, T) // a plain datum with modes() starts in the state its var names, as an atom does when it initializes
	if(T.hook_flags & ENGINE_HOOK_LIFEFORMS)
		lifeform_init(D, FALSE)
		if(param_drop_pending?[D])
			params_drop(D)
		hooks_change_baseline(D)
