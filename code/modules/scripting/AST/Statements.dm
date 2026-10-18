/*
	File: Statement Types
*/
/*
	Class: statement
	An object representing a single instruction run by an interpreter.
*/
/datum/node/statement
/*
	Class: FunctionCall
	Represents a call to a function.
*/
//
/datum/node/statement/FunctionCall
	var/func_name
	var/list/parameters=list() // ALLOW(instance_list): d: script AST node state

CAPABILITIES(/datum/node/statement/FunctionCall)
	owns_many(nameof(parameters))

/*
	Class: FunctionDefinition
	Defines a function.
*/
//
/datum/node/statement/FunctionDefinition
	var/func_name
	var/list/parameters=list() // ALLOW(instance_list): d: script AST node state
	var/datum/node/BlockDefinition/FunctionBlock/block

CAPABILITIES(/datum/node/statement/FunctionDefinition)
	owns_one(nameof(block), /datum/node/BlockDefinition/FunctionBlock)

/*
	Class: VariableAssignment
	Sets a variable in an accessible scope to the given value if one exists, otherwise initializes a new local variable to the given value.

	Notes:
	If a variable with the same name exists in a higher block, the value will be assigned to it. If not,
	a new variable is created in the current block.

	See Also:
*/
//
/datum/node/statement/VariableAssignment
	var/datum/node/identifier/var_name
	var/datum/node/expression/value

CAPABILITIES(/datum/node/statement/VariableAssignment)
	owns_one(nameof(value), /datum/node/expression)
	owns_one(nameof(var_name), /datum/node/identifier)


/*
	Class: IfStatement
*/
//
/datum/node/statement/IfStatement
	var/datum/node/BlockDefinition/block
	var/datum/node/BlockDefinition/else_block // may be null
	var/datum/node/expression/cond

CAPABILITIES(/datum/node/statement/IfStatement)
	owns_one(nameof(block), /datum/node/BlockDefinition)
	owns_one(nameof(cond), /datum/node/expression)
	owns_one(nameof(else_block), /datum/node/BlockDefinition)

/*
	Class: WhileLoop
	Loops while a given condition is true.
*/
//
/datum/node/statement/WhileLoop
	var/datum/node/BlockDefinition/block
	var/datum/node/expression/cond

CAPABILITIES(/datum/node/statement/WhileLoop)
	owns_one(nameof(block), /datum/node/BlockDefinition)
	owns_one(nameof(cond), /datum/node/expression)


/*
	Class: BreakStatement
	Ends a loop.
*/
//
/datum/node/statement/BreakStatement

/*
	Class: ContinueStatement
	Skips to the next iteration of a loop.
*/
//
/datum/node/statement/ContinueStatement

/*
	Class: ReturnStatement
	Ends the function and returns a value.
*/
//
/datum/node/statement/ReturnStatement
	var/datum/node/expression/value

CAPABILITIES(/datum/node/statement/ReturnStatement)
	owns_one(nameof(value), /datum/node/expression)






