// Requirement clauses over the target's state (doc/rewrite/systems.md section 6).
// Declarations: code/__defines/sys_requirements.dm. The predicate compiler
// (code/datums/properties/predicates.dm) hands these opcodes to compile_requirement().
//
// Every node reads the interaction's target, allocates nothing on success, and builds its reason
// only on failure. Reasons are generated from the field name and the value that failed unless
// the declaration gave one.

/// Compiles the section-6 clauses. Returns a node, or null after reporting an error.
/datum/predicate_compiler/compile_requirement(list/clause, negate)
	switch(clause[1])
		if(PRED_OP_FIELD)
			// field, name, mode, value[, reason]
			if(length(clause) != 4 && length(clause) != 5)
				error("REQ_FIELD clause has [length(clause)] parts, expected 4 or 5")
				return null
			var/name = clause[2]
			if(!istext(name) || !length(name))
				error("REQ_FIELD needs a field name")
				return null
			var/mode = clause[3]
			if(mode != REQ_FIELD_MODE_TRUE && mode != REQ_FIELD_MODE_EQ)
				error("REQ_FIELD has unknown mode [mode]")
				return null
			var/reason = length(clause) == 5 ? clause[5] : null
			if(!isnull(reason) && !istext(reason))
				error("REQ_FIELD([name])'s reason must be text")
				return null
			var/datum/pred_node/field/node = leaf(/datum/pred_node/field, negate)
			node.field = name
			node.mode = mode
			node.value = clause[4]
			node.reason_text = reason
			return node
		if(PRED_OP_ACCESS)
			if(!arity(clause, 1))
				return null
			return leaf(/datum/pred_node/access, negate)
		if(PRED_OP_EMAGGED)
			if(!arity(clause, 1))
				return null
			return leaf(/datum/pred_node/emagged, negate)
		if(PRED_OP_ANCHORED)
			if(!arity(clause, 1))
				return null
			return leaf(/datum/pred_node/anchored, negate)
		if(PRED_OP_PANEL)
			if(!arity(clause, 2))
				return null
			var/datum/pred_node/panel/node = leaf(/datum/pred_node/panel, negate)
			node.open = clause[2] ? TRUE : FALSE
			return node
	error("unknown clause [clause[1]]")
	return null

/// How `field` is read on `thing`'s type: REQ_FIELD_READ_VAR, REQ_FIELD_READ_PROC, or null when
/// the type has neither (a declaration error, reported once per type and field).
/proc/dq_req_field_access(datum/thing, field)
	var/static/list/access_by_type = list()
	var/key = "[thing.type]|[field]"
	. = access_by_type[key]
	if(.)
		return . == "none" ? null : .
	if(field in thing.vars)
		. = "var"
	else if(hascall(thing, field))
		. = "proc"
	else
		stack_trace("REQ_FIELD: [thing.type] has no var or derived field named [field]")
		. = "none"
	access_by_type[key] = .
	return . == "none" ? null : .

/// The current value of `thing`'s field `field` (a var, or a derived field's proc), or null.
/proc/dq_req_field_value(datum/thing, field)
	if(!thing)
		return null
	switch(dq_req_field_access(thing, field))
		if("var")
			return thing.vars[field]
		if("proc")
			return call(thing, field)()
	return null

/// A field's truth: an empty list counts as false ("has no X"), like null, 0 and "".
/proc/dq_req_truthy(value)
	if(islist(value))
		var/list/L = value
		return length(L) ? TRUE : FALSE
	return value ? TRUE : FALSE

/// "panel_open" -> "panel open".
/proc/dq_req_field_words(field)
	return replacetext(field, "_", " ")

/datum/pred_node/field
	/// The target's var or derived-field name.
	var/field
	/// REQ_FIELD_MODE_*.
	var/mode
	/// REQ_FIELD_EQ's value.
	var/value

/datum/pred_node/field/test(mob/actor, atom/target, obj/item/held)
	if(!target)
		return FALSE
	var/current = dq_req_field_value(target, field)
	if(mode == REQ_FIELD_MODE_EQ)
		return current == value
	return dq_req_truthy(current)

/datum/pred_node/field/generate_reason(mob/actor, atom/target, obj/item/held)
	var/words = dq_req_field_words(field)
	var/current = target ? dq_req_field_value(target, field) : null
	if(mode == REQ_FIELD_MODE_EQ)
		return negate ? "its [words] must not be [value]" : "its [words] must be [value]"
	if(negate)
		// It must be falsy but isn't.
		if(isatom(current))
			var/atom/thing = current
			return "it already has \a [thing]"
		return "it's [words]"
	if(isnull(current) || islist(current))
		return "it has no [words]"
	return "it isn't [words]"

/datum/pred_node/access/test(mob/actor, atom/target)
	if(!actor || !isobj(target))
		return FALSE
	var/obj/thing = target
	return thing.allowed(actor) ? TRUE : FALSE

/datum/pred_node/access/generate_reason()
	return negate ? "you have its access" : "access denied"

/datum/pred_node/emagged/test(mob/actor, atom/target)
	return dq_req_field_value(target, "emagged") ? TRUE : FALSE

/datum/pred_node/emagged/generate_reason()
	// REQ_NOT_EMAGGED negates: failing means it is emagged.
	return negate ? "its controls have been tampered with" : "it isn't emagged"

/datum/pred_node/anchored/test(mob/actor, atom/target)
	if(!ismovable(target))
		return TRUE // turfs and areas don't move
	var/atom/movable/thing = target
	return thing.anchored ? TRUE : FALSE

/datum/pred_node/anchored/generate_reason()
	return negate ? "unanchor it first" : "it must be anchored first"

/datum/pred_node/panel
	/// TRUE: the panel must be open; FALSE: closed.
	var/open = TRUE

/datum/pred_node/panel/test(mob/actor, atom/target)
	var/is_open = dq_req_field_value(target, "panel_open") ? TRUE : FALSE
	return is_open == open

/datum/pred_node/panel/generate_reason()
	// With negate, the declared state is the one that must not hold.
	var/wants_open = (open != negate)
	return wants_open ? "open the maintenance panel first" : "close the maintenance panel first"
