// Stat declarations (doc/rewrite/final_api.html, section 5 "Declaring"; section 19 "E3, stats").
//
// STAT(T, name, RULE, ...) registers one stat on a type. The id is per NAME, not per type: two types may declare the same name only with the
// same rule and the same base, which is how one meaning is shared across unrelated types (operable on every machine and on anything else that
// can lose power); the same name with another rule or base is a build error naming both declarations. A subtype cannot redeclare a stat with
// another rule. A stat belongs to its type: a contribution or a hold that names a stat the type does not declare is an error naming the type
// and the stat.
//
// A stat's effective value lives in a plain var that only the engine writes. The var is the type's own var of the stat's name; a stat whose
// type has no such var is virtual, and its value is read with stat_value(E, STAT_X).

/// Registration rows of STAT: list(type, the proc that returns list(name, rule, options)).
/datum/stat_decl/proc/spec()
	return null

/// One declared stat. Immutable once built.
/datum/stat_def
	var/id
	/// "[id]": the text key of every per-stat list (built once; a text of a number costs an allocation each time it is written).
	var/skey
	/// "stat:[id]": the key this stat publishes under and other stats read it by.
	var/stat_key
	var/name
	var/rule
	/// TRUE for the SUM_PER_KEY rule: the value is a key -> sum list and every hold names a key.
	var/keyed = FALSE
	/// TRUE for a boolean (ALL, ANY) stat.
	var/boolean = FALSE
	/// TRUE for a FORMULA stat.
	var/is_formula = FALSE
	/// TRUE for the rules stat_compute_fast() folds without a row list (ALL, ANY, SUM).
	var/fast = FALSE
	/// What the stat is with nothing contributing: the rule's own, or base =.
	var/base
	var/reapply = REAPPLY_MAX
	/// Deciseconds one unit of a status lasts (units =), or null for a plain stat.
	var/units
	/// FORMULA: the holder proc (a name) the stat is the result of.
	var/formula
	/// The declared reads of a FORMULA stat (hand-written until E5's generated reads replace them).
	var/list/formula_reads
	/// X5: the kind and range of the base and of every contribution.
	var/datum/schema/schema
	/// The types that declare it.
	var/list/types
	/// A status's companion immunity stat (STAT_<NAME>_IMMUNE) points at its status.
	var/immune_of
	/// Ranks come from the reads graph: one above the highest rank of any stat it reads on the same entity.
	var/rank = 0
	var/rank_known = FALSE

GLOBAL_LIST_EMPTY(stat_defs) // "[id]" -> /datum/stat_def
GLOBAL_LIST_EMPTY(stat_defs_by_name) // name -> /datum/stat_def
GLOBAL_VAR_INIT(stat_defs_built, FALSE)
GLOBAL_LIST_EMPTY(stat_type_index) // type -> /datum/stat_type_info

/// The base a rule has with nothing contributing when the declaration gives none.
/proc/stat_rule_base(rule)
	switch(rule)
		if(STAT_RULE_ALL)
			return TRUE
		if(STAT_RULE_ANY)
			return FALSE
		if(STAT_RULE_SUM, STAT_RULE_MASK_OR)
			return 0
		if(STAT_RULE_PRODUCT)
			return 1
		if(STAT_RULE_SET)
			return null
	return null

/// TRUE for a rule that takes no value from a contribution (a boolean stat).
/proc/stat_rule_is_boolean(rule)
	return rule == STAT_RULE_ALL || rule == STAT_RULE_ANY

/// Builds the registry from the STAT lines. Called on first use.
/proc/stat_defs_build()
	GLOB.stat_defs_built = TRUE
	for(var/decl_type in subtypesof(/datum/stat_decl))
		var/datum/stat_decl/D = new decl_type
		var/list/row = D.spec()
		if(!length(row))
			continue
		var/list/made = call(row[2])()
		stat_def_register(row[1], made[1], made[2], made[3])

