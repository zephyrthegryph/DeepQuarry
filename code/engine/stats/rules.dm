// The combine rules (doc/rewrite/final_api.html, section 5 "The combine rules"; section 19 "E3, stats": "a table-driven test per rule").
//
// A stat's effective value is its base when nothing contributes, else the rule's combination of the contributions. A contribution is a value, a
// priority and a serial (how recent it is: type-level contributions are older than any hold). The rules, with their base, value type, tie-break and
// override:
//
//   ALL       TRUE when every contribution allows     base TRUE   boolean   no tie-break    hold_override, either way
//   ANY       TRUE when any contribution holds        base FALSE  boolean   no tie-break    hold_override, either way
//   SUM       the sum                                 base 0      number    none            the override replaces the sum
//   PRODUCT   the product                             base 1      number    none            the override replaces the product
//   MAX/MIN   the extreme, or the base with none      base =      number    none            the override replaces the extreme
//   TOP       the highest priority, then the most recent  base =  any       priority, recency  an override is a contribution at PRIORITY_ADMIN
//   SET       the union of the members                the empty set  tokens none            grant or revoke; no override
//   MASK_AND  the bits every contribution allows      base = (all bits)  bitmask  none      the override replaces the mask
//   MASK_OR   the bits any contribution sets          base 0      bitmask   none            the override replaces the mask
//   SUM_PER_KEY  a list of key -> the sum of the holds naming that key  the empty list  number per key  none  holds only (hold(..., key =)); no override
//   FORMULA   the result of one formula proc          the formula's own  any  none          the override replaces the result until released

/// Row layout of a contribution list passed to stat_combine(): flat, three entries each.
#define SC_VALUE 0
#define SC_PRIORITY 1
#define SC_SERIAL 2
#define SC_STRIDE 3

/**
 * The composed value of a stat from its contributions. `rows` is a flat list of (value, priority, serial) triples. A stat with no
 * contributions is its base. FORMULA is not composed here (the formula proc is the value).
 */
/proc/stat_combine(datum/stat_def/def, list/rows)
	var/count = round(length(rows) / SC_STRIDE)
	var/rule = def.rule
	if(!count)
		return rule == STAT_RULE_SET ? list() : def.base
	switch(rule)
		if(STAT_RULE_ALL)
			for(var/i in 1 to length(rows) step SC_STRIDE)
				if(!rows[i + SC_VALUE])
					return FALSE
			return TRUE
		if(STAT_RULE_ANY)
			for(var/i in 1 to length(rows) step SC_STRIDE)
				if(rows[i + SC_VALUE])
					return TRUE
			return FALSE
		if(STAT_RULE_SUM)
			. = 0
			for(var/i in 1 to length(rows) step SC_STRIDE)
				. += rows[i + SC_VALUE]
		if(STAT_RULE_PRODUCT)
			. = 1
			for(var/i in 1 to length(rows) step SC_STRIDE)
				. *= rows[i + SC_VALUE]
		if(STAT_RULE_MAX)
			. = null
			for(var/i in 1 to length(rows) step SC_STRIDE)
				var/v = rows[i + SC_VALUE]
				if(isnull(.) || v > .)
					. = v
		if(STAT_RULE_MIN)
			. = null
			for(var/i in 1 to length(rows) step SC_STRIDE)
				var/v = rows[i + SC_VALUE]
				if(isnull(.) || v < .)
					. = v
		if(STAT_RULE_TOP)
			var/best_priority = null
			var/best_serial = null
			for(var/i in 1 to length(rows) step SC_STRIDE)
				var/priority = rows[i + SC_PRIORITY]
				var/serial = rows[i + SC_SERIAL]
				if(isnull(best_priority) || priority > best_priority || (priority == best_priority && serial >= best_serial))
					best_priority = priority
					best_serial = serial
					. = rows[i + SC_VALUE]
		if(STAT_RULE_SET)
			. = list()
			for(var/i in 1 to length(rows) step SC_STRIDE)
				var/member = rows[i + SC_VALUE]
				if(islist(member))
					for(var/token in member)
						. |= list(token)
				else
					. |= list(member)
		if(STAT_RULE_MASK_AND)
			. = null
			for(var/i in 1 to length(rows) step SC_STRIDE)
				var/mask = rows[i + SC_VALUE]
				. = isnull(.) ? mask : (. & mask)
			if(!isnull(def.base))
				. = . & def.base
		if(STAT_RULE_MASK_OR)
			. = 0
			for(var/i in 1 to length(rows) step SC_STRIDE)
				. |= rows[i + SC_VALUE]

/// The value a hold gives the stat's rule when the hold carries none: a veto on ALL (FALSE), a force on ANY (TRUE). null for a rule that needs a value.
/proc/stat_forcing_value(datum/stat_def/def)
	if(def.rule == STAT_RULE_ALL)
		return FALSE
	if(def.rule == STAT_RULE_ANY)
		return TRUE
	return null

/// TRUE when two composed values are the same, including lists and masks.
/proc/stat_values_equal(a, b)
	if(islist(a) || islist(b))
		if(!islist(a) || !islist(b))
			return FALSE
		var/list/la = a
		var/list/lb = b
		if(length(la) != length(lb))
			return FALSE
		for(var/token in la)
			if(!(token in lb))
				return FALSE
			if(!isnum(token) && la[token] != lb[token]) // a key -> value list (SUM_PER_KEY): the values count too
				return FALSE
		return TRUE
	return a == b
