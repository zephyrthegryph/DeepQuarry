/*
	Class: scope
	A runtime instance of a block. Used internally by the interpreter.
*/
/datum/scope
	var/tmp/datum/scope/parent_ref
	var/tmp/datum/node/BlockDefinition/block_ref
	var/list/functions
	var/list/variables

CAPABILITIES(/datum/scope)
	owns_many(nameof(functions))
	owns_many(nameof(variables))

/datum/scope/New(datum/node/BlockDefinition/B, datum/scope/parent)
	rel_set(src, nameof(block_ref), B)
	rel_set(src, nameof(parent_ref), parent)
	// The scope owns its variable value nodes: wrap the block's raw initial values.
	for(var/name in B.initial_variables)
		rel_add(src, nameof(variables), script_value_node(B.initial_variables[name]), name)
	// Functions are not copied: find_function() reads the block's own table, and `functions`
	// holds only what the interpreter binds into this scope at runtime (SetProc()).
	.=..()

/// The function (a FunctionDefinition node, or a bound proc path) named `name`, or null.
/datum/scope/proc/find_function(name)
	if(!isnull(LAZYACCESS(functions, name)))
		return functions[name]
	var/datum/node/BlockDefinition/B = block_ref
	return LAZYACCESS(B?.functions, name)

/// Whether a function named `name` is visible in this scope.
/datum/scope/proc/has_function(name)
	if(name in functions)
		return TRUE
	var/datum/node/BlockDefinition/B = block_ref
	return B && (name in B.functions)

/// Wraps a raw script value in an expression node (a literal, or a reference to an object)
/// so an owned variable table holds nodes it made, never the objects themselves.
/proc/script_value_node(value)
	if(istype(value, /datum))
		return new /datum/node/expression/value/reference(value)
	return new /datum/node/expression/value/literal(value)

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/scope/proc/parent() as /datum/scope
	return parent_ref

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/scope/proc/block_node() as /datum/node/BlockDefinition
	return block_ref

