// The table builder (doc/rewrite/final_api.html, section 1 "Declarations", "Precedence"; section 19 "E1, declarations").
//
// A type's entries are the CAPABILITIES lists on its ancestors and on itself, parents first. The builder compiles each type from
// its parent's compiled table plus its own list: it walks the list once, interns every entry (entries.dm), applies extend,
// configure and without in list order, expands each capability into the entries its definition brings, validates, and keeps the
// result. A type whose list adds nothing shares its parent's table. Every entry keeps the file:line of its CAPABILITIES list in
// every build (the explain tools say where anything came from in production too).
//
// Errors are reported as `file:line: [rule] message -- hint`. In a test build a report fails the run (stack_trace), unless a test
// captures them (GLOB.declare_report_capture); `declare_report()` is the one place.

/// One compiled item: an interned entry (or capability definition), where it came from, the capability that brought it, and the
/// when() blocks it sits inside. Immutable once built; tables of a parent and its subtypes share them.
/datum/centry
	/// A /datum/entry, or a /datum/capability definition.
	var/datum/item
	/// "file:line" of the CAPABILITIES list that declared it.
	var/origin
	/// The key of the capability whose definition brought this entry, or null for a type's own entry.
	var/owner
	/// The enclosing when() entries, outermost first, or null.
	var/list/whens
	/// The key extend/configure/without address it by: its own key =, namespaced by the capability for an op.
	var/eff_key

/// One type's compiled table. Read-only after build: never write one.
/datum/type_table
	var/owner_type
	/// /datum/centry in effective order.
	var/list/items
	/// capability key -> the definition (type-level capabilities only).
	var/list/caps
	/// The reports made while building it.
	var/list/errors
	/// var names of the rel_grants() entries (relation-scoped grants), or null.
	var/list/rel_grant_vars
	/// TRUE when the type declares a while_slotted() entry: the ledger asks before it spends anything on a slot move (scopes.dm).
	var/has_slotted = FALSE
	/// TRUE when the type declares a type-level entry of a condition-scoped kind (cond_scope.dm).
	var/has_cond_scoped = FALSE
	/// ENGINE_HOOK_*: the lifecycle work an instance of the type needs.
	var/hook_flags = 0

/// block type -> /datum/type_table. A static, not a GLOB list: global datums are made while the globals are still being built, and their
/// declarations (a rel_add(..., key) in a global's New()) must already be readable. The table builds lazily on the first lookup.
/proc/type_blocks_cache()
	RETURN_TYPE(/list)
	var/static/list/cache = list() // ALLOW(cache,sys_static_getter): a mutable static, not a GLOB list, because the declaration tables are built while the globals are still being made
	return cache

/// instance type -> /datum/type_table (see type_blocks_cache()).
/proc/type_table_cache()
	RETURN_TYPE(/list)
	var/static/list/cache = list() // ALLOW(cache,sys_static_getter): a mutable static, not a GLOB list, because the declaration tables are built while the globals are still being made
	return cache

GLOBAL_VAR(declare_report_capture)

/// Reports a declaration error. A test that expects them sets GLOB.declare_report_capture to a list and reads it after.
/proc/declare_report(message)
	var/list/capture = GLOB.declare_report_capture
	if(islist(capture))
		capture += message
		return
	var/static/list/reported = list()
	if(reported[message])
		return
	reported[message] = TRUE
	stack_trace("DECLARE: [message]")

/// The base proc CAPABILITIES overrides: appends this type's entry block (parents first through ..()).
/datum/proc/declared_entries(list/into)
	SHOULD_CALL_PARENT(FALSE)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// The compiled table of D's type, built once per type from its parent's.
/proc/table_of(datum/D)
	RETURN_TYPE(/datum/type_table)
	var/datum/type_table/T = type_table_cache()[D.type]
	if(T)
		return T
	return table_build(D)

/// The table of a type that declares nothing, shared. Never written.
/proc/table_empty()
	RETURN_TYPE(/datum/type_table)
	var/static/datum/type_table/empty
	if(!empty)
		empty = new
		empty.items = list()
		empty.caps = list()
	return empty

