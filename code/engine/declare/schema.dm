// Value schemas (doc/rewrite/final_api.html, section 4 "Value schemas (X5)"; section 19 "E1, declarations": "value schemas (TRACKED(schema =),
// SCHEMA)").
//
// A schema is the declared kind of a value: range, normaliser, default and persistence. One schema drives every place the value is
// checked, shown or stored, so none of them is written by hand beside a setter, an arg or a column. This file is the schema itself and the
// checks (a setter's write, a boundary's input); the places that use one are the TRACKED_SCHEMA setter, E2's arg(), E6's prompts and
// requests, and the UI-type generator, which prints schema_range_text().
//
// The kinds are written bool(), int(min, max), num(min, max, step), enum(list), flags(list), schema_text(max_len, sanitize =), schema_ref(type),
// schema_path(type), list_of(schema), map_of(key, value) and row(type). BYOND owns the names text() and path(), so those two are spelled
// schema_text() and schema_path().



/// One declared kind of value. Immutable once built.
/datum/schema
	var/kind
	var/min
	var/max
	var/step
	/// enum: the list of choices, or a PROC_REF text naming a holder proc that returns it.
	var/choices
	/// flags: the declared flag values.
	var/list/flag_values
	var/max_len
	var/sanitize = SANITIZE_NONE
	/// ref / path / row: the type the value must be (or descend from).
	var/type_of
	/// list_of / map_of: the member schemas.
	var/datum/schema/member
	var/datum/schema/key_schema
	var/default
	var/has_default = FALSE
	/// normalize = a holder proc name (x(datum/act/A, value)): run after validation, returns the value to store.
	var/normalize
	var/on_invalid
	var/reason
	var/persist = FALSE
	/// The source text the declaration macro kept ("num(0, MAX_PUMP_PRESSURE, step = 1)"), for the range text.
	var/source_text

