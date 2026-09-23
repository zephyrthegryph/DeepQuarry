// Shared belly lists (C7, doc/rewrite/containment.md §9).
//
// A belly carries about fifty list vars: its message lists, idle emotes, the liquid
// it makes, extra autotransfer targets and the vore-spawn whitelist. Nearly every
// belly keeps its type's defaults, so every belly of a type points at one shared
// copy of each, made once:
//   - a var the type leaves unset gets the base default (belly_default_lists());
//   - a var a subtype sets with its own list() is shared per type (the first
//     instance's list is kept, later instances drop theirs for it);
//   - a list loaded from saved prefs that equals the shared one is swapped back
//     for it (belly_reshare_lists(), from state_post_apply()).
//
// Copy on write. These lists are never edited in place: customizing one replaces
// the var with a new list (set_messages(), the vore panel, the importer).
// emote_lists is the one list of lists written by key; writers call
// own_emote_lists() first. Only a customized list costs the belly anything.

/// Per type: var name -> the list every instance of that type shares.
GLOBAL_LIST_EMPTY(belly_type_shared_lists)

/// The base defaults for every shared list var, keyed by var name.
/proc/belly_default_lists()
	var/static/list/defaults
	if(!defaults)
		defaults = belly_default_message_lists().Copy()
		defaults["fullness1_messages"] = list("%pred's %belly looks empty")
		defaults["fullness2_messages"] = list("%pred's %belly looks filled")
		defaults["fullness3_messages"] = list("%pred's %belly looks like it's full of liquid")
		defaults["fullness4_messages"] = list("%pred's %belly is quite full!")
		defaults["fullness5_messages"] = list("%pred's %belly is completely filled to it's limit!")
		defaults["emote_lists"] = list()
		defaults["generated_reagents"] = list(REAGENT_ID_WATER = 1)
		defaults["autotransferextralocation"] = list()
		defaults["autotransferextralocation_secondary"] = list()
		defaults["vorespawn_whitelist"] = list()
	return defaults

/// The list `var_name` shares on this belly's type, or null if the type has none of its own.
/obj/belly/proc/belly_shared_list(var_name)
	var/list/type_lists = GLOB.belly_type_shared_lists[type]
	return type_lists?[var_name] || belly_default_lists()[var_name]

/// Runs before the atom's New(): the var initializers have just run, nothing else has.
/obj/belly/New(loc, ...)
	belly_share_lists()
	return ..()

/// Points every shared list var at its shared copy (see the file comment).
/obj/belly/proc/belly_share_lists()
	var/list/defaults = belly_default_lists()
	var/list/type_lists = GLOB.belly_type_shared_lists[type]
	for(var/var_name in defaults)
		var/list/current = vars[var_name]
		if(isnull(current))
			vars[var_name] = defaults[var_name]
			continue
		if(!type_lists)
			type_lists = list()
			GLOB.belly_type_shared_lists[type] = type_lists
		var/list/shared = type_lists[var_name]
		if(shared)
			vars[var_name] = shared
		else
			type_lists[var_name] = current

/// After a load: every list equal to the shared one goes back to sharing it.
/obj/belly/proc/belly_reshare_lists()
	for(var/var_name in belly_default_lists())
		var/list/current = vars[var_name]
		var/list/shared = belly_shared_list(var_name)
		if(current == shared)
			continue
		if(!islist(current))
			if(isnull(current))
				vars[var_name] = shared
			continue
		if(belly_lists_equal(current, shared))
			vars[var_name] = shared

/// TRUE if two lists hold the same entries (and values) in the same order, one level of nesting deep.
/proc/belly_lists_equal(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/i in 1 to length(a))
		var/key = a[i]
		if(key != b[i])
			return FALSE
		if(istext(key))
			var/value_a = a[key]
			var/value_b = b[key]
			if(islist(value_a) || islist(value_b))
				if(!islist(value_a) || !islist(value_b) || !belly_lists_equal(value_a, value_b))
					return FALSE
			else if(value_a != value_b)
				return FALSE
	return TRUE

/// Makes emote_lists this belly's own before a keyed write. Idempotent.
/obj/belly/proc/own_emote_lists()
	if(emote_lists != belly_shared_list("emote_lists") && islist(emote_lists))
		return emote_lists
	emote_lists = islist(emote_lists) ? emote_lists.Copy() : list()
	return emote_lists

/// Shared list vars this belly has customized (no longer the shared copy). The rest stay out of the saved state.
/obj/belly/proc/belly_unshared_list_names()
	. = list()
	for(var/var_name in belly_default_lists())
		if(vars[var_name] != belly_shared_list(var_name))
			. += var_name

/// The lists this belly holds for itself rather than shares: customized shared-list vars and
/// the lazy per-instance ones (the C7 memory measure; an empty, default belly has none).
/obj/belly/proc/belly_owned_lists()
	. = belly_unshared_list_names()
	if(items_preserved)
		. += "items_preserved"
	if(belly_surrounding)
		. += "belly_surrounding"
	if(ledger)
		. += "ledger"