/// The compiled table of `type` without an instance in hand (explain tools, tests): a probe instance is made, asked and deleted.
/proc/table_of_type(type)
	RETURN_TYPE(/datum/type_table)
	var/datum/type_table/T = type_table_cache()[type]
	if(T)
		return T
	var/datum/probe = isatom(type) ? null : null
	if(ispath(type, /atom/movable))
		probe = new type(null)
	else if(ispath(type, /datum) && !ispath(type, /atom))
		probe = new type
	if(!probe)
		return null
	T = table_build(probe)
	qdel(probe) // ALLOW(lifecycle): a probe instance made only to read a type's declarations
	return T

/proc/table_build(datum/D)
	var/list/chain = list()
	D.declared_entries(chain)
	var/list/blocks = table_split_blocks(chain)
	var/datum/type_table/T = null
	for(var/list/block in blocks)
		var/datum/entry/block/B = block[1]
		var/datum/type_table/built = type_blocks_cache()[B.block_type]
		if(!built)
			built = table_compile(B.block_type, T, block[2], entry_origin_text(B.file, B.line), B.file)
			type_blocks_cache()[B.block_type] = built
		T = built
	if(!T)
		T = table_compile(D.type, null, null, null)
	else if(T.owner_type != D.type && stat_type_needs_own_table(D.type, T.owner_type))
		// A type that declares nothing shares its ancestor's table, but a FORMULA stat it declares (STAT lines are not table entries) must be
		// computed at init: it gets its own table, whose hooks say so.
		T = table_compile(D.type, T, null, null)
	type_table_cache()[D.type] = T
	return T

/// A declared_entries() chain split at its blocks: list(list(block, entries), ...) in order.
/proc/table_split_blocks(list/chain)
	. = list()
	var/list/current = null
	for(var/entry in chain)
		if(istype(entry, /datum/entry/block))
			current = list(entry, list())
			. += list(current)
		else if(current)
			current[2] += list(entry)

/// A table from `parent` (null: empty) plus `entries`, all declared at `origin` (or, when the list carries entry_line() markers and `file` is
/// given, each at file:line of its own marker). Builds, applies, validates.
/proc/table_compile(type, datum/type_table/parent, list/entries, origin, file = null)
	RETURN_TYPE(/datum/type_table)
	var/datum/type_table/T = new
	T.owner_type = type
	T.items = parent ? parent.items.Copy() : list()
	T.caps = parent ? parent.caps.Copy() : list()
	T.errors = parent?.errors ? parent.errors.Copy() : null
	var/origin_now = origin
	for(var/item in entry_flatten(entries))
		if(istype(item, /datum/entry/line))
			var/datum/entry/line/L = item
			if(file)
				origin_now = entry_origin_text(file, L.line, L.section_name)
			continue
		table_apply(T, item, origin_now, null, null)
	table_validate(T)
	T.rel_grant_vars = null
	T.has_slotted = FALSE
	T.has_cond_scoped = FALSE
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == ENTRY_REL_GRANTS)
			LAZYOR(T.rel_grant_vars, E.args["var"])
		else if(istype(E) && E.kind == ENTRY_WHILE_SLOTTED)
			T.has_slotted = TRUE
		else if(istype(E) && isnull(C.owner) && entry_engine_for(E.kind)?.cond_scoped)
			T.has_cond_scoped = TRUE
	if(T.has_slotted)
		table_slot_gates(T) // a gated or reading while_slotted entry is re-applied when what it reads changes (scopes.dm)
	if(T.has_cond_scoped)
		table_cond_gates(T) // a condition-scoped entry is re-applied when its conditions or the vars it reads change (cond_scope.dm)
	T.hook_flags = table_hook_flags(T)
	return T

