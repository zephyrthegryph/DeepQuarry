// The purity guard (doc/rewrite/final_api.html, section 9 "Conditions and requirements", section 7 "Outputs"; section 19 "E2, parts").
//
// A condition (when(), a requirement, an on_change gate) and an output (a draw, a UI payload, a derived value) never write, publish or message:
// a menu, a screentip or a refresh reads them any number of times, in any order, and the answer must not depend on how often it was asked.
// The engine evaluates every one inside op_pure_begin() .. op_pure_end() (outputs run under DERIVED_EVAL_BEGIN, the same rule), and each place that
// writes state, publishes a key or a notice, starts an action or an op, places a hold, grants or ends an activation, or speaks to a player checks
// the guard first:
//
//	OP_PURE_GUARD("what it was about to do")
//
// A violation is reported once per distinct text through stack_trace() (a test build fails the run, production logs it) and counted in
// GLOB.op_pure_violations, which a test reads. The guard reports; it does not refuse the write, because a write that ran is already in the world and
// dropping the half of it that follows would leave it inconsistent. The author's fix is to move the work to an effect, an after hook or an output.

/// Depth of condition and requirement evaluation (they nest: a tree of conditions, a requirement that asks another).
GLOBAL_VAR_INIT(op_pure_depth, 0)
/// The violations reported since the list was last cleared (a test reads and clears it).
GLOBAL_LIST_EMPTY(op_pure_violations)
/// A test sets this while it provokes a violation on purpose: the report is counted but is not a runtime.
GLOBAL_VAR_INIT(op_pure_expected, FALSE)

// OP_PURE_ACTIVE and OP_PURE_GUARD are in code/__defines/engine/parts.dm (every file that writes uses them).

/// Condition and requirement evaluation starts: writes, publications and messages are reported until the matching op_pure_end().
/proc/op_pure_begin()
	GLOB.op_pure_depth++

/proc/op_pure_end()
	GLOB.op_pure_depth = max(0, GLOB.op_pure_depth - 1)

/// Reports that `what` was done inside a condition, a requirement or an output.
/proc/op_pure_violation(what)
	var/where = GLOB.op_pure_depth > 0 ? "a condition or requirement" : "an output"
	var/text = "PURITY: [what] inside [where]: conditions and outputs never write, publish or message (move it to an effect, an after hook or an output of its own)"
	if(length(GLOB.op_pure_violations) < 64)
		GLOB.op_pure_violations += text
	if(GLOB.op_pure_expected || (GLOB.derived_evaluating > 0 && !(GLOB.op_pure_depth > 0) && GLOB.derived_write_expected))
		return
	var/static/list/reported = list()
	if(reported[text])
		return
	reported[text] = TRUE
	stack_trace(text)

/// Evaluates `cond` of `holder` as a pure condition: a proc of the holder answering TRUE or FALSE. The one place the engine calls a condition proc by name
/// outside an op context.
/proc/op_pure_call(datum/holder, proc_name, datum/act/A)
	op_pure_begin()
	// A condition that throws must not leave the purity guard up: every write after it would be reported.
	try
		. = isnull(A) ? call(holder, proc_name)() : call(holder, proc_name)(A)
	catch(var/exception/fault)
		op_pure_end()
		throw fault
	op_pure_end()
