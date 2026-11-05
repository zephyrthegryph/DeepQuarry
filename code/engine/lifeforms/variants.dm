// variants(nameof(var), PROC_REF(table)) (doc/rewrite/final_api.html section 6 "Lifecycle forms"; code/content/variants/README.md).
//
//	CAPABILITIES(/obj/item/clothing/accessory/gaiter)
//		variants(nameof(variant), PROC_REF(variant_table))
//	/obj/item/clothing/accessory/gaiter/proc/variant_table()
//		return GLOB.dq_variants_accessory_gaiter
//
// A family of subtypes that differed only in data is one type plus a table: key -> list(var = value, ...). The instance's `var` (a map edit, a
// loadout's choice, a spawn list's key) names its row, and at preinit, before any init code reads the instance, each var the row gives a value is
// set (a list as a copy), a falsey value too (0, "", null, FALSE: a row can switch a default off). A key with no row, or no key, changes nothing.
// It replaces the Initialize() override that called apply_variant() before ..(); /obj/item/apply_variant() applies the declared table again
// when a loadout tweak sets the key after creation.

/proc/variants(var_name, table_proc)
	if(!istext(var_name) || !istext(table_proc))
		declare_report("variants(): needs nameof(var) and PROC_REF(table)")
		return null
	return entry_make(ENTRY_VARIANTS, "variants", list("var" = var_name, "table" = table_proc))

/// A row's value as one instance gets it: a list is copied, so an instance that changes its list (a rolled sleeve sets a slot) changes nobody else's.
/proc/variant_row_value(value)
	if(!islist(value))
		return value
	var/list/shared = value
	return shared.Copy()

/// Applies the row its variant var names to `holder` (preinit, and a later re-application). TRUE when a row was applied.
/proc/variant_apply(datum/holder)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	. = FALSE
	for(var/datum/centry/C as anything in P.variants)
		var/datum/entry/E = C.item
		var/key = holder.vars[E.args["var"]]
		if(isnull(key))
			continue
		var/list/table = call(holder, E.args["table"])()
		var/list/row = islist(table) ? table[key] : null
		if(!islist(row))
			continue
		for(var/var_name in row)
			if(!(var_name in holder.vars))
				declare_report("[C.origin]: variants() row '[key]' of [holder.type] sets '[var_name]', which it doesn't have")
				continue
			holder.vars[var_name] = variant_row_value(row[var_name]) // ALLOW(api): a variant row is the type's data for this key, applied before anything reads it
		. = TRUE
