// Table holds (doc/rewrite/final_api.html, section 5 "Holds: runtime contributions"; doc/rewrite/proposals/stat_layer.md, "hold_table").
//
//	hold_table(E, source, table, scale =, stacks =, part =, priority =)    release_table(E, source, part =)
//	hold_tables_begin(E)   hold_tables_end(E)
//
// A source that contributes to many stats at once (an affliction, a species, a reagent at a dose) declares one table: an alist of stat id -> value.
// hold_table() turns each entry into the contribution the stat's rule asks for at `scale` and `stacks`, and holds it as one row of `source`:
//
//   PRODUCT   max(0, 1 - (1 - value) * scale) ^ stacks        a multiplier that fades toward 1 as the scale falls
//   SUM       value * scale * stacks
//   MAX, MIN  value * scale                                    stacks are idempotent
//   MASK_OR   value                                            while the scale is above 0
//
// A scale of 0 or less holds nothing. A contribution that is the rule's neutral value (a multiplier of 1, a sum of 0, a bit mask of 0, a maximum
// at or below the base, a minimum at or above it) is no row. Placing the same (source, part) again replaces the values exactly, up or down (never
// REAPPLY_MAX), releases the rows of stats the new table no longer names (a table swap), and leaves unchanged rows alone: a value that did not
// move costs a compare and no recompute. Every stat the call changed settles once, after all its rows are placed.
//
// A source with more than one table gives each a `part` (a name); each (source, part) is its own set of rows. The rows carry HF_TABLE and a key
// of their own, so a plain hold(E, STAT_X, v, source) of the same source is a different row and release() leaves them alone: release_table(),
// release_all() and the source's deletion end them.
//
// A caller that re-reads every source of an entity (the body's factors) brackets the calls in hold_tables_begin() / hold_tables_end(): the rows
// no call of the pass touched are released, and every stat the pass changed settles once, however many tables moved.

/// The key of a table row's (source, part): "t" for the unnamed part, "t:name" for a named one.
#define TABLE_KEY(part) (isnull(part) ? "t" : "t:[part]")

/// The entity whose tables a pass is re-reading, or null outside a pass.
GLOBAL_VAR(stat_pass_entity)
/// The stats (skey -> def) the open pass changed a row of.
GLOBAL_LIST_EMPTY(stat_pass_touched)
/// The values (skey -> value) those stats held when the pass first touched them.
GLOBAL_LIST_EMPTY(stat_pass_before)

/// The contribution of one table entry at scale and stacks for the stat's rule, or null when it contributes nothing (the neutral value, or a scale
/// that is not above 0). Pure.
/proc/stat_table_contribution(datum/stat_def/def, value, scale, stacks)
	if(scale <= 0 || isnull(value))
		return null
	switch(def.rule)
		if(STAT_RULE_PRODUCT)
			var/c = max(0, 1 - (1 - value) * scale)
			if(c == 1)
				return null
			return stacks > 1 ? (c ** stacks) : c
		if(STAT_RULE_SUM)
			var/c = value * scale * stacks
			return c ? c : null
		if(STAT_RULE_MAX)
			var/c = value * scale
			return (isnull(def.base) || c > def.base) ? c : null
		if(STAT_RULE_MIN)
			var/c = value * scale
			return (isnull(def.base) || c < def.base) ? c : null
		if(STAT_RULE_MASK_OR)
			return value ? value : null
	return null

/// Holds `table` (stat id -> value) for `source` on E. Returns TRUE, or null with the reason reported when the call is refused.
/proc/hold_table(datum/E, source, alist/table, scale = 1, stacks = 1, part = null, priority = PRIORITY_DEFAULT)
	OP_PURE_GUARD("a table hold on [E?.type] was placed")
	if(!isdatum(E) || QDELETED(E))
		declare_report("hold_table([E?.type]): the holder is deleted or not a datum")
		return null
	if(!source_is_valid(source))
		declare_report("hold_table([E.type]): the source must be a live datum or a SOURCE_DEF id, got [isnull(source) ? "null" : "[source]"]")
		return null
	var/in_pass = (GLOB.stat_pass_entity == E)
	if(GLOB.stat_pass_entity && !in_pass)
		declare_report("hold_table([E.type]): a table pass for [GLOB.stat_pass_entity] is open; one pass at a time")
		return null
	var/datum/stat_record/rec = stat_record_of(E)
	if(!rec.inited)
		stat_ensure_inited(E, stat_type_of(E) || null)
	var/key = TABLE_KEY(part)
	var/list/touched = in_pass ? GLOB.stat_pass_touched : list()
	var/list/before = in_pass ? GLOB.stat_pass_before : list()
	for(var/id in table)
		var/datum/stat_def/def = stat_def_of(id)
		if(!def)
			declare_report("hold_table([E.type]): stat [id] is not declared")
			continue
		if(!stat_declared_on(E.type, def))
			declare_report("hold_table([E.type]): [E.type] does not declare stat [def.name]")
			continue
		var/c = stat_table_contribution(def, table[id], scale, stacks)
		if(isnull(c))
			continue
#if defined(UNIT_TESTS)
		if(def.schema)
			var/list/checked = schema_check(def.schema, c)
			if(checked[1] == SCHEMA_REJECT || checked[2])
				declare_report("hold_table([E.type], [def.name]): the contribution [c] does not satisfy the stat's schema ([checked[2]])")
				continue
