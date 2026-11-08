// machinery_misc: lazy state of /obj/machinery (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, machinery_misc, field), write with STATE_SET(A, machinery_misc, field, value), end it with machinery_misc_clear(A).

/datum/machinery_misc_state
	parent_type = /datum/lazy_state
	/// /obj/machinery
	var/gas_dependency_wake_count = 0
	var/heat_output_now = 0
	/// Whole-machine EMP rejection supplied by insulating component materials: lazy state field material_emp_resistance (default 0).
	var/material_emp_resistance = 0
	var/rebuilding
	/// A mapped machine's board while it is still data: the path or VARIANT() its type names, until board() makes the item (null once real).
	var/stock_circuit
	var/recursive_set = FALSE
	var/list/material_component_manifest
