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
	var/datum/node/identifier/object
	var/list/parameters=list()

/*
	Class: FunctionDefinition
	Defines a function.
*/
//
/datum/node/statement/FunctionDefinition
	var/func_name
	var/list/parameters=list()
	var/datum/node/BlockDefinition/FunctionBlock/block

/*
	Class: VariableAssignment
	Sets a variable in an accessible scope to the given value if one exists, otherwise initializes a new local variable to the given value.

	Notes:
	If a variable with the same name exists in a higher block, the value will be assigned to it. If not,
	a new variable is created in the current block. To force creation of a new variable, use <VariableDeclaration>.

	See Also:
	- <VariableDeclaration>
*/
//
/datum/node/statement/VariableAssignment
	var/datum/node/identifier/object
	var/datum/node/identifier/var_name
	var/datum/node/expression/value

/*
	Class: VariableDeclaration
	Intializes a local variable to a null value.

	See Also:
	- <VariableAssignment>
*/
//
/datum/node/statement/VariableDeclaration
	var/datum/node/identifier/object
	var/var_name_handle

/*
	Class: IfStatement
*/
//
/datum/node/statement/IfStatement
	var/datum/node/BlockDefinition/block
	var/datum/node/BlockDefinition/else_block // may be null
	var/datum/node/expression/cond

/*
	Class: WhileLoop
	Loops while a given condition is true.
*/
//
/datum/node/statement/WhileLoop
	var/datum/node/BlockDefinition/block
	var/datum/node/expression/cond

/*
	Class: ForLoop
	Loops while test is true, initializing a variable, increasing the variable
*/
/datum/node/statement/ForLoop
	var/datum/node/BlockDefinition/block
	var/test_handle
	var/init_handle
	var/increment_handle

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

REF_OWNED(/datum/node/statement/FunctionDefinition, "block")

REF_OWNED(/datum/node/statement/VariableAssignment, list("var_name", "value"))

REF_OWNED(/datum/node/statement/IfStatement, list("block", "else_block", "cond"))

REF_OWNED(/datum/node/statement/WhileLoop, list("block", "cond"))

REF_OWNED(/datum/node/statement/ReturnStatement, "value")

/// LC-refs: the var_name this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/node/statement/VariableDeclaration/proc/var_name() as /datum/node/identifier
	return om_resolve(var_name_handle)

/// LC-refs: the test this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/node/statement/ForLoop/proc/test() as /datum/node/expression
	return om_resolve(test_handle)

/// LC-refs: the init this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/node/statement/ForLoop/proc/init() as /datum/node/expression
	return om_resolve(init_handle)

/// LC-refs: the increment this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/node/statement/ForLoop/proc/increment() as /datum/node/expression
	return om_resolve(increment_handle)
