// vars_write (doc/rewrite/final_api.html, section 4 "Reflection writes"; section 5; section 19 "E3, stats").
//
//	vars_write(E, name, value, source = SRC_VV)   the one by-name write: VV, SDQL, state serializers, the map loader, DNA and record copy
//
// A stat's name writes a hold_override sourced `source` at PRIORITY_ADMIN (released by releasing that source), so an admin's VV edit of a stat is
// one more contribution that wins and can be taken back. A tracked var goes through its schema (clamped or refused, logged) and its setter. Any
// other var is refused: a name the build cannot resolve is not written blind.

/// Writes var `name` of E by name. Returns TRUE when it was written (or the override placed), FALSE when refused (reported).
/proc/vars_write(datum/E, name, value, source = SRC_VV)
	if(!isdatum(E) || QDELETED(E) || !istext(name))
		return FALSE
	var/datum/stat_def/def = stat_def_named(name)
	if(def && stat_declared_on(E.type, def))
		if(def.keyed)
			declare_report("vars_write([E.type], [name]): a SUM_PER_KEY stat has no override: hold or release a key")
			return FALSE
		if(def.rule == STAT_RULE_SET)
			declare_report("vars_write([E.type], [name]): a SET stat has no override: grant or revoke instead")
			return FALSE
		var/value_to_hold = value
		if(def.schema && !stat_rule_is_boolean(def.rule))
			var/list/checked = schema_input(def.schema, value, E)
			if(checked[1] == SCHEMA_REJECT)
				declare_report("vars_write([E.type], [name]): [checked[2]]")
				return FALSE
			value_to_hold = checked[1]
		TEST_REC_DELTA(E, "vars_write:[name]", null, value_to_hold)
		return !!hold_override(E, def.id, value_to_hold, source)
	if(!(name in E.vars))
		declare_report("vars_write([E.type], [name]): no such var")
		return FALSE
	var/written = schema_write(E, name, value)
	if(written == SCHEMA_REJECT)
		return FALSE
	var/old = E.vars[name]
	if(old == written)
		return TRUE
	E.vars[name] = written // ALLOW(api): vars_write is the one by-name writer
	TEST_REC_DELTA(E, "vars_write:[name]", old, written)
	state_changed(E, 0, name)
	return TRUE
