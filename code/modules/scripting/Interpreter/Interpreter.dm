/*
	File: Interpreter (Internal)
*/
/*
	Class: n_Interpreter
*/
/*
	Macros: Status Macros
	RETURNING  - Indicates that the current function is returning a value.
	BREAKING   - Indicates that the current loop is being terminated.
	CONTINUING - Indicates that the rest of the current iteration of a loop is being skipped.
*/
#define RETURNING  1
#define BREAKING   2
#define CONTINUING 4
/datum/n_Interpreter
	var/tmp/datum/scope/curScope_ref
	var/datum/scope/globalScope
	var/datum/node/BlockDefinition/program
	var/tmp/datum/node/statement/FunctionDefinition/curFunction_ref
	var/datum/stack/scopes	= new()
	var/datum/stack/functions	= new()

	var/tmp/datum/container	// associated container for interpeter
/*
	Var: status
	A variable indicating that the rest of the current block should be skipped. This may be set to any combination of <Status Macros>.
*/
	var/status=0
	var/returnVal

	var/max_statements=1000 // maximum amount of statements that can be called in one execution. this is to prevent massive crashes and exploitation
	var/cur_statements=0    // current amount of statements called
	var/alertadmins=0		// set to 1 if the admins shouldn't be notified of anymore issues
	var/max_iterations=100 	// max number of uninterrupted loops possible
	var/max_recursion=50   	// max recursions without returning anything (or completing the code block)
	var/cur_recursion=0	   	// current amount of recursion
/*
	Var: persist
	If 0, global variables will be reset after Run() finishes.
*/
	var/persist=1
/*
	Var: yield_for
	Set by the script's sleep() (deciseconds): the run unwinds after the current statement, leaving
	its continuation in <resume_frames>, and Resume() carries on from there later. Nothing sleeps:
	the owner runs Resume() as a task step (TCS_Compiler).
*/
	var/yield_for
/*
	Var: resume_frames
	A suspended run's continuation, outermost first: list("block", block, next index, scope),
	list("while", stmt, next iteration) and list("func") (a script function's return handling).
*/
	var/list/resume_frames
	/// Where the frames of the current unwind go (just after the frames still pending from before).
	var/unwind_at

CAPABILITIES(/datum/n_Interpreter)
	owns_one(nameof(globalScope), /datum/scope)
	owns_one(nameof(program), /datum/node/BlockDefinition)

/*
	Constructor: New
	Calls <Load()> with the given parameters.
*/
/datum/n_Interpreter/New(datum/node/BlockDefinition/GlobalBlock/program=null)
	.=..()
	if(program)Load(program)

/*
	Proc: RaiseError
	Raises a runtime error.
*/
/datum/n_Interpreter/proc/RaiseError(datum/runtimeError/e)
	rel_set(e, nameof(e.stack), functions.Copy())
	e.stack.Push(curFunction())
	src.HandleError(e)

/datum/n_Interpreter/proc/CreateScope(datum/node/BlockDefinition/B)
	var/datum/scope/S = new(B, curScope())
	scopes.Push(curScope())
	rel_set(src, nameof(curScope_ref), S)
	return S

/datum/n_Interpreter/proc/CreateGlobalScope()
	scopes.Clear()
	var/datum/scope/S = new(program, null)
	rel_set(src, nameof(globalScope), S)
	return S

/*
Proc: RunBlock
Runs each statement in a block of code.
*/
/datum/n_Interpreter/proc/RunBlock(datum/node/BlockDefinition/Block, datum/scope/scope = null)
	var/is_global = istype(Block, /datum/node/BlockDefinition/GlobalBlock)
	if(!is_global)
		if(scope)
			rel_set(src, nameof(curScope_ref), scope)
		else
			CreateScope(Block)
	else
		if(!persist)
			CreateGlobalScope()
		rel_set(src, nameof(curScope_ref), globalScope)

	RunStatements(Block, 1)

	rel_set(src, nameof(curScope_ref), scopes.Pop())

/// The script's sleep(time): suspends the run after the current statement (see <yield_for>).
/datum/n_Interpreter/proc/script_sleep(time)
	yield_for = max(isnum(time) ? time : text2num(time), 0)
	unwind_at = length(resume_frames) + 1

/// Records one frame of the continuation while a suspended run unwinds (innermost first).
/datum/n_Interpreter/proc/PushResume(list/frame)
	LAZYINITLIST(resume_frames)
	resume_frames.Insert(unwind_at, null)
	resume_frames[unwind_at] = frame

/// Carries on a suspended run. TRUE when the script finished, FALSE when it sleeps again.
/datum/n_Interpreter/proc/Resume()
	yield_for = null
	while(length(resume_frames))
		var/list/frame = resume_frames[length(resume_frames)]
		resume_frames.len--
		switch(frame[1])
			if("block")
				scopes.Push(curScope())
				rel_set(src, nameof(curScope_ref), frame[4])
				RunStatements(frame[2], frame[3])
				rel_set(src, nameof(curScope_ref), scopes.Pop())
			if("while")
				RunWhile(frame[2], frame[3], frame[3] - 1)
			if("func")
				FinishFunction()
		if(!isnull(yield_for))
			return FALSE
	return TRUE

