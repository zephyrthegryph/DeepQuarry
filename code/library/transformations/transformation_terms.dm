// Terms of a transformation (doc/rewrite/proposals/transformations.md section 3): one input or output, `currency(key, amount)`.
//
//   reagent(REAGENT_ID_WATER, 5)          a reagent amount in the subject's reagents() holder
//   gas(GAS_PLASMA, 1)                    moles in the subject's mixture
//   ore_term(ORE_CARBON, 1)               a smelter's stock key
//   fruit_term(PLANT_CHILI, 1)            a grown item matched by seed kitchen tag
//   item_term(/obj/item/x, 1)             items of a type (item() and stack() are already the op input parts of code/engine/parts)
//   stack_term(/obj/item/stack/x, 4)      units of one stack
//
// A term is an interned entry, so the same term written twice is one datum and a rule that lists it shares it. The compile flattens a rule's terms to
// plain rows (xform_rows()), which is all the matcher reads.

/// A term of `currency`: what `key` names in that currency's medium, and how much.
/proc/xform_term(currency, key, amount = 1, into = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_XTERM, null, list("currency" = currency, "key" = key, "amount" = amount, "into" = into))

/proc/reagent(reagent_id, amount = 1)
	RETURN_TYPE(/datum/entry)
	return xform_term(XCUR_REAGENT, reagent_id, amount)

/proc/gas(gas_id, moles = 1)
	RETURN_TYPE(/datum/entry)
	return xform_term(XCUR_GAS, gas_id, moles)

/proc/ore_term(ore_key, amount = 1)
	RETURN_TYPE(/datum/entry)
	return xform_term(XCUR_ORE, ore_key, amount)

/proc/fruit_term(tag, amount = 1)
	RETURN_TYPE(/datum/entry)
	return xform_term(XCUR_FRUIT, tag, amount)

/proc/item_term(item_type, amount = 1, into = null)
	RETURN_TYPE(/datum/entry)
	return xform_term(XCUR_ITEM, item_type, amount, into)

/proc/stack_term(stack_type, amount = 1, into = null)
	RETURN_TYPE(/datum/entry)
	return xform_term(XCUR_STACK, stack_type, amount, into)

/// Terms flattened to rows of list(currency, key, amount, into), in declaration order. A bare list or nested lists are accepted.
/proc/xform_rows(list/terms)
	. = list()
	for(var/term in entry_flatten(terms))
		var/datum/entry/E = term
		if(!istype(E) || E.kind != ENTRY_XTERM)
			continue
		. += list(list(E.args["currency"], E.args["key"], E.args["amount"], E.args["into"]))

/// The rows of one currency as an assoc list key => amount (the shape reagent holders and gas mixtures are asked in), or null when there are none.
/proc/xform_assoc(list/rows, currency)
	var/list/result = null
	for(var/list/row as anything in rows)
		if(row[1] == currency)
			LAZYSET(result, row[2], row[3])
	return result

/// The currency of the first row, or null: the medium of a rule is inferred from it.
/proc/xform_first_currency(list/rows)
	for(var/list/row as anything in rows)
		return row[1]
	return null
