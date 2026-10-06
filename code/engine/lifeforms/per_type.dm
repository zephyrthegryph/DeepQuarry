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

/proc/per_type(var_name, build)
	if(!istext(var_name) || !istext(build))
		declare_report("per_type(): needs nameof(var) and PROC_REF(build)")
		return null
	return entry_make(ENTRY_PER_TYPE, "per_type:[var_name]", list("var" = var_name, "build" = build))

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
		if(!(var_name in mine))
			mine[var_name] = call(holder, E.args["build"])()
		holder.vars[var_name] = mine[var_name] // ALLOW(api): every instance's per_type var names the one shared table

/// The table `type` has built for `var_name`, or null before its first instance (tests, explain tools).
/proc/per_type_table(type, var_name)
	return per_type_tables()[type]?[var_name]