/// TRUE while a run is suspended (its script sleeps).
/datum/n_Interpreter/proc/IsSuspended()
	return !isnull(yield_for) || length(resume_frames)

/// Runs `Block`'s statements from `index` in the current scope; a sleep() leaves a "block" frame.
/datum/n_Interpreter/proc/RunStatements(datum/node/BlockDefinition/Block, index)
	if(cur_statements < max_statements)

		for(var/i in index to length(Block.statements))
			var/datum/node/statement/S = Block.statements[i]
			if(!isnull(yield_for))
				PushResume(list("block", Block, i, curScope()))
				return

			cur_statements++
			if(cur_statements >= max_statements)
				RaiseError(new/datum/runtimeError/MaxCPU())

				if(container() && !alertadmins)
					if(istype(container(), /datum/TCS_Compiler))
						var/datum/TCS_Compiler/Compiler = container()
						var/obj/machinery/telecomms/server/Holder = Compiler.Holder()
						var/message = "Potential crash-inducing NTSL script detected at telecommunications server [Compiler.Holder()] ([Holder.x], [Holder.y], [Holder.z])."

						alertadmins = 1
						message_admins(message, 1)
				break

			if(istype(S, /datum/node/statement/VariableAssignment))
				var/datum/node/statement/VariableAssignment/stmt = S
				var/name = stmt.var_name.id_name
				if(!stmt.object())
					// Below we assign the variable first to null if it doesn't already exist.
					// This is necessary for assignments like +=, and when the variable is used in a function
					// If the variable already exists in a different block, then AssignVariable will automatically use that one.
					if(!IsVariableAccessible(name))
						AssignVariable(name, null)
					AssignVariable(name, Eval(stmt.value))
				else
					var/datum/D = Eval(GetVariable(stmt.object().id_name))
					if(!D) return
					D.vars[stmt.var_name.id_name] = Eval(stmt.value) // ALLOW(api): NTSL interpreter: script assigns vars by name
			else if(istype(S, /datum/node/statement/VariableDeclaration))
				//VariableDeclaration nodes are used to forcibly declare a local variable so that one in a higher scope isn't used by default.
				var/datum/node/statement/VariableDeclaration/dec=S
				if(!dec.object())
					AssignVariable(dec.var_name().id_name, null, curScope())
				else
					var/datum/D = Eval(GetVariable(dec.object().id_name))
					if(!D) return
					D.vars[dec.var_name().id_name] = null // ALLOW(api): NTSL interpreter: script assigns vars by name
			else if(istype(S, /datum/node/statement/FunctionCall))
				RunFunction(S)
			else if(istype(S, /datum/node/statement/FunctionDefinition))
				pass() //do nothing
			else if(istype(S, /datum/node/statement/WhileLoop))
				RunWhile(S)
			else if(istype(S, /datum/node/statement/IfStatement))
				RunIf(S)
			else if(istype(S, /datum/node/statement/ReturnStatement))
				if(!curFunction())
					RaiseError(new/datum/runtimeError/UnexpectedReturn())
					continue
				status |= RETURNING
				returnVal=Eval(S:value)
				break
			else if(istype(S, /datum/node/statement/BreakStatement))
				status |= BREAKING
				break
			else if(istype(S, /datum/node/statement/ContinueStatement))
				status |= CONTINUING
				break
			else
				RaiseError(new/datum/runtimeError/UnknownInstruction())
			if(!isnull(yield_for))
				PushResume(list("block", Block, i + 1, curScope()))
				return
			if(status)
				break

/*
Proc: RunFunction
Runs a function block or a proc with the arguments specified in the script.
*/
/datum/n_Interpreter/proc/RunFunction(datum/node/statement/FunctionCall/stmt)
	//Note that anywhere /node/statement/FunctionCall/stmt is used so may /node/expression/FunctionCall

	// If recursion gets too high (max 50 nested functions) throw an error
	if(cur_recursion >= max_recursion)
		RaiseError(new/datum/runtimeError/RecursionLimitReached())
		return 0

	var/datum/node/statement/FunctionDefinition/def
	if(!stmt.object())							//A scope's function is being called, stmt.object is null
		def = GetFunction(stmt.func_name)
	else if(istype(stmt.object(), /datum/node/identifier))				//A method of an object exposed as a variable is being called, stmt.object is a /node/identifier
		var/O = GetVariable(stmt.object().id_name)	//Gets a reference to the object which is the target of the function call.
		if(!O) return							//Error already thrown in GetVariable()
		def = Eval(O)

	if(!def) return

	cur_recursion++ // add recursion
	if(istype(def))
		if(curFunction()) functions.Push(curFunction())
		var/datum/scope/S = CreateScope(def.block)
		for(var/i=1 to def.parameters.len)
			var/val
			if(stmt.parameters.len>=i)
				val = stmt.parameters[i]
			//else
			//	unspecified param
			AssignVariable(def.parameters[i], new/datum/node/expression/value/literal(Eval(val)), S)
		rel_set(src, nameof(curFunction_ref), stmt)
		RunBlock(def.block, S)
		if(!isnull(yield_for))
			PushResume(list("func")) // the return handling runs when the run resumes
			return
		//Handle return value
		. = returnVal
		FinishFunction()
	else
		cur_recursion--
		var/list/params=new
		for(var/datum/node/expression/P in stmt.parameters)
			params+=list(Eval(P))
		if(isobject(def))	//def is an object which is the target of a function call
			if( !hascall(def, stmt.func_name) )
				RaiseError(new/datum/runtimeError/UndefinedFunction("[stmt.object().id_name].[stmt.func_name]"))
				return
			return call(def, stmt.func_name)(arglist(params))
		else										//def is a path to a global proc
			return call(def)(arglist(params))