#endif
		var/list/row = stat_hold_find(rec, def.id, source, key)
		if(row)
			row[H_FLAGS] |= HF_SEEN
			if(row[H_VALUE] == c && row[H_PRIORITY] == priority)
				continue
			row[H_VALUE] = c
			row[H_PRIORITY] = priority
		else
			row = list(def.id, source, c, 0, priority, HF_TABLE | HF_SEEN, HOLD_CLOCK_OWN, null, ++GLOB.stat_hold_serial, key, null)
			stat_rows_add(rec, row)
			if(isdatum(source))
				var/datum/stat_record/src_rec = stat_record_of(source)
				LAZYOR(src_rec.held_on, E)
		if(!touched[def.skey])
			before[def.skey] = stat_value_now(E, def, null)
			touched[def.skey] = def
	if(!in_pass)
		// A call of its own: this (source, part)'s rows the new table did not place leave, and the stats settle now.
		var/list/gone = list()
		for(var/list/row as anything in rec.holds)
			if((row[H_FLAGS] & HF_TABLE) && row[H_SOURCE] == source && row[H_KEY] == key)
				if(row[H_FLAGS] & HF_SEEN)
					row[H_FLAGS] &= ~HF_SEEN
				else
					var/datum/stat_def/def = stat_def_of(row[H_STAT])
					if(def && !touched[def.skey])
						touched[def.skey] = def
					gone += list(row)
		for(var/list/row as anything in gone)
			stat_hold_remove(E, rec, row)
		stat_table_settle(E, touched)
	return TRUE

/// Releases the rows of `part` of `source`'s tables on E (the unnamed part by default). TRUE when something was released.
/proc/release_table(datum/E, source, part = null)
	OP_PURE_GUARD("a table hold on [E?.type] was released")
	var/datum/stat_record/rec = isdatum(E) ? E.rx?.stats : null
	if(!rec?.holds)
		return FALSE
	var/key = TABLE_KEY(part)
	var/list/gone = list()
	for(var/list/row as anything in rec.holds)
		if((row[H_FLAGS] & HF_TABLE) && row[H_SOURCE] == source && row[H_KEY] == key)
			gone += list(row)
	if(!length(gone))
		return FALSE
	stat_release_rows(E, rec, gone)
	return TRUE

/// Opens a pass over E's tables: hold_table() calls for E until hold_tables_end() settle nothing, and the end releases what no call placed. Returns
/// TRUE, or FALSE (reported) when a pass is already open.
/proc/hold_tables_begin(datum/E)
	if(GLOB.stat_pass_entity)
		declare_report("hold_tables_begin([E?.type]): a table pass for [GLOB.stat_pass_entity] is already open")
		return FALSE
	GLOB.stat_pass_entity = E
	GLOB.stat_pass_touched = list()
	GLOB.stat_pass_before = list()
	var/datum/stat_record/rec = isdatum(E) ? E.rx?.stats : null
	for(var/list/row as anything in rec?.holds)
		if(row[H_FLAGS] & HF_SEEN)
			row[H_FLAGS] &= ~HF_SEEN // a mark a refused call left behind
	return TRUE

/// Closes the pass: every table row of E no call of the pass placed is released, and each stat the pass changed settles once, in rank order.
/// Returns how many stats ended with a different value than the pass found; `moved`, when given, receives their ids.
/proc/hold_tables_end(datum/E, list/moved = null)
	if(GLOB.stat_pass_entity != E)
		return 0
	var/list/touched = GLOB.stat_pass_touched
	var/list/before = GLOB.stat_pass_before
	GLOB.stat_pass_entity = null
	GLOB.stat_pass_touched = list()
	GLOB.stat_pass_before = list()
	var/datum/stat_record/rec = E.rx?.stats
	var/list/gone = list()
	for(var/list/row as anything in rec?.holds)
		if(!(row[H_FLAGS] & HF_TABLE))
			continue
		if(row[H_FLAGS] & HF_SEEN)
			row[H_FLAGS] &= ~HF_SEEN
			continue
		var/datum/stat_def/def = stat_def_of(row[H_STAT])
		if(def && !touched[def.skey])
			before[def.skey] = stat_value_now(E, def, null)
			touched[def.skey] = def
		gone += list(row)
	for(var/list/row as anything in gone)
		stat_hold_remove(E, rec, row)
	stat_table_settle(E, touched)
	. = 0
	for(var/skey in touched)
		var/datum/stat_def/def = touched[skey]
		if(!stat_values_equal(before[skey], stat_value_now(E, def, null)))
			.++
			moved?.Add(def.id)

/// Settles the stats a table call changed, once each, in rank order.
/proc/stat_table_settle(datum/E, list/touched)
	if(!length(touched))
		return
	var/list/defs = list()
	for(var/skey in touched)
		defs += touched[skey]
	stat_settle(E, defs)

/// What the stat `stat_id` composes to from `tables` alone, each held at `scale` and `stacks`: the stat's base, the tables' contributions by its
/// rule, held to its bounds. Pure: it holds nothing and reads no entity, so a source can ask what its tables would give without placing them.
/// `lookup_id` is the key the tables name the stat by when that is not the stat's own id.
/proc/stat_fold_tables(stat_id, list/tables, scale = 1, stacks = 1, lookup_id = null)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def)
		return null
	if(isnull(lookup_id))
		lookup_id = stat_id
	var/list/rows = list()
	if(!isnull(def.base))
		rows.Add(def.base, PRIORITY_DEFAULT, -1000000)
	for(var/alist/table as anything in tables)
		var/c = stat_table_contribution(def, table?[lookup_id], scale, stacks)
		if(!isnull(c))
			rows.Add(c, PRIORITY_DEFAULT, 0)
	var/value = stat_combine(def, rows)
	return def.clamps ? stat_clamp(def, value) : value
