/atom/proc/type_verbs()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

// type_verbs() entries with flags (doc/rewrite/lifecycle.md "Starting state").
//
//	/mob/living/simple_mob/vore/wolf/type_verbs()
//		. = ..()
//		. += type_verb(/mob/living/proc/set_size, login = TRUE)
//
// A plain path in type_verbs() is on every instance from init. type_verb(path, login = TRUE) puts it on a mob only
// once a player has had it (applied at Login by verb_store_login(); an NPC-only mob never carries it): the old
// DECLARE_LOGIN_VERB, which is now a thin wrapper over this entry. The composed list is split once per type
// (type_verbs_always() / type_verbs_login()); nothing is stored per instance.

/// A type_verbs() entry carrying flags. Interned per (verb, flags): never written after construction.
/datum/type_verb
	var/verb_path
	/// Only on a mob, and only once a player has had it (Login).
	var/login = FALSE

/// A type_verbs() entry: the verb path itself, or with login = TRUE an entry the verb store applies at Login.
/proc/type_verb(verb_path, login = FALSE)
	if(!login)
		return verb_path
	var/datum/type_verb/entry = GLOB.type_login_verb_entries[verb_path]
	if(!entry)
		entry = new
		entry.verb_path = verb_path
		entry.login = TRUE
		GLOB.type_login_verb_entries[verb_path] = entry
	return entry

/// verb path -> its interned login entry.
GLOBAL_LIST_EMPTY(type_login_verb_entries)
/// type -> list(always paths, login paths): the split of the type's composed type_verbs().
GLOBAL_LIST_EMPTY(type_verbs_split)

/// The verb paths every instance of A's type has from init (type_verbs() without its login entries). Shared.
/proc/type_verbs_always(atom/A)
	RETURN_TYPE(/list)
	var/list/split = GLOB.type_verbs_split[A.type] || type_verbs_split_build(A)
	return split[1]

/// The verb paths a mob of A's type has once a player has had it (type_verb(..., login = TRUE)). Shared.
/proc/type_verbs_login(atom/A)
	RETURN_TYPE(/list)
	var/list/split = GLOB.type_verbs_split[A.type] || type_verbs_split_build(A)
	return split[2]

/proc/type_verbs_split_build(atom/A)
	var/list/always = list()
	var/list/login = list()
	for(var/entry in type_list(A, TYPE_PROC_REF(/atom, type_verbs)))
		if(istype(entry, /datum/type_verb))
			var/datum/type_verb/flagged = entry
			if(!ismob(A))
				stack_trace("type_verb([flagged.verb_path], login = TRUE) on [A.type]: only mobs log in; dropped")
				continue
			login |= flagged.verb_path
			always -= flagged.verb_path
		else if(!(entry in login))
			always |= entry
	var/list/split = list(always, login)
	GLOB.type_verbs_split[A.type] = split
	return split