/// ENGINE_HOOK_* bits of a compiled table: what the lifecycle must call on an instance of the type.
/proc/table_hook_flags(datum/type_table/T)
	. = 0
	for(var/datum/centry/C as anything in T.items)
		if(istype(C.item, /datum/capability))
			var/datum/capability/def = C.item
			. |= def.holder_hooks
		else
			var/datum/entry/E = C.item
			if(istype(E) && E.kind == ENTRY_REL_GRANTS)
				. |= ENGINE_HOOK_INIT
			else if(istype(E) && E.kind == ENTRY_ON_CHANGE)
				. |= ENGINE_HOOK_INIT // the baseline of an on_change hook is taken when the holder initializes
			else if(istype(E) && E.kind == ENTRY_MODES)
				. |= ENGINE_HOOK_INIT | ENGINE_HOOK_MODES // the mode its var names is granted when the holder initializes
			else if(istype(E) && E.kind == ENTRY_VERB)
				. |= ENGINE_HOOK_INIT // a type's verb entries are put on the instance when it initializes
			else if(istype(E) && E.kind == ENTRY_EVERY && isnull(C.owner))
				. |= ENGINE_HOOK_INIT // a type-level every() is armed when the holder initializes
			else if(istype(E) && E.kind == ENTRY_SLOT && !isnull(E.args["starts"]))
				. |= ENGINE_HOOK_INIT | ENGINE_HOOK_SLOT_STARTS // a slot's starting contents are made when the holder initializes
			else if(istype(E) && E.kind == ENTRY_AFTER_INIT)
				. |= ENGINE_HOOK_INIT | ENGINE_HOOK_AFTER_INIT // armed when the instance's init is complete
	if(T.has_cond_scoped)
		. |= ENGINE_HOOK_INIT | ENGINE_HOOK_COND_SCOPED
	if(stat_table_needs_init(T))
		. |= ENGINE_HOOK_INIT | ENGINE_HOOK_STATS
	. |= lifeform_hook_flags(T) // the lifecycle forms (code/engine/lifeforms/forms.dm)



/// Reports an error on `T` and through declare_report().
/proc/table_error(datum/type_table/T, origin, rule, message, hint)
	var/text = "[origin || "?"]: [rule] [T.owner_type]: [message][hint ? " -- [hint]" : ""]"
	LAZYADD(T.errors, text)
	declare_report(text)

/// Applies one declared item to the table being built.
/proc/table_apply(datum/type_table/T, item, origin, owner, list/whens)
	if(istype(item, /datum/capability))
		table_add_capability(T, item, origin, owner, whens)
		return
	var/datum/entry/E = item
	if(!istype(E))
		table_error(T, origin, "[declare_rule(RULE_NOT_AN_ENTRY)]", "[item] is not an entry or a capability", "a declaration list holds the constructors of code/engine/declare/entries.dm and the library")
		return
	switch(E.kind)
		if(ENTRY_BLOCK)
			return
		if(ENTRY_WHEN)
			var/list/inner = whens ? whens.Copy() : list()
			inner += E
			for(var/child in E.children)
				table_apply(T, child, origin, owner, inner)
			return
		if(ENTRY_EXTEND)
			table_apply_extend(T, E, origin, owner, whens)
			return
		if(ENTRY_CONFIGURE)
			table_apply_configure(T, E, origin)
			return
		if(ENTRY_WITHOUT)
			table_apply_without(T, E, origin)
			return
		if(ENTRY_REF_ONE, ENTRY_REF_MANY, ENTRY_OWNS_ONE, ENTRY_OWNS_MANY)
			table_add_relation(T, E, origin, owner, whens)
			return
		if(ENTRY_LINK)
			link_register(E)
	table_add_item(T, E, origin, owner, whens, E.key)

/// Adds a centry. `eff_key` is what extend/configure/without address it by.
/proc/table_add_item(datum/type_table/T, datum/item, origin, owner, list/whens, eff_key)
	var/datum/centry/C = new
	C.item = item // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	C.origin = origin
	C.owner = owner
	C.whens = whens
	C.eff_key = eff_key
	T.items += C // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	return C


/proc/declare_rule(rule)
	return "\[[rule]]"

/proc/table_add_capability(datum/type_table/T, datum/capability/def, origin, owner, list/whens)
	var/key = def.key
	var/datum/capability/known = T.caps[key]
	if(known)
		if(known == def)
			return // an identical repeat dedupes
		var/datum/centry/first = table_find_cap_centry(T, known)
		table_error(T, origin, declare_rule(RULE_CAP_CONFLICT), "capability [key] is declared twice with different params ([cap_params_text(known)] at [first?.origin || "?"], and [cap_params_text(def)] here)", "use configure(CAP_X, param = value) to change what the type inherits")
		return
	T.caps[key] = def
	table_add_item(T, def, origin, owner, whens, key)
	var/list/children = def.entries()
	if(!length(children))
		return
	for(var/child in entry_flatten(children))
		table_apply_child(T, child, origin, def, whens)

