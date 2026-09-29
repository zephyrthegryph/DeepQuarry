/*
	Class: scope
	A runtime instance of a block. Used internally by the interpreter.
*/
/datum/scope
	var/tmp/datum/scope/parent_ref
	var/tmp/datum/node/BlockDefinition/block_ref
	var/list/functions
	var/list/variables

/datum/scope/New(datum/node/BlockDefinition/B, datum/scope/parent)
	rel_set(src, "block_ref", B)
	rel_set(src, "parent_ref", parent)
	src.variables = LAZYCOPY(B.initial_variables)
	src.functions = B.functions.Copy()
	.=..()

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/scope/proc/parent() as /datum/scope
	return parent_ref

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/scope/proc/block_node() as /datum/node/BlockDefinition
	return block_ref

