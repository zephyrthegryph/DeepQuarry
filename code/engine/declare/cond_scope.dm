// Condition scope (doc/rewrite/final_api.html, section 5 "Scoped activation (X1)"): a type-level entry of a kind whose engine is cond_scoped
// (heat_link(), heat_pump(), heat_engine(): the heat domain's edges) is an activation of the holder that lives exactly while its enclosing when()
// conditions hold, the same way a while_slotted() entry lives for the item's time in the slot. The engine applies it through apply() and takes it
// back through remove(), so the declaration alone says when the thing exists:
//
//	when(STAT_OPERABLE, heat_pump(HEAT_AIR, HEAT_HULL, watts = nameof(heating_power), target = nameof(set_temperature)))
//	    the pump exists while the machine works; a broken or unpowered machine has none, with no code that removes it
//
// The conditions' inputs, and the vars of the holder the entry reads (its args named in reads), are watched by on_change hooks that
// table_cond_gates() adds to the type; a change re-applies the scope, so the entry always has the current values.

/// The holder initialized: every condition-scoped entry of its type whose conditions hold is applied.
/proc/activations_cond_init(datum/holder, datum/type_table/T)
	for(var/datum/centry/C as anything in cond_scoped_entries(T))
		cond_scope_apply(holder, C)

/// The type-level entries of condition-scoped kinds of a compiled table.
/proc/cond_scoped_entries(datum/type_table/T)
	. = list()
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && isnull(C.owner) && entry_engine_for(E.kind)?.cond_scoped)
			. += C

/// Attaches one condition-scoped entry to `holder` when its when() conditions hold.
/proc/cond_scope_apply(datum/holder, datum/centry/C)
	if(QDELETED(holder))
		return
	if(length(C.whens) && !op_whens_hold(holder, C.whens))
		return
	activation_attach(holder, hook_capability_of(list(C.item), FALSE), holder, null, SCOPE_COND, C, null)

/// Ends what one condition-scoped entry gave `holder`.
/proc/cond_scope_end(datum/holder, datum/centry/C)
	for(var/datum/activation/A as anything in holder.rx?.activations?.Copy())
		if(!A.dead && A.scope == SCOPE_COND && A.scope_data == C)
			activation_end(A)

/// An input of a condition-scoped entry of `holder`'s type changed: each such entry is re-applied, so its condition and its read values are the
/// current ones.
/proc/activations_cond_regate(datum/holder)
	if(QDELETED(holder))
		return
	for(var/datum/centry/C as anything in cond_scoped_entries(table_of(holder)))
		cond_scope_end(holder, C)
		cond_scope_apply(holder, C)

/// The on_change handler table_cond_gates() gives a type.
/proc/activations_cond_regate_hook(datum/act/A)
	activations_cond_regate(A.holder)

/// The inputs a condition-scoped entry is re-applied on: its when() conditions (and the bits the stats in them read), and the holder vars the
/// entry's own args name (reads = list(...) on the entry).
/proc/cond_scope_inputs(datum/centry/C, datum/type_table/T)
	. = list()
	for(var/datum/entry/W as anything in C.whens)
		. |= list(W.args["cond"])
		. |= slot_scope_stat_reads(T, W.args["cond"])
	var/datum/entry/E = C.item
	for(var/read in E.args?["reads"])
		. |= read

/// One on_change hook per input of the type's condition-scoped entries (each added once: a subtype's table, copied from its parent's, already
/// carries its parent's).
/proc/table_cond_gates(datum/type_table/T)
	var/list/have = null
	for(var/datum/centry/C as anything in T.items)
		if(istext(C.eff_key) && findtext(C.eff_key, "cond_gate:") == 1)
			LAZYSET(have, C.eff_key, TRUE)
	for(var/datum/centry/C as anything in cond_scoped_entries(T))
		var/datum/entry/E = C.item
		var/list/inputs = cond_scope_inputs(C, T)
		for(var/i in 1 to length(inputs))
			var/gate_key = "cond_gate:[E.sig]:[i]"
			if(LAZYACCESS(have, gate_key))
				continue
			LAZYSET(have, gate_key, TRUE)
			table_add_item(T, on_change(inputs[i], ANY, then(GLOBAL_PROC_REF(activations_cond_regate_hook))), C.origin, null, null, gate_key)