/// An entry a capability's definition brings: kept with its owner, ops namespaced by the capability.
/proc/table_apply_child(datum/type_table/T, child, origin, datum/capability/owner_def, list/whens)
	if(istype(child, /datum/entry))
		var/datum/entry/E = child
		if(E.kind == ENTRY_WHEN)
			var/list/inner = whens ? whens.Copy() : list()
			inner += E
			for(var/grandchild in E.children)
				table_apply_child(T, grandchild, origin, owner_def, inner)
			return
		if(E.kind in list(ENTRY_EXTEND, ENTRY_CONFIGURE, ENTRY_WITHOUT, ENTRY_BLOCK))
			table_apply(T, E, origin, owner_def.key, whens)
			return
		var/eff = E.key
		if(E.kind == "op" && E.key)
			eff = cap_op_key(owner_def, E.key)
		table_add_item(T, E, origin, owner_def.key, whens, eff)
		return
	table_apply(T, child, origin, owner_def.key, whens)

/// The namespaced key of an op a capability brings: "cover.open", "cover.hatch.open", "cell_bay.cell.insert". A selector at its
/// default value adds nothing.
/proc/cap_op_key(datum/capability/def, op_key)
	var/datum/capability_info/info = def.cap_id ? capability_info(def.cap_id) : null
	var/prefix = info?.name || "[def.cap_id]"
	if(def.selector && !cap_selector_is_default(def, info))
		return "[prefix].[def.selector].[op_key]"
	return "[prefix].[op_key]"

/proc/cap_selector_is_default(datum/capability/def, datum/capability_info/info)
	if(!info?.key_param)
		return TRUE
	var/default_value = null
	if(info.key_param in def.vars)
		default_value = initial(def.vars[info.key_param])
	return isnull(default_value) ? FALSE : "[default_value]" == def.selector

/proc/table_find_cap_centry(datum/type_table/T, datum/capability/def)
	for(var/datum/centry/C as anything in T.items)
		if(C.item == def)
			return C
	return null

/// A relation entry: replaces an earlier one for the same var of the same kind family; a different kind for a var is an error.
/proc/table_add_relation(datum/type_table/T, datum/entry/E, origin, owner, list/whens)
	var/var_name = E.args["var"]
	for(var/i in 1 to length(T.items))
		var/datum/centry/old = T.items[i]
		var/datum/entry/OE = old.item
		if(!istype(OE) || !(OE.kind in list(ENTRY_REF_ONE, ENTRY_REF_MANY, ENTRY_OWNS_ONE, ENTRY_OWNS_MANY)) || OE.args["var"] != var_name)
			continue
		if(OE == E)
			return
		var/old_owns = (OE.kind == ENTRY_OWNS_ONE || OE.kind == ENTRY_OWNS_MANY)
		var/new_owns = (E.kind == ENTRY_OWNS_ONE || E.kind == ENTRY_OWNS_MANY)
		if(old_owns != new_owns)
			table_error(T, origin, declare_rule(RULE_RELATION_KIND), "var '[var_name]' is declared [OE.kind] at [old.origin] and [E.kind] here", "one kind per var across the hierarchy: a subtype may change an option, never the kind")
			return
		T.items.Cut(i, i + 1)
		break
	table_add_item(T, E, origin, owner, whens, E.key)

/// Does an extend()/without() target name something the table has? Text: an entry key. A number: a capability id the table has, or a tag. A
/// path: an action type. A list of keys (extend(list("a", "b"), ...)): every one of them.
/proc/table_resolves(datum/type_table/T, target)
	if(islist(target))
		for(var/one in target)
			if(!table_resolves(T, one))
				return FALSE
		return length(target) > 0
	if(ispath(target))
		return ispath(target, /datum/act) || ispath(target, /datum/notice)
	if(isnum(target))
		if(target >= TAG_BASE)
			return TRUE
		for(var/key in T.caps)
			var/datum/capability/def = T.caps[key]
			if(def.cap_id == target)
				return TRUE
		return FALSE
	for(var/datum/centry/C as anything in T.items)
		if(C.eff_key == target)
			return TRUE
	return FALSE

