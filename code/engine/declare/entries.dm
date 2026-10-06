// Declaration entries (doc/rewrite/final_api.html, section 1 "Entry catalogue"; section 19 "E1, declarations").
//
// An entry is what a type declares: a capability, a relation, a conditional block, a change to something inherited. Every
// entry is a flyweight /datum/entry interned by its signature, so `tool(TOOL_MULTITOOL)` or `ref_one(nameof(species), ...)` is
// one datum wherever it is written, and a type that adds nothing shares its parent's compiled table. The table builder
// (table.dm) flattens the entries of a CAPABILITIES list, applies extend/configure/without in list order, validates, and
// splits the result into the per-engine indexes.
//
// Other engines add their entry kinds the same way: a constructor proc that calls entry_make(kind, key, args, children). The
// builder does not interpret a kind it does not own; the engine that owns it reads its entries from the compiled table
// (compiled_entries(type, kind)) and registers an /datum/entry_engine to be told when an activation applies or removes one.


/// Immutable and interned: never write a var of an entry after entry_make() returned it.
/datum/entry
	/// What the entry is (ENTRY_*, or another engine's kind).
	var/kind
	/// The optional key = of the entry, which extend/configure/without address it by. null: none.
	var/key
	/// The entry's named arguments (an assoc list of text -> value), or null.
	var/list/args
	/// Nested entries (a when() block's, a capability body's), in order, or null.
	var/list/children
	/// The interning signature.
	var/sig

/// The entry of `kind` with these arguments: the one shared instance for the signature. `args` is an assoc list; entries that
/// appear among its values or in `children` count by their own signature.
/proc/entry_make(kind, key, list/args, list/children)
	RETURN_TYPE(/datum/entry)
	var/static/list/interned = list()
	var/sig = entry_signature(kind, key, args, children)
	var/datum/entry/known = interned[sig]
	if(known)
		return known
	var/datum/entry/E = new
	E.kind = kind
	E.key = key
	E.args = args && length(args) ? args : null
	E.children = children && length(children) ? children : null
	E.sig = sig
	interned[sig] = E
	return E

/// The text that tells two entries apart: kind, key, every argument and every child, by value.
/proc/entry_signature(kind, key, list/args, list/children)
	var/list/parts = list(kind, isnull(key) ? "~" : "k[key]")
	for(var/name in args)
		parts += "[name]=[entry_value_signature(args[name])]"
	for(var/child in children)
		parts += "(" + entry_value_signature(child) + ")"
	return jointext(parts, "|")

/proc/entry_value_signature(value)
	if(istype(value, /datum/entry))
		var/datum/entry/E = value
		return "e:[E.sig]"
	if(islist(value))
		var/list/L = value
		var/list/parts = list()
		for(var/i in 1 to length(L))
			var/k = L[i]
			var/part = entry_value_signature(k)
			if(!isnum(k) && !isnull(k) && !isdatum(k) && !islist(k) && !isnull(L[k]))
				part += "=" + entry_value_signature(L[k])
			parts += part
		return "\[[jointext(parts, ",")]]"
	if(istype(value, /datum/capability))
		var/datum/capability/def = value
		return "c:[def.type]:[def.key]:[def.ctor ? entry_value_signature(def.ctor) : ""]"
	return datum_signature(value)

/// A boundary in a declared_entries() chain: entries after it, up to the next block, were declared by CAPABILITIES(type) at file:line.
/datum/entry/block
	kind = ENTRY_BLOCK
	/// The type the block was declared for.
	var/block_type
	var/file
	var/line

/proc/entry_block(file, line, type)
	var/datum/entry/block/B = new
	B.block_type = type
	B.file = file
	B.line = line
	B.sig = "block:[type]:[file]:[line]"
	return B

/// In a generated declared_entries() chain, the source line of the entry that follows: the generator writes one before each entry of a
/// CAPABILITIES list, so every compiled entry keeps its own file:line, and the name of the block's section(name) it sits in, if any.
/datum/entry/line
	kind = "line"
	var/line
	/// The section of the block the entry is written under, or null.
	var/section_name

/proc/entry_line(line, section_name = null)
	var/datum/entry/line/L = new
	L.line = line
	L.section_name = section_name
	return L

/// Where an entry was declared: "file:line" of its CAPABILITIES list (with " section <name>" when it sits in a section), or "?" when unknown.
/proc/entry_origin_text(file, line, section_name = null)
	if(!file)
		return "?"
	return section_name ? "[file]:[line] section [section_name]" : "[file]:[line]"

// ---- constructors of the entries E1 owns ----

/// A reference to another entity: the holder does not own it. Declared by `ref_one(nameof(v), type, ...)`.
/proc/ref_one(var_name, type = null, on_other_deleted = OTHER_CLEAR, on_unlink = null, by = null, key = null)
	return entry_make(ENTRY_REF_ONE, key, list("var" = var_name, "type" = type, "on_other_deleted" = on_other_deleted, "on_unlink" = on_unlink, "by" = by))

