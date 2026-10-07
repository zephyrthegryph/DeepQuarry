/// Every capability's hidden verbs plus the type's own hidden_verbs().
/proc/caps_hidden_verbs(atom/holder)
	. = list()
	for(var/datum/capability/C as anything in caps_all(holder))
		var/list/hidden = C.hidden_verbs(holder)
		if(hidden)
			. |= hidden


/// The engine's lazy per-atom records, kept in the atom's cap_data under this datum's type so that an atom spends no
/// base-type var on a feature it is not using: a capability entry's cooldowns and look_flash()'s transient visuals.
/// Made on first write (cap_engine_state_make()), read without making one (cap_engine_state_of()); cap_data's teardown
/// (caps_destroy()) deletes it with the atom.
/datum/cap_engine_state
	/// entry id -> world.time when a capability entry's cooldown ends (entry `cooldown =`). Lazy.
	var/list/entry_cooldowns
	/// state -> TRUE for the overlays look_flash() is showing now. Lazy.
	var/list/look_flashes
	/// The base state look_flash(as_state = TRUE) is showing now, or null.
	var/look_flash_state
	/// state -> the token of the flash that owns it, so look_flash_end() ends only its own. Lazy.
	var/list/look_flash_tokens

/// A's engine record, or null when the engine has kept nothing for it.
/proc/cap_engine_state_of(atom/A)
	RETURN_TYPE(/datum/cap_engine_state)
	return capability_data(A)?[/datum/cap_engine_state]

/// A's engine record, made when it has none.
/proc/cap_engine_state_make(atom/A)
	RETURN_TYPE(/datum/cap_engine_state)
	var/datum/cap_engine_state/state = capability_data(A)?[/datum/cap_engine_state]
	if(!state)
		state = new
		LAZYSET(capability_runtime(A).data, /datum/cap_engine_state, state)
	return state


// ---- ordering (M1) ----

/// A's capabilities in draw or examine order: list order unless some set layer_order/examine_order.
/// Cached per type (extras append in their own order).
/proc/caps_ordered(atom/A, which)
	var/key = "[A.type]|[which]"
	var/list/ordered = GLOB.caps_order_cache[key]
	if(!ordered)
		ordered = caps_sort(caps_of(A), which)
		GLOB.caps_order_cache[key] = ordered
	return capability_extras(A) ? ordered + caps_sort(capability_extras(A), which) : ordered

GLOBAL_LIST_EMPTY(caps_order_cache) // ALLOW(cache): a per-(type, order) memo of sorted capability lists, filled on first use and never invalidated

/proc/caps_sort(list/caps, which)
	var/any = FALSE
	for(var/datum/capability/C as anything in caps)
		if(!isnull(which == CAP_ORDER_DRAW ? C.layer_order : C.examine_order))
			any = TRUE
			break
	if(!any)
		return caps
	// Stable: entries without an explicit order keep their list index as the order.
	var/list/keyed = list()
	for(var/i in 1 to length(caps))
		var/datum/capability/C = caps[i]
		var/order = which == CAP_ORDER_DRAW ? C.layer_order : C.examine_order
		keyed += list(list(isnull(order) ? i : order, i, C))
	keyed = sortTim(keyed, GLOBAL_PROC_REF(caps_order_cmp))
	. = list()
	for(var/list/row as anything in keyed)
		. += row[3]

/proc/caps_order_cmp(list/a, list/b)
	if(a[1] != b[1])
		return a[1] - b[1]
	return a[2] - b[2]


/datum/capability/proc/draw(atom/holder, datum/look/look)
	return


/datum/capability/proc/hidden_verbs(atom/holder)
	return null


/datum/capability/proc/verbs()
	return null
