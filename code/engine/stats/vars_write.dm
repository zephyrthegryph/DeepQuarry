// vars_write (doc/rewrite/final_api.html, section 4 "Reflection writes"; section 5; section 19 "E3, stats").
//
//	vars_write(E, name, value, source = SRC_VV)   the one by-name write: VV, SDQL, state serializers, the map loader, DNA and record copy
//
// A stat's name writes a hold_override sourced `source` at PRIORITY_ADMIN (released by releasing that source), so an admin's VV edit of a stat is
// one more contribution that wins and can be taken back. A tracked var goes through its schema (clamped or refused, logged) and its setter. Any
// trait field (`@kind.field`, or a var name that moved into a trait block) is written with set_trait(). A declared relation or owned var
// (ref_one, ref_many, owns_one, owns_many, a links() end) goes through rel_set / rel_add, so the reverse index, the owner stamp and the
// publish all happen; a value that is not an entity (or a list of them for a many) is refused. Any other var that exists is written
// directly, through its schema when it has one; a name that is not a var is refused (reported).

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
		// A trait field (`@uses_power.active`, or the old var name `active_power_usage`): the holder's own copy, through set_trait().
		var/list/trait_field = type_trait_field_named(E, name)
		if(trait_field)
			set_trait(E, trait_field[1], trait_field[2], value)
			return TRUE
		declare_report("vars_write([E.type], [name]): no such var")
		return FALSE
	if(rel_kind(E, name))
		return vars_write_relation(E, name, value)
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

/// The relation branch of vars_write(): a one is rel_set (null clears), a many is cleared and refilled member by member (an assoc key stays the key).
/// Refused, with a report, when the value is not an entity (for a many: not null or a list of entities); nothing is changed on a refusal.
/proc/vars_write_relation(datum/E, name, value)
	if(!rel_is_list_shaped(E, name))
		if(!isnull(value) && !isdatum(value))
			declare_report("vars_write([E.type], [name]): a relation holds an entity or null, not [value]")
			return FALSE
		rel_set(E, name, value)
		return TRUE
	if(!isnull(value) && !islist(value))
		declare_report("vars_write([E.type], [name]): a many relation takes null or a list of entities, not [value]")
		return FALSE
	var/list/members = value
	for(var/member in members)
		var/entry_value = istext(member) ? members[member] : member
		if(!isdatum(member) && !isdatum(entry_value))
			declare_report("vars_write([E.type], [name]): a many relation holds entities; [member] is not one")
			return FALSE
	rel_clear(E, name)
	for(var/member in members)
		var/entry_value = istext(member) ? members[member] : member
		if(isdatum(member))
			rel_add(E, name, member)
		else
			rel_add(E, name, entry_value, member)
	return TRUE