/proc/ref_many(var_name, type = null, on_other_deleted = OTHER_CLEAR, on_unlink = null, by = null, key = null)
	return entry_make(ENTRY_REF_MANY, key, list("var" = var_name, "type" = type, "on_other_deleted" = on_other_deleted, "on_unlink" = on_unlink, "by" = by))

/// An owned value: the holder owns it and disposes of it by `on_destroy`. starts = is the starting occupant (a type, nameof(type_var),
/// list(types), PROC_REF, pick_one(), when(cond, T)); starts_args are the constructor arguments of what it creates.
/// `only_if` (nameof(flag)) makes on_destroy conditional: it applies while the holder's flag var is true, else `otherwise` does (a robot's MMI is spilled
/// only once the borg had a mind to give it). `successor` / `successor_var` are where ON_DESTROY_HAND_OVER sends the value: the holder's var naming the successor and the
/// successor's var that takes it.
/proc/owns_one(var_name, type = null, starts = null, starts_args = null, on_destroy = ON_DESTROY_DELETE, copy_on_write = FALSE, key = null, only_if = null, otherwise = ON_DESTROY_DELETE, successor = null, successor_var = null)
	return entry_make(ENTRY_OWNS_ONE, key, list("var" = var_name, "type" = type, "starts" = starts, "starts_args" = starts_args, "on_destroy" = on_destroy, "copy_on_write" = copy_on_write, "only_if" = only_if, "otherwise" = otherwise, "successor" = successor, "successor_var" = successor_var))

/// `count =` makes that many of `starts` (or of `type` when starts is left out): owns_many(nameof(cells), /obj/item/cell, count = 2).
/proc/owns_many(var_name, type = null, starts = null, starts_args = null, on_destroy = ON_DESTROY_DELETE, copy_on_write = FALSE, key = null, count = null, only_if = null, otherwise = ON_DESTROY_DELETE, successor = null, successor_var = null)
	if(!isnull(count))
		var/made = isnull(starts) ? type : starts
		if(ispath(made))
			starts = list()
			starts[made] = count
		else
			declare_report("owns_many(\"[var_name]\", count = [count]): count needs one type in starts = or type =")
	return entry_make(ENTRY_OWNS_MANY, key, list("var" = var_name, "type" = type, "starts" = starts, "starts_args" = starts_args, "on_destroy" = on_destroy, "copy_on_write" = copy_on_write, "only_if" = only_if, "otherwise" = otherwise, "successor" = successor, "successor_var" = successor_var))

/// link_pair(/type::var, /type::var): the macro of code/__defines/engine/declare.dm passes each end as the text it was written as.
/// `a_many` / `b_many` say an end is a list var (DM has no way to read a var's declared type; the generator will derive it).
/proc/entry_link(a_text, b_text, hot = FALSE, a_many = FALSE, b_many = FALSE, key = null)
	var/list/a = link_end(a_text)
	var/list/b = link_end(b_text)
	return entry_make(ENTRY_LINK, key, list("a_type" = a[1], "a_var" = a[2], "b_type" = b[1], "b_var" = b[2], "hot" = hot, "a_many" = a_many, "b_many" = b_many))

/// The base of the CAPABILITIES(T) block header (code/__defines/engine/markers.dm): each block is an override of this on T, so a subtype's block
/// does not clash with its parent's. Nothing calls it; the statements of a block are read by `analyze` and compiled for their names and arguments.
/datum/proc/__capabilities()
	return

/// links(/type::var, /type::var, hot = FALSE, a_many = FALSE, b_many = FALSE, key = null): the block-form spelling of a paired relation (`link` is a
/// BYOND reserved word). Only a declaration: `analyze gen declare` rewrites it to entry_link() with each end as text, so this proc is never
/// called; it exists so the compiler and DreamChecker check the entry's name and named arguments inside a CAPABILITIES block.
/proc/links(a_end, b_end, hot = FALSE, a_many = FALSE, b_many = FALSE, key = null)
	CRASH("links() is a declaration entry read by analyze gen declare; it is never called")

/// "/obj/machinery/power/apc::hacker" -> list(path, "hacker"). The one place a type path is parsed from text: the macro cannot
/// hand over a path and a var name separately.
/proc/link_end(end_text)
	var/at = findtext(end_text, "::")
	if(!at)
		stack_trace("link(): [end_text] is not /type::var")
		return list(null, null)
	return list(text2path(copytext(end_text, 1, at)), copytext(end_text, at + 2))

