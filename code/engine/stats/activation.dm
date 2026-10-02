// The contributions of a granted capability (doc/rewrite/final_api.html, section 11 "Definition, activation, contributions"; section 16.9;
// section 19 "E3, stats").
//
// A capability that is granted at runtime (a species, a slot, an op's grants()) brings its contributes() entries with it, one set per activation: the
// phased capability of 16.9 holds density FALSE, the shadekin invisibility and the origin mask on the shifter while the shift lasts. They apply
// at once when the activation attaches and go in the same step when it ends, so the stat is right on the line after the grant and after the revoke.
//
// A contribution of an activation is a hold on the holder's stat, with the activation as its source and the entry's priority and reason: the stat's
// own rule combines it with everything else, one contribution per activation, whatever the capability's stacking policy says (stacking decides which
// activations' behaviour runs, never which contribute). The value is a constant, because an activation brings no declared inputs of its own: a
// contribution that reads a var, a stat, a capability key or a holder proc, or that sits inside a when() block, is a type-level one (the holder's
// CAPABILITIES list), which the compiled table of the type recomputes when its reads change.

/datum/entry_engine/stat_contributes
	kind = "contributes"

/// Validation runs before the scope is known (a type-level activation brings dynamic contributions that its holder's table already compiled), so
/// the kinds of value a grant cannot bring are refused in apply().
/datum/entry_engine/stat_contributes/validate(datum/activation/A, datum/entry/E)
	if(!stat_def_of(E.args["stat"]))
		return "contributes(): [E.args["stat"]] is not a declared stat"
	return null

/datum/entry_engine/stat_contributes/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	if(A.scope == SCOPE_TYPE)
		return FALSE // the holder's own type declares it: it is in the compiled table already
	if(length(C?.whens))
		declare_report("[A.def.key] on [A.holder?.type]: a contributes() inside when() cannot be granted: the condition is an input of the stat, and a grant brings none")
		return FALSE
	var/spec = E.args["value"]
	if(islist(spec) || (isnum(spec) && (stat_def_of(spec) || spec >= CAPKEY_ID_BASE)) || (istext(spec) && length(spec)))
		declare_report("[A.def.key] on [A.holder?.type]: a granted capability's contributes() takes a constant value; a var, stat, key or proc read belongs in the holder's own CAPABILITIES list")
		return FALSE
	return !!hold(A.holder, E.args["stat"], spec, A, null, E.args["priority"], null, E.args["reason"])

/datum/entry_engine/stat_contributes/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(holder && !QDELETED(holder))
		release(holder, E.args["stat"], A)
