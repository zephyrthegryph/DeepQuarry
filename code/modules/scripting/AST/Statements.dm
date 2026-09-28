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
	var/tmp/datum/node/identifier/object_owned
	var/list/parameters=list() // ALLOW(instance_list): d: script AST node state

/*
	Class: FunctionDefinition
	Defines a function.
*/
//
/datum/node/statement/FunctionDefinition
	var/func_name
	var/list/parameters=list() // ALLOW(instance_list): d: script AST node state
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
	var/tmp/datum/node/identifier/object_owned
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
	var/tmp/datum/node/identifier/object_owned
	var/tmp/datum/node/identifier/var_name_owned

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
	var/tmp/datum/node/BlockDefinition/block_owned
	var/tmp/datum/node/expression/test_owned
	var/tmp/datum/node/expression/init_owned
	var/tmp/datum/node/expression/increment_owned

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

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/VariableDeclaration/proc/var_name() as /datum/node/identifier
	return var_name_owned
REF_OWNED(/datum/node/statement/VariableDeclaration, "var_name_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/ForLoop/proc/test() as /datum/node/expression
	return test_owned
REF_OWNED(/datum/node/statement/ForLoop, "test_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/ForLoop/proc/init() as /datum/node/expression
	return init_owned
REF_OWNED(/datum/node/statement/ForLoop, "init_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/ForLoop/proc/increment() as /datum/node/expression
	return increment_owned
REF_OWNED(/datum/node/statement/ForLoop, "increment_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/FunctionCall/proc/object() as /datum/node/identifier
	return object_owned
REF_OWNED(/datum/node/statement/FunctionCall, "object_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/VariableAssignment/proc/object() as /datum/node/identifier
	return object_owned
REF_OWNED(/datum/node/statement/VariableAssignment, "object_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/VariableDeclaration/proc/object() as /datum/node/identifier
	return object_owned
REF_OWNED(/datum/node/statement/VariableDeclaration, "object_owned")

/// REF_OWNED: created for and owned by this holder; deleted with it.
/datum/node/statement/ForLoop/proc/block_node() as /datum/node/BlockDefinition
	return block_owned
REF_OWNED(/datum/node/statement/ForLoop, "block_owned")