/proc/bool(default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_BOOL
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// A whole number. Bounds are optional: int() alone is any integer.
/proc/int(min = null, max = null, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_INT
	S.min = min
	S.max = max
	S.on_invalid = ON_INVALID_CLAMP
	schema_default(S, default)
	return S

/// A number; `step` snaps the value to a grid.
/proc/num(min = null, max = null, step = null, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_NUM
	S.min = min
	S.max = max
	S.step = step
	S.on_invalid = ON_INVALID_CLAMP
	schema_default(S, default)
	return S

/// One of a list of ids or texts. The list may be a PROC_REF text naming a holder proc that returns it, for choices known at runtime.
/proc/enum(choices, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_ENUM
	S.choices = choices
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// A bitmask of the declared flags: at most 24 (DM numbers are exact to 24 bits).
/proc/flags(list/flag_values, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_FLAGS
	S.flag_values = flag_values
	S.on_invalid = ON_INVALID_REJECT
	if(length(flag_values) > 24)
		declare_report("flags(): [length(flag_values)] flags declared, at most 24 fit a DM number")
	schema_default(S, default)
	return S

/// A string no longer than max_len; sanitize = names a rule from the closed list.
/proc/schema_text(max_len = null, sanitize = SANITIZE_NONE, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_TEXT
	S.max_len = max_len
	S.sanitize = sanitize
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// An entity of that type, held as a handle.
/proc/schema_ref(type, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_REF
	S.type_of = type
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// A type path that descends from `type`.
/proc/schema_path(type, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_PATH
	S.type_of = type
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// A list whose members have the given schema.
/proc/list_of(datum/schema/member, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_LIST
	S.member = member // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// An associative list whose keys and values have the given schemas.
/proc/map_of(datum/schema/key_schema, datum/schema/value_schema, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_MAP
	S.key_schema = key_schema // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	S.member = value_schema // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/// A typed record row, such as a SQL row, whose own vars carry schemas.
/proc/row(type, default = null)
	var/datum/schema/S = new
	S.kind = SCHEMA_ROW
	S.type_of = type
	S.on_invalid = ON_INVALID_REJECT
	schema_default(S, default)
	return S

/proc/schema_default(datum/schema/S, default)
	if(!isnull(default))
		S.default = default
		S.has_default = TRUE

// ---- the declarations ----

/// Registration rows of SCHEMA / TRACKED_SCHEMA: list(type, the proc that returns the row).
/datum/schema_decl/proc/spec()
	return null

GLOBAL_LIST_EMPTY(schemas) // type -> list(var -> /datum/schema); built on first use
GLOBAL_VAR_INIT(schemas_built, FALSE)

/proc/schemas_build()
	GLOB.schemas_built = TRUE
	for(var/decl_type in subtypesof(/datum/schema_decl))
		var/datum/schema_decl/D = new decl_type
		var/list/row = D.spec()
		if(!length(row))
			continue
		var/type = row[1]
		var/list/made = call(row[2])()
		var/var_name = made[1]
		var/datum/schema/S = made[2]
		var/list/opts = made[3]
		if(!istype(S))
			declare_report("SCHEMA([type], [var_name]): the schema expression did not build a schema")
			continue
		S.source_text = made[4]
		schema_apply_options(S, opts, type, var_name)
		var/list/by_var = GLOB.schemas[type]
		if(!by_var)
			by_var = list()
			GLOB.schemas[type] = by_var
		by_var[var_name] = S

/// default =, normalize =, persist =, on_invalid =, reason = of a declaration.
/proc/schema_apply_options(datum/schema/S, list/opts, type, var_name)
	for(var/name in opts)
		var/value = opts[name]
		switch(name)
			if("default")
				S.default = value
				S.has_default = TRUE
			if("normalize")
				S.normalize = value
			if("persist")
				S.persist = !!value
			if("on_invalid")
				S.on_invalid = value
			if("reason")
				S.reason = value
			else
				declare_report("SCHEMA([type], [var_name]): unknown option '[name]'")
	if(S.has_default)
		var/list/problem = schema_check(S, S.default)
		if(problem[1] == SCHEMA_REJECT || problem[2])
			declare_report("SCHEMA([type], [var_name]): the default [S.default] does not satisfy the schema ([problem[2] || "rejected"])")

/// The schema of `type`'s var (the nearest ancestor that declares it), or null.
/proc/schema_of(type, var_name)
	RETURN_TYPE(/datum/schema)
	if(!islist(GLOB?.schemas))
		return null
	if(!GLOB.schemas_built)
		schemas_build()
	var/datum/schema/found = null
	var/best = 0
	for(var/declared_type in GLOB.schemas)
		var/list/by_var = GLOB.schemas[declared_type]
		if(by_var[var_name] && ispath(type, declared_type))
			var/depth = length(splittext("[declared_type]", "/"))
			if(depth > best)
				best = depth
				found = by_var[var_name]
	return found

// ---- checking ----

/**
 * Checks `value` against S. Returns list(value to store or SCHEMA_REJECT, note) where note is null when the value was fine, or a short
 * text when it was clamped, rounded or snapped. A number outside its range is clamped (on_invalid = ON_INVALID_CLAMP) and any other
 * failure is rejected, unless on_invalid says otherwise. `boundary` is TRUE for input that arrives from a player, a UI arg or a
 * request: an int refuses a fractional number there instead of rounding it.
 */
/proc/schema_check(datum/schema/S, value, boundary = FALSE, datum/holder = null)
	switch(S.kind)
		if(SCHEMA_BOOL)
			if(value == TRUE || value == FALSE)
				return list(value ? TRUE : FALSE, null)
			return list(SCHEMA_REJECT, "[value] is not a boolean")
		if(SCHEMA_INT, SCHEMA_NUM)
			if(boundary && istext(value))
				value = text2num(value) // a client sends "3" as often as 3 (the old UI_ARG_NUM read both)
			if(!isnum(value) || value != value) // NaN
				return list(SCHEMA_REJECT, "[value] is not a number")
			var/note = null
			var/v = value
			if(S.kind == SCHEMA_INT && v != round(v))
				if(boundary)
					return list(SCHEMA_REJECT, "[value] is not a whole number")
				v = round(v + 0.5) // an internal write rounds to the nearest whole number
				note = "rounded [value] to [v]"
			if(S.kind == SCHEMA_NUM && S.step)
				var/snapped = round(v - (S.min || 0), S.step) + (S.min || 0)
				if(snapped != v)
					note = note || "snapped [value] to [snapped]"
					v = snapped
			if(!isnull(S.min) && v < S.min)
				if(S.on_invalid == ON_INVALID_REJECT)
					return list(SCHEMA_REJECT, "[value] is below [S.min]")
				note = "clamped [value] to [S.min]"
				v = S.min
			if(!isnull(S.max) && v > S.max)
				if(S.on_invalid == ON_INVALID_REJECT)
					return list(SCHEMA_REJECT, "[value] is above [S.max]")
				note = "clamped [value] to [S.max]"
				v = S.max
			return list(v, note)
		if(SCHEMA_ENUM)
			var/list/choices = S.choices
			if(istext(choices) && holder)
				choices = call(holder, choices)()
			if(islist(choices) && !(value in choices))
				return list(SCHEMA_REJECT, "[value] is not one of the choices")
			return list(value, null)
		if(SCHEMA_FLAGS)
			if(!isnum(value))
				return list(SCHEMA_REJECT, "[value] is not a flag mask")
			var/mask = 0
			for(var/f in S.flag_values)
				mask |= f
			if(value & ~mask)
				return list(SCHEMA_REJECT, "[value] sets undeclared flags")
			return list(value, null)
		if(SCHEMA_TEXT)
			if(boundary && isnum(value) && value == value)
				value = "[value]" // a window sends a typed-in or selected number for a text field: its text (the legacy UI_ARG_TEXT parse)
			if(!istext(value))
				return list(SCHEMA_REJECT, "[value] is not text")
			var/t = value
			switch(S.sanitize)
				if(SANITIZE_PLAIN)
					t = sanitize(t, S.max_len || MAX_MESSAGE_LEN)
				if(SANITIZE_NAME)
					t = sanitize(t, S.max_len || MAX_NAME_LEN)
			if(S.max_len && length(t) > S.max_len)
				return list(SCHEMA_REJECT, "longer than [S.max_len] characters")
			return list(t, (t != value) ? "sanitized" : null)
		if(SCHEMA_REF)
			if(boundary && istext(value))
				value = locate(value) // a window sends a ref as its text: the entity it names (null when it names none)
			if(isnull(value) || (isdatum(value) && (!S.type_of || istype(value, S.type_of))))
				return list(value, null)
			return list(SCHEMA_REJECT, "[value] is not a [S.type_of]")
		if(SCHEMA_PATH)
			if(boundary && istext(value))
				value = text2path(value) // a window sends a type as its text
			if(ispath(value) && (!S.type_of || ispath(value, S.type_of)))
				return list(value, null)
			return list(SCHEMA_REJECT, "[value] is not a path under [S.type_of]")
		if(SCHEMA_ROW)
			if(isdatum(value) && (!S.type_of || istype(value, S.type_of)))
				return list(value, null)
			return list(SCHEMA_REJECT, "[value] is not a [S.type_of] row")
		if(SCHEMA_LIST)
			if(!islist(value))
				return list(SCHEMA_REJECT, "[value] is not a list")
			var/list/in_list = value
			var/list/out = list()
			var/list_note = null
			for(var/member in in_list)
				var/list/checked = schema_check(S.member, member, boundary, holder)
				if(checked[1] == SCHEMA_REJECT)
					return list(SCHEMA_REJECT, "a member: [checked[2]]")
				out += list(checked[1])
				list_note = list_note || checked[2]
			return list(out, list_note)
		if(SCHEMA_MAP)
			if(!islist(value))
				return list(SCHEMA_REJECT, "[value] is not a list")
			var/list/in_map = value
			var/list/map_out = list()
			var/map_note = null
			for(var/k in in_map)
				var/list/checked_key = schema_check(S.key_schema, k, boundary, holder)
				if(checked_key[1] == SCHEMA_REJECT)
					return list(SCHEMA_REJECT, "a key: [checked_key[2]]")
				var/list/checked_value = schema_check(S.member, in_map[k], boundary, holder)
				if(checked_value[1] == SCHEMA_REJECT)
					return list(SCHEMA_REJECT, "a value: [checked_value[2]]")
				map_out[checked_key[1]] = checked_value[1]
				map_note = map_note || checked_key[2] || checked_value[2]
			return list(map_out, map_note)
	return list(value, null)

GLOBAL_VAR_INIT(schema_last_note, null)
GLOBAL_LIST_EMPTY(schema_log_state) // "[type]|[var]" -> list(last full line time, suppressed count)
GLOBAL_VAR(schema_log_capture)

/**
 * A setter's write: the value to store for `var_name` of `holder`, validated and normalised, or SCHEMA_REJECT. A number outside its
 * range was clamped (and logged); any other failure leaves the old value (logged). A var with no schema passes through.
 */
/proc/schema_write(datum/holder, var_name, value)
	var/datum/schema/S = schema_of(holder.type, var_name)
	if(!S)
		return value
	var/list/checked = schema_check(S, value, FALSE, holder)
	if(checked[1] == SCHEMA_REJECT)
		schema_log(holder, var_name, "[var_name] [checked[2]]: write refused")
		return SCHEMA_REJECT
	if(checked[2])
		schema_log(holder, var_name, "[var_name] [checked[2]]")
	return schema_normalized(S, holder, checked[1])

/// Boundary input (a UI arg, a prompt answer, a request field): checked before anything reads it. Returns list(value or SCHEMA_REJECT,
/// reason text or null). An int refuses a fractional number; a number outside its range is clamped.
/proc/schema_input(datum/schema/S, value, datum/holder = null)
	var/list/checked = schema_check(S, value, TRUE, holder)
	if(checked[1] == SCHEMA_REJECT)
		return list(SCHEMA_REJECT, checked[2])
	return list(holder ? schema_normalized(S, holder, checked[1]) : checked[1], checked[2])

/// The normalizer of the schema over a validated value (holder proc x(datum/act/A, value)).
/proc/schema_normalized(datum/schema/S, datum/holder, value)
	if(!S.normalize || !holder)
		return value
	var/datum/act/eval/A = take(/datum/act/eval)
	A.holder = holder // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	. = call(holder, S.normalize)(A, value)
	A.release()

/// Writes one line about a clamp or a refusal: the first for a (type, var) in full, then one summary per SCHEMA_LOG_INTERVAL with a count.
/proc/schema_log(datum/holder, var_name, message)
	var/key = "[holder.type]|[var_name]"
	var/list/state = GLOB.schema_log_state[key]
	var/now = world.time
	if(!state)
		GLOB.schema_log_state[key] = list(now, 0)
		schema_log_line(holder, "SCHEMA: [holder.type] [message]")
		return
	if(now - state[1] >= SCHEMA_LOG_INTERVAL)
		var/count = state[2]
		state[1] = now
		state[2] = 0
		schema_log_line(holder, "SCHEMA: [holder.type] [message][count ? " ([count] more in the last [SCHEMA_LOG_INTERVAL / 10]s)" : ""]")
		return
	state[2]++

/proc/schema_log_line(datum/holder, line)
	if(islist(GLOB.schema_log_capture))
		var/list/capture = GLOB.schema_log_capture
		capture += line
	log_world(line)
	TEST_REC_LOG(null, null, null, null, holder, line)

// ---- range text ----

/**
 * The range text of the schema of `type`'s var, as the generated UI type's doc comment spells it: "num 0..MAX_PUMP_PRESSURE step 1". It is
 * read from the source text of the declaration, so a define keeps its name instead of its value.
 */
/proc/schema_range_text(type, var_name)
	var/datum/schema/S = schema_of(type, var_name)
	if(!S)
		return null
	return schema_describe(S)

/proc/schema_describe(datum/schema/S)
	var/list/arg_texts = schema_source_args(S.source_text)
	switch(S.kind)
		if(SCHEMA_INT, SCHEMA_NUM)
			var/min_text = "[S.min]"
			var/max_text = "[S.max]"
			var/step_text = S.step ? "[S.step]" : null
			if(length(arg_texts))
				var/positional = 0
				for(var/t in arg_texts)
					var/at = findtext(t, "=")
					if(at)
						var/name = trim(copytext(t, 1, at))
						var/value = trim(copytext(t, at + 1))
						if(name == "step")
							step_text = value
						else if(name == "min")
							min_text = value
						else if(name == "max")
							max_text = value
					else
						positional++
						if(positional == 1)
							min_text = t
						else if(positional == 2)
							max_text = t
						else if(positional == 3 && S.kind == SCHEMA_NUM)
							step_text = t
			var/range = (isnull(S.min) && isnull(S.max)) ? "" : " [isnull(S.min) ? "" : min_text]..[isnull(S.max) ? "" : max_text]"
			return "[S.kind][range][step_text ? " step [step_text]" : ""]"
		if(SCHEMA_TEXT)
			return "text[S.max_len ? " max [S.max_len]" : ""]"
		if(SCHEMA_ENUM)
			return "enum"
	return S.kind

/// The top-level arguments of a declaration's source text "num(0, MAX, step = 1)": a list of trimmed argument texts, or null.
/proc/schema_source_args(source_text)
	if(!istext(source_text))
		return null
	var/open = findtext(source_text, "(")
	var/close = findlasttext(source_text, ")")
	if(!open || !close || close < open)
		return null
	var/inner = copytext(source_text, open + 1, close)
	var/list/out = list()
	var/depth = 0
	var/start = 1
	for(var/i in 1 to length(inner))
		var/c = copytext(inner, i, i + 1)
		if(c == "(")
			depth++
		else if(c == ")")
			depth--
		else if(c == "," && depth == 0)
			out += trim(copytext(inner, start, i))
			start = i + 1
	var/last = trim(copytext(inner, start))
	if(length(last))
		out += last
	return out
