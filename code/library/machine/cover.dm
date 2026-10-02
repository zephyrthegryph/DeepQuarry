// The cover capability (doc/rewrite/final_api.html, section 11 "The library": cover(name, open, remove, replace)).
//
// A cover over the holder's insides: the door of a bay (BAY_HATCH, compartment()). State keys COVER_OPEN and COVER_REMOVED (a removed cover is
// open for good); ops cover.open (toggles COVER_OPEN, by the `open` parts: a crowbar by default), cover.remove (the `remove` parts, when given)
// and cover.replace (the `replace` parts, when given: it fits a cover back on). Look layer and examine lines come with it.
//
//   cover()                                                       a crowbar opens and closes it
//   cover(open = hand())                                          an empty hand does
//   cover(remove = force_pry(), replace = component_swap(/obj/item/frame/apc))
//
// The params are parts (a binding, a wait, ...), resolved per definition; null is the default (a crowbar for `open`, no op for the others).

MSG_DEF(cover/opened, "You open the cover of %T%.", "%U% opens the cover of %T%.")
MSG_DEF(cover/shut, "You close the cover of %T%.", "%U% closes the cover of %T%.")
MSG_DEF(cover/pried_off, "You pry the cover off %T%.", "%U% pries the cover off %T%.")
MSG_DEF(cover/refitted, "You fit a new cover on %T%.", "%U% fits a new cover on %T%.")
MSG_DEF_SELF(cover/open_examine, "Its cover is open.")
MSG_DEF_SELF(cover/removed_examine, "Its cover has been removed.")

CAPABILITY_TYPE(cover, CAP_COVER, /datum/capability/lib/cover, key = name, name = "cover", open = null, remove = null, replace = null, starts_open = FALSE)
cap_keys(CAP_COVER, OPEN = MSG(cover/closed), REMOVED = MSG(cover/still_on))

/// Base of the library's capability datums (a CAPABILITY_TYPE with code of its own). The legacy library owns the plain names
/// (/datum/capability/panel, /datum/capability/lock, ...) until it is deleted, so the engine library lives under lib/.
/datum/capability/lib

/datum/capability/lib/cover
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/cover/entries()
	var/list/entries = list()
	entries += op("open", open || tool(TOOL_CROWBAR), \
		needs(req_is(COVER_REMOVED, FALSE, because = MSG(cover/removed))), \
		toggles(COVER_OPEN), says(CAP_PROC(open_message)))
	if(remove)
		entries += op("remove", remove, label("Remove cover"), \
			needs(req_is(COVER_REMOVED, FALSE, because = MSG(cover/removed))), \
			sets(COVER_REMOVED, TRUE), sets(COVER_OPEN, TRUE), says(MSG(cover/pried_off)))
	if(replace)
		entries += op("replace", replace, label("Replace cover"), \
			when(cond_any(COVER_REMOVED, cond_not(STAT_OPERABLE))), \
			sets(COVER_REMOVED, FALSE), sets(COVER_OPEN, FALSE), says(MSG(cover/refitted)))
	entries += look_layer(LOOK_COVER_OPEN, when = cond_all(COVER_OPEN, cond_not(COVER_REMOVED)))
	entries += examine_line(MSG(cover/removed_examine), when = COVER_REMOVED)
	entries += examine_line(MSG(cover/open_examine), when = cond_all(COVER_OPEN, cond_not(COVER_REMOVED)))
	return entries

/// What cover.open just did: opened or closed.
/datum/capability/lib/cover/proc/open_message(datum/act/A)
	return cover_open(A.holder, selector) ? /datum/msg/cover/opened : /datum/msg/cover/shut

/// A cover that starts open is open from the moment its holder initializes.
/datum/capability/lib/cover/on_holder_init_ctx(datum/act/eval/A)
	if(starts_open)
		cap_key_set(A.holder, COVER_OPEN, TRUE, selector)

/// An open or removed cover leaves its bay exposed.
/datum/capability/lib/cover/bay_exposed(datum/holder)
	return cover_open(holder, null) || cover_removed(holder, null)

/// The reason shown while the cover keeps its bay closed.
/datum/capability/lib/cover/bay_closed_reason()
	return /datum/msg/cover/closed

// ---- the bundles a cover's params are made of ----

/// remove = force_pry(): a crowbar on harm intent forces the thing open for good.
/proc/force_pry()
	return list(tool(TOOL_CROWBAR), hostile())

/// replace = component_swap(T): the held T goes in (it is used up) over `delay`, and the holder is whole again.
/proc/component_swap(item_type, delay = 5 SECONDS)
	return list(item(item_type), consumes(), wait(delay), fixes())
