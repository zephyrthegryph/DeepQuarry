/*
	Class: scope
	A runtime instance of a block. Used internally by the interpreter.
*/
/datum/scope
	var/datum/scope/parent = null
	var/datum/node/BlockDefinition/block
	var/list/functions
	var/list/variables

/datum/scope/New(datum/node/BlockDefinition/B, datum/scope/parent)
	src.block = B
	src.parent = parent
	src.variables = LAZYCOPY(B.initial_variables)
	src.functions = B.functions.Copy()
	.=..()
