/*
	File: Interpreter (Public)
	Contains methods for interacting with the interpreter.
*/
/*
	Class: n_Interpreter
	Procedures allowing for interaction with the script that is being run by the interpreter object.
*/
/datum/n_Interpreter

/*
	Proc: Load
	Loads a 'compiled' script into memory.

	Parameters:
	program - A <GlobalBlock> object which represents the script's global scope.
*/
/datum/n_Interpreter/proc/Load(datum/node/BlockDefinition/GlobalBlock/program)
	ASSERT(program)
	rel_set(src, nameof(program), program)
	CreateGlobalScope()

/*
	Proc: Run
	Runs the script.
*/
/datum/n_Interpreter/proc/Run()
	cur_recursion = 0 // reset recursion
	cur_statements = 0 // reset CPU tracking
	alertadmins = 0

	ASSERT(src.program)
	RunBlock(src.program)

/*
	Proc: SetVar
	Defines a global variable for the duration of the next execution of a script.

	Notes:
	This differs from <Block.SetVar()> in that variables set using this procedure only last for the session,
	while those defined from the block object persist if it is ran multiple times.

	See Also:
	- <Block.SetVar()>
*/
/datum/n_Interpreter/proc/SetVar(name, value)
	if(!istext(name))
		return
	AssignVariable(name, value)

/*
	Proc: SetProc
	Defines a procedure to be available to the script.

	Parameters:
	name 		- The name of the procedure as exposed to the script.
	path 		- The typepath of a proc to be called when the function call is read by the interpreter, or, if object is specified, a string representing the procedure's name.
	object	- (Optional) An object which will the be target of a function call.
	params 	- Only required if object is not null, a list of the names of parameters the proc takes.
*/
/datum/n_Interpreter/proc/SetProc(name, path, object=null, list/params=null)
	if(!istext(name))
		return
	if(!object)
		own_put(globalScope, nameof(globalScope.functions), name, path) // a proc path: plain data in the owned lookup
		return
	var/datum/node/statement/FunctionDefinition/S = new()
	S.func_name		= name
	S.parameters	= params
	rel_set(S, nameof(S.block), new /datum/node/BlockDefinition/FunctionBlock())
	S.block.SetVar("src", object)
	var/datum/node/expression/FunctionCall/C = new()
	C.func_name	= path
	rel_set(C, nameof(C.object), new /datum/node/identifier("src"))
	for(var/p in params)
		own_add(C, nameof(C.parameters), new/datum/node/expression/value/variable(p))
	var/datum/node/statement/ReturnStatement/R=new()
	rel_set(R, nameof(R.value), C)
	LAZYADD(S.block.statements, R)
	own_put(globalScope, nameof(globalScope.functions), name, S)
/*
	Proc: VarExists
	Checks whether a global variable with the specified name exists.
*/
/datum/n_Interpreter/proc/VarExists(name)
	return (name in globalScope.variables) //convert to 1/0 first?

/*
	Proc: ProcExists
	Checks whether a global function with the specified name exists.
*/
/datum/n_Interpreter/proc/ProcExists(name)
	return globalScope.has_function(name)

/*
	Proc: GetVar
	Returns the value of a global variable in the script. Remember to ensure that the variable exists before calling this procedure.

	See Also:
	- <VarExists()>
*/
/datum/n_Interpreter/proc/GetVar(name)
	if(!VarExists(name))
		return
	var/x = LAZYACCESS(globalScope.variables, name)
	return Eval(x)

/*
	Proc: CallProc
	Calls a global function defined in the script and, amazingly enough, returns its return value. Remember to ensure that the function
	exists before calling this procedure.

	See Also:
	- <ProcExists()>
*/
/datum/n_Interpreter/proc/CallProc(name, params[]=null)
	if(!ProcExists(name))
		return
	var/datum/node/statement/FunctionDefinition/func = globalScope.find_function(name)
	if(istype(func))
		var/datum/node/statement/FunctionCall/stmt = new
		stmt.func_name  = func.func_name
		// The call owns its argument nodes: wrap each raw value (Eval() unwraps them again).
		for(var/p in params)
			own_add(stmt, nameof(stmt.parameters), script_value_node(p))
		return RunFunction(stmt)
	else
		return call(func)(arglist(params))

/*
	Event: HandleError
	Called when the interpreter throws a runtime error.

	See Also:
	- <runtimeError>
*/
/datum/n_Interpreter/proc/HandleError(datum/runtimeError/e)