/// A slot: an object that lives inside the holder (section 6). Backed by the containment ledger; the entry is the declaration the
/// ledger, the reach gate and the state-graph's SLOT_CONSTRUCTION read.
/proc/slot(slot_id, accepts = null, capacity = null, exposure = null, at = null, on_destroy = null, starts = null, starts_args = null, key = null)
	return entry_make(ENTRY_SLOT, key, list("id" = slot_id, "accepts" = accepts, "capacity" = capacity, "exposure" = exposure, "at" = at, "on_destroy" = on_destroy, "starts" = starts, "starts_args" = starts_args))

// DM gives a proc named arguments only when it declares them, so a constructor that takes entries and then options (`when(cond, a, b, reads =
// ...)`) declares ENTRY_SLOTS positional slots for the entries and the options by name. More than that many entries go in one list (a
// bundle): when(cond, list(a, b, c, ...)). A bundle is flattened.
#define ENTRY_SLOTS p1, p2, p3, p4, p5, p6
#define ENTRY_SLOT_LIST list(p1, p2, p3, p4, p5, p6)

/// Entries that exist while a condition holds (an activation whose scope is the condition and whose source is the holder's type).
/// `cond` is a condition as section 5 lists them: nameof(v), a stat or cap key id, cond_not()/cond_all()/cond_any() of those, or a PROC_REF.
/// `reads` is the var names a PROC_REF condition reads, written by hand until E5's generated reads replace it.
/proc/when(cond, ENTRY_SLOTS, list/reads = null)
	return entry_make(ENTRY_WHEN, null, list("cond" = cond, "reads" = reads), entry_flatten(ENTRY_SLOT_LIST))

/// extend(key | CAP_X | TAG_X | /datum/act/x, parts...): changes what the type inherits. `parts` are opaque to E1: the engine that owns
/// the addressed thing reads them (E2 for an op key, E4 for an act). drop = "id" relaxes a named requirement.
/proc/extend(key_or_id, ENTRY_SLOTS, drop = null)
	return entry_make(ENTRY_EXTEND, null, list("target" = key_or_id, "drop" = drop), entry_flatten(ENTRY_SLOT_LIST))

/// configure(e1_widget("a", power = 9), variant = /datum/capability/x/other): rebuilds the capability of that id and selector with the params
/// the call names (the ones left out keep their value). DM cannot take a capability's params as named arguments of one generic proc, so the
/// constructor call itself carries them.
/proc/configure(datum/capability/changes, variant = null)
	return entry_make(ENTRY_CONFIGURE, null, list("def" = changes, "variant" = variant))

/// without(key): drops an inherited entry by key, or every capability of a CAP id (with a selector, only that one).
/proc/without(target, selector = null)
	if(islist(target)) // the legacy `. = without(., /datum/capability/x)` of a capabilities() override
		return legacy_without(target, selector)
	return entry_make(ENTRY_WITHOUT, null, list("target" = target, "selector" = selector))

/// while_slotted(SLOT_X, entries..., on = ON_CONTENTS | ON_HOLDER): entries applied while an item is in that slot (an activation scoped
/// to the item's time in the slot). A slot-sourced activation is always bound to its source.
/proc/while_slotted(slot_id, ENTRY_SLOTS, on = ON_HOLDER)
	return entry_make(ENTRY_WHILE_SLOTTED, null, list("slot" = slot_id, "on" = on), entry_flatten(ENTRY_SLOT_LIST))

/// Grants the entries of the value a relation names, from that value's own CAPABILITIES list, while the relation names it
/// (the design's species_capabilities(): a species change is a relation write and an edge of the graph).
/proc/rel_grants(var_name, key = null)
	return entry_make(ENTRY_REL_GRANTS, key, list("var" = var_name))

/// A named list of entries or parts, kept in its own file and named by a constructor that returns it. Bundles flatten in list order.
/proc/entry_flatten(list/entries)
	. = list()
	for(var/entry in entries)
		if(islist(entry))
			. += entry_flatten(entry)
		else if(!isnull(entry))
			. += entry

/// A generic entry of a kind the engine that owns it has no constructor for yet (a fixture's stand-in for op() or contributes()):
/// entry_of("op", "toggle", e1, ...). The kind, an optional key, up to four children (entries, parts) and a closed set of named arguments
/// the fixtures use: stat, value, text, needs, from, into.
/proc/entry_of(kind, key = null, e1 = null, e2 = null, e3 = null, e4 = null, stat = null, value = null, text = null, needs = null, from = null, into = null)
	var/list/named = list()
	if(!isnull(stat))
		named["stat"] = stat
	if(!isnull(value))
		named["value"] = value
	if(!isnull(text))
		named["text"] = text
	if(!isnull(needs))
		named["needs"] = needs
	if(!isnull(from))
		named["from"] = from
	if(!isnull(into))
		named["into"] = into
	return entry_make(kind, key, named, entry_flatten(list(e1, e2, e3, e4)))
