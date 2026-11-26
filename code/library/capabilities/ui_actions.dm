// The validators a window handler or a sub-action reads its client values through: each returns null when the value is not acceptable.
// A window button is an op with a ui_act() binding whose arg() schemas validate the payload first (code/engine/parts/inputs.dm); these are for the
// values that arrive outside one (a nested payload, a stat panel message, a prompt answer).

// ---- validators: null when the value is not acceptable ----

/// TRUE for true/1/"1"/"true"/"yes", FALSE for false/0/"0"/"false"/"no"/"", null for anything else.
/proc/ui_bool(value)
	if(isnum(value))
		return value ? TRUE : FALSE
	if(istext(value))
		switch(lowertext(value))
			if("1", "true", "yes", "on")
				return TRUE
			if("0", "false", "no", "off", "")
				return FALSE
	return null

/// A number (or numeric text) clamped to [min_value, max_value]; null if it isn't one.
/proc/ui_number(value, min_value = -INFINITY, max_value = INFINITY, round_to = 0)
	READS_FROM()
	if(istext(value))
		value = text2num(value)
	if(!isnum(value) || value != value)
		return null
	if(round_to)
		value = round(value, round_to)
	return clamp(value, min_value, max_value)

/// Text, sanitised and cut to max_length; null if it isn't text (a number is rendered).
/proc/ui_text(value, max_length = MAX_MESSAGE_LEN)
	if(isnum(value))
		value = "[value]"
	if(!istext(value))
		return null
	return sanitize(value, max_length)

/// value if it is one of choices (a list), else null.
/proc/ui_choice(value, list/choices)
	if(isnull(value) || !(value in choices))
		return null
	return value

/// The datum a handle (the handle_of() a window was sent) names, if it is in `within` (or anywhere with within null) and of type `type`. A handle names
/// nothing once its datum is deleted, and a made-up value names nothing at all.
/proc/ui_token(value, list/within, type)
	READS_FROM() // a handle names a thing when a choice is made, never cached
	if(!istext(value) && !isnum(value))
		return null
	var/datum/D = handle_get(value)
	if(!D || (within && !(D in within)) || (type && !istype(D, type)))
		return null
	return D

/// The datum a handle names, only if it is in `within`, a list the caller's own window listed: unlike ui_token(), a null or empty list names nothing
/// (an empty `within` there means anywhere), so a console with no entries cannot be handed one from elsewhere.
/proc/ui_member(value, list/within, type)
	READS_FROM() // a handle names a thing when a choice is made, never cached
	if(!LAZYLEN(within))
		return null
	return ui_token(value, within, type)

/// The datum a ref names, if it is in `within` (or anywhere with within null) and of type `type`.
/proc/ui_ref(value, list/within, type)
	READS_FROM() // a ref names a thing when a choice is made, never cached
	if(!istext(value) && !isnum(value))
		return null
	var/datum/D = resolve_window_ref(value)
	if(within && !(D in within))
		return null
	if(!D || (type && !istype(D, type)))
		return null
	return D
