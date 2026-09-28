/*
	Class: scope
	A runtime instance of a block. Used internally by the interpreter.
*/
/datum/scope
	var/parent_handle
	var/block_handle
	var/list/functions
	var/list/variables

/datum/scope/New(datum/node/BlockDefinition/B, datum/scope/parent)
	src.block_handle = om_handle(B)
	src.parent_handle = om_handle(parent)
	src.variables = LAZYCOPY(B.initial_variables)
	src.functions = B.functions.Copy()
	.=..()

/// LC-refs: the parent this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/scope/proc/parent() as /datum/scope
	return om_resolve(parent_handle)

/// LC-refs: the block this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/scope/proc/block() as /datum/node/BlockDefinition
	return om_resolve(block_handle)
