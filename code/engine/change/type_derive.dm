/// TYPE_DERIVES_* known so far for A's type. A type seen for the first time is TYPE_DERIVES_PENDING
/// (plus CAPS when it has capabilities) until its first refresh fills in LOOK and VERBS.
/proc/type_derive_flags(atom/A)
	var/known = GLOB.type_derives_cache[A.type]
	if(!isnull(known))
		return known
	. = TYPE_DERIVES_PENDING
	if(length(caps_of(A)) || present_declares_look(A))
		. |= TYPE_DERIVES_CAPS
	if(length(type_list(A, TYPE_PROC_REF(/atom, type_verbs))))
		. |= TYPE_DERIVES_TYPE_VERBS
	if(derived_table_of(A))
		. |= TYPE_DERIVES_DEPS
	if(look_table_has_layers(table_of(A)))
		. |= TYPE_DERIVES_LOOK // look_layer() entries draw through look_layers_draw(): the type has a look the refresh engine keeps up
	GLOB.type_derives_cache[A.type] = .

/// A refresh of A just ran draw() and hidden_verbs(): record what its type derives (first time only).
/proc/type_derive_record(atom/A, drew, hid, side = TRUE)
	var/flags = GLOB.type_derives_cache[A.type]
	if(isnull(flags) || !(flags & TYPE_DERIVES_PENDING))
		return
	flags &= ~TYPE_DERIVES_PENDING
	if(drew)
		flags |= TYPE_DERIVES_LOOK
	if(hid)
		flags |= TYPE_DERIVES_VERBS
	if(side)
		flags |= TYPE_DERIVES_SIDE
	GLOB.type_derives_cache[A.type] = flags

/// Whether A's type derives anything the refresh engine keeps up (a look or hidden verbs; unknown yet
/// counts as yes).
/proc/type_derives(atom/A)
	return !!(type_derive_flags(A) & (TYPE_DERIVES_LOOK | TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING))

GLOBAL_LIST_EMPTY(type_derives_cache) // ALLOW(cache): a per-type memo of derive flags, filled on first use and written in place as a type's capabilities change; shared caches hand out read-only values