/proc/table_apply_extend(datum/type_table/T, datum/entry/E, origin, owner, list/whens)
	var/target = E.args["target"]
	if(!table_resolves(T, target))
		table_error(T, origin, declare_rule(RULE_UNKNOWN_KEY), "extend([islist(target) ? "list([jointext(target, ", ")])" : target]) names a key nothing in the table has", "spell an op key as the declaration does (\"cover.open\"), or use CAP_X, TAG_X or an action type")
		return
	table_add_item(T, E, origin, owner, whens, null)

/proc/table_cap_defs(datum/type_table/T, cap_id, selector)
	. = list()
	for(var/key in T.caps)
		var/datum/capability/def = T.caps[key]
		if(def.cap_id == cap_id && (isnull(selector) || def.selector == selector))
			. += def

/proc/table_apply_configure(datum/type_table/T, datum/entry/E, origin)
	var/datum/capability/change_call = E.args["def"]
	var/variant = E.args["variant"]
	if(!istype(change_call) || !change_call.cap_id)
		table_error(T, origin, declare_rule(RULE_CONFIGURE), "configure() takes a capability constructor change_call, got [change_call]", "configure(e1_widget(\"a\", power = 9))")
		return
	var/list/defs = table_cap_defs(T, change_call.cap_id, change_call.selector)
	if(!length(defs) && isnull(change_call.selector))
		defs = table_cap_defs(T, change_call.cap_id, null)
	if(!length(defs))
		table_error(T, origin, declare_rule(RULE_CONFIGURE), "configure(CAP [change_call.cap_id][change_call.selector ? ", \"[change_call.selector]\"" : ""]) names a capability the type does not have", "declare it first in this or an ancestor's list")
		return
	if(length(defs) > 1)
		table_error(T, origin, declare_rule(RULE_CONFIGURE), "configure(CAP [change_call.cap_id]) matches [length(defs)] capabilities and no selector was given", "name the selector: configure(e1_widget(\"selector\", ...))")
		return
	var/datum/capability/old = defs[1]
	var/list/changes = change_call.ctor ? change_call.ctor.Copy() : list()
	if(old.selector)
		var/datum/capability_info/info = capability_info(old.cap_id)
		if(info?.key_param)
			changes -= info.key_param // the selector names which one; it is not a change
	var/datum/capability/replacement = cap_reconfigured(old, changes, variant)
	if(replacement == old)
		return
	// Re-expand in place: the definition's centry and the entries it brought are replaced by the new definition's.
	var/at = 0
	for(var/i in 1 to length(T.items))
		var/datum/centry/C = T.items[i]
		if(C.item == old)
			at = i
			break
	var/datum/centry/old_cap_centry = T.items[at]
	var/list/keep = list()
	for(var/datum/centry/C as anything in T.items)
		if(C.owner == old.key && C != old_cap_centry)
			continue
		keep += C
	// Rebuild a scratch table to take the new definition's entries in the right place.
	var/datum/type_table/scratch = new
	scratch.owner_type = T.owner_type
	scratch.items = list()
	scratch.caps = list()
	table_add_capability(scratch, replacement, old_cap_centry.origin, old_cap_centry.owner, old_cap_centry.whens)
	var/list/result = list()
	for(var/datum/centry/C as anything in keep)
		if(C == old_cap_centry)
			result += scratch.items
		else
			result += C
	T.items = result
	T.caps -= old.key
	T.caps[replacement.key] = replacement