/// One STAT line.
/proc/stat_def_register(type, name, rule, list/opts)
	var/id = opts["id"]
	if(!isnum(id) || id < STAT_ID_BASE)
		declare_report("STAT([type], [name]): id = must be a number from STAT_ID_BASE up (STAT_[uppertext(name)]), got [id]")
		return
	var/datum/stat_def/known = GLOB.stat_defs_by_name[name]
	var/base = opts["base"]
	if(isnull(base))
		base = stat_rule_base(rule)
	if(known)
		if(known.rule != rule || known.base != base)
			declare_report("STAT([type], [name]): '[name]' is already declared [known.rule] with base [known.base] (for [known.types[1]]); one name has one rule and one base, here [rule] with base [base]")
			return
		if(known.id != id)
			declare_report("STAT([type], [name]): id [id] differs from the id [known.id] of the same name")
			return
		known.types += type
		return
	if(GLOB.stat_defs["[id]"])
		var/datum/stat_def/clash = GLOB.stat_defs["[id]"]
		declare_report("STAT([type], [name]): id [id] is already the id of '[clash.name]'")
		return
	var/datum/stat_def/def = new
	def.id = id
	def.skey = "[id]"
	def.stat_key = "stat:[id]"
	def.name = name
	def.rule = rule
	def.boolean = stat_rule_is_boolean(rule)
	def.is_formula = (rule == STAT_RULE_FORMULA)
	def.keyed = (rule == STAT_RULE_SUM_PER_KEY)
	def.fast = (rule == STAT_RULE_ALL || rule == STAT_RULE_ANY || rule == STAT_RULE_SUM)
	def.base = base
	if(!isnull(opts["reapply"]))
		def.reapply = opts["reapply"]
	if(def.keyed)
		def.reapply = REAPPLY_REPLACE // a key's hold is its latest count, not the stronger of two
	def.units = opts["units"]
	def.formula = opts["formula"]
	def.formula_reads = opts["reads"]
	def.schema = opts["schema"] // ALLOW(ownership): a flyweight the declaration engine builds once per type and never mutates
	def.types = list(type)
	if(rule == STAT_RULE_FORMULA && !def.formula)
		declare_report("STAT([type], [name]): a FORMULA stat needs formula = PROC_REF(x)")
	if(rule != STAT_RULE_FORMULA && def.formula)
		declare_report("STAT([type], [name]): formula = is for the FORMULA rule only")
	GLOB.stat_defs["[id]"] = def
	GLOB.stat_defs_by_name[name] = def
	// A status (units =) carries a companion boolean ANY stat, STAT_<NAME>_IMMUNE: while it is TRUE the status reads 0.
	if(def.units)
		var/datum/stat_def/immune = new
		immune.id = STAT_IMMUNE(id)
		immune.skey = "[immune.id]"
		immune.stat_key = "stat:[immune.id]"
		immune.name = "[name]_immune"
		immune.rule = STAT_RULE_ANY
		immune.boolean = TRUE
		immune.base = FALSE
		immune.types = list(type)
		immune.immune_of = def
		GLOB.stat_defs["[immune.id]"] = immune
		GLOB.stat_defs_by_name[immune.name] = immune

/// The declared stat with this id, or null.
/proc/stat_def_of(id)
	RETURN_TYPE(/datum/stat_def)
	if(!islist(GLOB?.stat_defs))
		return null
	if(!GLOB.stat_defs_built)
		stat_defs_build()
	return GLOB.stat_defs["[id]"]

/// The declared stat of this name, or null.
/proc/stat_def_named(name)
	RETURN_TYPE(/datum/stat_def)
	if(!islist(GLOB?.stat_defs))
		return null
	if(!GLOB.stat_defs_built)
		stat_defs_build()
	return GLOB.stat_defs_by_name[name]

/// TRUE when `type` (or an ancestor) declares the stat.
/proc/stat_declared_on(type, datum/stat_def/def)
	for(var/declared in def.types)
		if(ispath(type, declared))
			return TRUE
	return FALSE

/// The text of a stat id for reports: "operable (100001)".
/proc/stat_label(id)
	var/datum/stat_def/def = stat_def_of(id)
	return def ? "[def.name]" : "stat [id]"