/*
Proc: RunIf
Checks a condition and runs either the if block or else block.
*/
/datum/n_Interpreter/proc/RunIf(datum/node/statement/IfStatement/stmt)
	if(Eval(stmt.cond))
		RunBlock(stmt.block)
	else if(stmt.else_block)
		RunBlock(stmt.else_block)

/// A script function's return handling (after its block, or when a suspended run resumes).
/datum/n_Interpreter/proc/FinishFunction()
	status &= ~RETURNING
	returnVal=null
	rel_set(src, nameof(curFunction_ref), functions.Pop())
	cur_recursion--

/*
Proc: RunWhile
Runs a while loop. `finishing`: resuming a run suspended in that iteration, which is accounted
for before the loop carries on.
*/
/datum/n_Interpreter/proc/RunWhile(datum/node/statement/WhileLoop/stmt, i = 1, finishing = 0)
	if(!finishing || IterationDone(finishing))
		while(Eval(stmt.cond) && Iterate(stmt.block, i++))
			continue
		if(!isnull(yield_for))
			PushResume(list("while", stmt, i))
			return
	status &= ~BREAKING

/*
Proc:Iterate
Runs a single iteration of a loop. Returns a value indicating whether or not to continue looping.
*/
/datum/n_Interpreter/proc/Iterate(datum/node/BlockDefinition/block, count)
	RunBlock(block)
	if(!isnull(yield_for))
		return 0
	return IterationDone(count)

/// The checks after a loop iteration: FALSE ends the loop.
/datum/n_Interpreter/proc/IterationDone(count)
	if(max_iterations > 0 && count >= max_iterations)
		RaiseError(new/datum/runtimeError/IterationLimitReached())
		return 0
	if(status & (BREAKING|RETURNING))
		return 0
	status &= ~CONTINUING
	return 1

/*
Proc: GetFunction
Finds a function in an accessible scope with the given name. Returns a <FunctionDefinition>.
*/
/datum/n_Interpreter/proc/GetFunction(name)
	var/datum/scope/S = curScope()
	while(S)
		if(S.has_function(name))
			return S.find_function(name)
		S = S.parent()
	RaiseError(new/datum/runtimeError/UndefinedFunction(name))

/*
Proc: GetVariable
Finds a variable in an accessible scope and returns its value.
*/
/datum/n_Interpreter/proc/GetVariable(name)
	var/datum/scope/S = curScope()
	while(S)
		if((name in S.variables))
			return S.variables[name]
		S = S.parent()
	RaiseError(new/datum/runtimeError/UndefinedVariable(name))

/datum/n_Interpreter/proc/GetVariableScope(name) //needed for when you reassign a variable in a higher scope
	var/datum/scope/S = curScope()
	while(S)
		if((name in S.variables))
			return S
		S = S.parent()


/datum/n_Interpreter/proc/IsVariableAccessible(name)
	var/datum/scope/S = curScope()
	while(S)
		if((name in S.variables))
			return TRUE
		S = S.parent()
	return FALSE


/*
Proc: AssignVariable
Assigns a value to a variable in a specific block.

Parameters:
name  - The name of the variable to assign.
value - The value to assign to it.
S     - The scope the variable resides in. If it is null, a scope with the variable already existing is found. If no scopes have a variable of the given name, the current scope is used.
*/
/datum/n_Interpreter/proc/AssignVariable(name, datum/node/expression/value, datum/scope/S=null)
	if(!S) S = GetVariableScope(name)
	if(!S) S = curScope()
	if(!S) S = globalScope
	ASSERT(istype(S))
	if(istext(value) || isnum(value) || isnull(value))	value = new/datum/node/expression/value/literal(value)
	else if(!istype(value) && isobject(value))			value = new/datum/node/expression/value/reference(value)
	//TODO: check for invalid name
	own_put(S, nameof(S.variables), "[name]", value)

#undef RETURNING
#undef BREAKING
#undef CONTINUING


/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/n_Interpreter/proc/curFunction() as /datum/node/statement/FunctionDefinition
	return curFunction_ref

/// Associated container for interpeter (a relation view).
/datum/n_Interpreter/proc/container() as /datum
	return container

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/n_Interpreter/proc/curScope() as /datum/scope
	return curScope_ref

// Cursors into scopes and function definitions held by the scope stack and the program tree.