/proc/table_apply_without(datum/type_table/T, datum/entry/E, origin)
	var/target = E.args["target"]
	var/selector = E.args["selector"]
	var/removed = FALSE
	var/list/keep = list()
	var/list/dropped_caps = list()
	for(var/datum/centry/C as anything in T.items)
		var/drop = FALSE
		if(isnum(target))
			var/datum/capability/def = C.item
			if(istype(def) && def.cap_id == target && (isnull(selector) || def.selector == selector))
				drop = TRUE
				dropped_caps += def.key
		else if(C.eff_key == target)
			drop = TRUE
			var/datum/capability/def2 = C.item
			if(istype(def2))
				dropped_caps += def2.key
		if(drop)
			removed = TRUE
		else
			keep += C
	if(!removed)
		table_error(T, origin, declare_rule(RULE_WITHOUT), "without([target]) names nothing the type has", "the key must exist in an ancestor's list, or be the CAP id of a capability it declares")
		return
	// What a dropped capability brought goes with it, and so does a capability it brought (a bundle's nested one) with everything that one brought.
	var/list/pool = keep
	var/stable = FALSE
	while(!stable)
		stable = TRUE
		var/list/next = list()
		for(var/datum/centry/C as anything in pool)
			if(C.owner && (C.owner in dropped_caps))
				var/datum/capability/brought = C.item
				if(istype(brought) && !(brought.key in dropped_caps))
					dropped_caps += brought.key
					stable = FALSE
				continue
			next += C
		pool = next
	T.items = pool
	for(var/key in dropped_caps)
		T.caps -= key

/// The checks that need the whole table: a placed state-graph stage with several paths needs via =, and so on (graph.dm).
/proc/table_validate(datum/type_table/T)
	for(var/datum/centry/C as anything in T.items)
		var/datum/capability/def = C.item
		if(istype(def))
			def.validate_in(T, C.origin)
	op_validate_table(T)
	modes_validate_table(T)

/// Table-level checks a capability definition makes of its own params (a construction graph's start and via).
/datum/capability/proc/validate_in(datum/type_table/T, origin)
	return

/// The items of one kind (a /datum/entry kind, or ENTRY_CAPABILITY for definitions) in effective order. A fresh list.
/proc/compiled_entries(datum/type_table/T, kind)
	. = list()
	for(var/datum/centry/C as anything in T.items)
		if(kind == ENTRY_CAPABILITY)
			if(istype(C.item, /datum/capability))
				. += C
		else
			var/datum/entry/E = C.item
			if(istype(E) && E.kind == kind)
				. += C

/// The table's dump: one line per item, "kind key (args) @ origin", children indented by their when() depth. explain_type() returns it.
/proc/table_dump(datum/type_table/T)
	var/list/lines = list("[T.owner_type]")
	for(var/datum/centry/C as anything in T.items)
		lines += table_dump_line(T, C)
	return jointext(lines, "\n")

/proc/table_dump_line(datum/type_table/T, datum/centry/C)
	var/indent = "  "
	for(var/i in 1 to length(C.whens))
		indent += "  "
	var/body
	if(istype(C.item, /datum/capability))
		var/datum/capability/def = C.item
		body = "capability [capability_label(def)][def.selector ? " \"[def.selector]\"" : ""] ([cap_params_text(def)])"
	else
		var/datum/entry/E = C.item
		body = "[E.kind][C.eff_key ? " \"[C.eff_key]\"" : ""] ([entry_args_text(E)])"
	var/when_text = ""
	for(var/datum/entry/W as anything in C.whens)
		when_text += " when([W.args["cond"]])"
	var/owner_text = ""
	if(C.owner)
		var/datum/capability/owner_def = T.caps[C.owner]
		owner_text = " from [owner_def ? "[capability_label(owner_def)][owner_def.selector ? ":[owner_def.selector]" : ""]" : C.owner]"
	return "[indent][body][when_text][owner_text] @ [C.origin]"

/// What a capability is called in a dump: its constructor's name, or its key for a legacy one.
/proc/capability_label(datum/capability/def)
	var/datum/capability_info/info = def.cap_id ? capability_info(def.cap_id) : null
	return info?.name || (def.cap_id ? "CAP [def.cap_id]" : "[def.key]")

/proc/entry_args_text(datum/entry/E)
	var/list/parts = list()
	for(var/name in E.args)
		var/value = E.args[name]
		if(isnull(value) || value == FALSE)
			continue
		parts += "[name]=[islist(value) ? "list" : ((name == "stat" && isnum(value) && stat_def_of(value)) ? stat_label(value) : "[value]")]"
	for(var/child in E.children)
		var/datum/entry/CE = child
		if(istype(CE, /datum/entry/part))
			var/datum/entry/part/part_child = CE
			parts += part_child.describe()
		else
			parts += istype(CE) ? CE.kind : "[child]"
	return jointext(parts, ", ")
