// per_type(nameof(var), PROC_REF(build)): a lazily built, read-only table shared by every instance of a type (doc/rewrite/final_api.html
// section 6 "Lifecycle forms", form 5).
//
//	CAPABILITIES(/obj/machinery/vending/coffee)
//		per_type(nameof(product_records), PROC_REF(build_products))
//
//	/obj/machinery/vending/coffee/proc/build_products()
//		. = list()
//		for(var/path in products)
//			. += new /datum/stored_item/vending_product(path, products[path])
//
// The first instance of the type to initialize calls build() and the result is kept for the type; every instance's var is set to that one
// table before its init code runs (preinit), so an Initialize() that only built a per-type list goes. build() reads only what every instance of
// the type shares (its compiled vars): it runs once. A subtype re-declaring the var gets its own table. The table is read-only: `analyze`
// rejects a write to a per_type var (an assignment to an element, +=, -=, Add, Remove, Cut, Insert, Swap) anywhere but its build proc.
//
// copy_on_write = TRUE makes the table a per-instance STARTING LIST: the var is declared bare (`var/list/words`, no initial value, so no
// instance allocates one), every instance holds the type's one table until it first writes, and that first write copies it. The var is a
// tracked list (the build names it, so `analyze` generates its setter and its add_v / include_v / remove_v / set_v_at / clear_v / insert_v /
// swap_v / cut_v mutators and the `tracked` lint rejects any raw in-place write); each mutator unshares first (code/engine/_generated/
// tracked_lists.dm), so a write never reaches the shared table or another instance. A map edit or a param that gave the var a value is kept.
//
//	CAPABILITIES(/obj/item/megaphone)
//		per_type(nameof(volume_options), PROC_REF(build_volume_options), copy_on_write = TRUE)
//
// The copy is one level deep: a list of lists shares its inner lists, so a nested table is not a starting list.

/proc/per_type(var_name, build, copy_on_write = FALSE)
	if(!istext(var_name) || !istext(build))
		declare_report("per_type(): needs nameof(var) and PROC_REF(build)")
		return null
	return entry_make(ENTRY_PER_TYPE, "per_type:[var_name]", list("var" = var_name, "build" = build, "cow" = !!copy_on_write))

/// The stock build of a per_type() var that only interns the type's own value: per_type(nameof(attacktext), TYPE_PROC_REF(/datum, per_type_own)) makes every
/// instance of the type share the first one's list (what shared_type_list() did by hand in Initialize()).
/datum/proc/per_type_own(var_name)
	return vars[var_name]

/// type -> var -> the built table.
/proc/per_type_tables()
	var/static/list/tables = list() // ALLOW(sys_static_getter): built lazily per type by the first instance, which a TYPE_TABLE (built at compile time) cannot do
	return tables

/proc/per_type_bind(datum/holder, datum/lifeform_plan/P)
	var/list/tables = per_type_tables()
	var/list/mine = tables[holder.type]
	if(!mine)
		mine = list()
		tables[holder.type] = mine
	for(var/datum/centry/C as anything in P.per_types)
		var/datum/entry/E = C.item
		var/var_name = E.args["var"]
		if(!(var_name in holder.vars))
			declare_report("[C.origin]: per_type(\"[var_name]\") on [holder.type]: no such var")
			continue
		if(E.args["cow"] && !isnull(holder.vars[var_name]))
			continue // a map edit or a param gave this instance its own list
		if(!(var_name in mine))
			mine[var_name] = call(holder, E.args["build"])(var_name) // build(var_name): one build proc may serve several vars
		if(E.args["cow"] && COW_LISTS_EAGER)
			var/list/own = mine[var_name]
			holder.vars[var_name] = own.Copy() // ALLOW(api): the measurement mode: a private list per instance, as the initializer allocated
		else
			holder.vars[var_name] = mine[var_name] // ALLOW(api): every instance's per_type var names the one shared table
		if(E.args["cow"] && !COW_LISTS_EAGER)
			// Debug tracing (boot_phase_timers=1): the lists a starting list saved at init, one per bind (the initializer it replaced allocated one each), and their entries.
			BOOT_PHASE_COUNT("cow list: starting lists bound, none allocated")
			BOOT_PHASE_COUNT("cow list: entries not copied")
			if(GLOB.boot_phase_on)
				GLOB.boot_phase_counts["cow list: entries not copied"] += length(mine[var_name]) - 1

/// The table `type` has built for `var_name`, or null before its first instance (tests, explain tools).
/proc/per_type_table(type, var_name)
	return per_type_tables()[type]?[var_name]

/// The starting table of `holder`'s type for `var_name`: what a copy_on_write list holds until its first write. Every generated mutator of such a
/// list compares its var with this before it writes, once (while the list's `v_version` is still 0), and copies the list if it is the same one.
/proc/cow_table(datum/holder, var_name)
	RETURN_TYPE(/list)
	return per_type_tables()[holder.type]?[var_name]
