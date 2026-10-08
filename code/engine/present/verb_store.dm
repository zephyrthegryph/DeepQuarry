// The verb store (doc/rewrite/systems.md §19). It is the ONLY code that writes a `verbs` list:
// nothing else may `verbs +=`, `verbs -=`, assign `verbs`, or create a verb with
// `new /x/proc/y(target, ...)` (lint sys_verb_write, no ALLOW accepted).
//
// A verb is on an atom or a client when
//     not hidden:  no hidden granted_verb activation hides it and the type doesn't DECLARE_VERB_HIDE it
//     and one of:  a granted_verb activation grants it
//                  the type declares it (a /type/verb/ it inherits, DECLARE_VERB,
//                  DECLARE_VERB_IF with the var true, DECLARE_LOGIN_VERB once a player had it)
//
// Runtime changes are capabilities (code/engine/present/verbs.dm):
//
//     grant(M, granted_verb(/mob/living/proc/ventcrawl), source)                // on while source holds it
//     revoke(M, granted_verb(/mob/living/proc/ventcrawl), source)
//     grant(M, granted_verb(/mob/verb/observe, hidden = TRUE), source)          // off while source holds it
//     grant(C, granted_verb(/client/verb/adminhelp, hidden = TRUE), source, 2 MINUTES)   // timed
//     grant(M, granted_verb(path, verb_name = "Name", verb_desc = "Desc"), source)       // renamed verb
//
// A source's deletion ends its activations, so nothing pairs an add with a remove. Every activation that adds or ends a verb entry calls
// verb_store_sync(), which recomputes the rule above for the key: a type verb that a grant also covered survives the grant's revoke, and a hide
// lifted brings back exactly what the rule says (no mixed-source desync).
//
// What a type has by what it is costs no per-instance store entry: DECLARE_VERB and friends
// (code/__defines/lifecycle_decl.dm) live in the type's declaration table and are applied at init
// (Login for DECLARE_LOGIN_VERB). A per-instance grant is for what can change.
//
// Clients are not datums: a grant to a client goes to the client's /datum/client_verbs holder
// (made on first grant, owned by the client), so client verb sets follow the same rules.
// Sources with no datum of their own (the server config, an admin's hand edit) use
// verb_source(VERB_SOURCE_*), one shared datum per name.

// ---------------------------------------------------------------- keys and sources

/// The store key for verb `verb_path` shown as `name`/`desc` (use VERB_NAMED()).
/proc/verb_named_key(verb_path, name, desc)
	return "[verb_path]\n[replacetext("[name]", "\n", " ")]\n[replacetext("[desc]", "\n", " ")]"

/// The shared source datum named `id` (VERB_SOURCE_*), for grants nothing else owns.
/proc/verb_source(id)
	RETURN_TYPE(/datum/verb_source)
	var/static/list/sources = list()
	var/datum/verb_source/S = sources[id]
	if(!S)
		S = new /datum/verb_source(id)
		sources[id] = S
	return S

/datum/verb_source
	var/id

/datum/verb_source/New(id)
	..()
	src.id = id

// Shared sources live for the round.
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/verb_source)

// ---------------------------------------------------------------- clients

/client
	/// Grant holder for this client's verbs (made on first grant).
	var/datum/client_verbs/verb_store

/// A client's grant target: grants on a client land here.
/datum/client_verbs
	var/client/owner

/datum/client_verbs/New(client/C)
	..()
	rel_set(src, nameof(owner), C)

/// The datum grants on `target` are stored on: a client's holder, or `target` itself.
/// `create`: make a client's holder when it has none (grants); FALSE for reads and revokes.
/proc/verb_grant_target(target, create = TRUE)
	if(!istype(target, /client))
		return target
	var/client/C = target
	if(!C.verb_store && create)
		rel_set(C, nameof(/client::verb_store), new /datum/client_verbs(C)) // its grants die with the client
	return C.verb_store

// ---------------------------------------------------------------- queries

/// What `E` (an atom or a /datum/client_verbs) edits: the atom or the client.
/proc/verb_store_owner(datum/E)
	if(isatom(E))
		return E
	if(istype(E, /datum/client_verbs))
		var/datum/client_verbs/H = E
		return H.owner
	return null

/// The type that declares `verb_path` as a /type/verb/, or FALSE (a /proc/ path, or none).
/proc/verb_static_owner(verb_path)
	var/static/list/owner_of = list()
	var/owner_type = owner_of[verb_path]
	if(isnull(owner_type))
		var/text = "[verb_path]"
		var/at = findtext(text, "/verb/")
		owner_type = (at > 1) ? text2path(copytext(text, 1, at)) : null
		if(!owner_type)
			owner_type = FALSE
		owner_of[verb_path] = owner_type
	return owner_type

/// What the live activations say about verb `key` on `E`: -1 when one hides it (a hide beats a grant), 1 when one grants it, 0 when none does.
/proc/verb_activations_want(datum/E, key)
	var/granted = FALSE
	for(var/list/pool in list(E.rx?.activations, E.rx?.sourced))
		for(var/datum/activation/A as anything in pool)
			if(A.dead)
				continue
			for(var/datum/centry/C as anything in activation_plan(A.def))
				var/datum/entry/entry = C.item
				if(!istype(entry) || entry.kind != ENTRY_VERB || verb_entry_key(entry) != key || verb_entry_target(A, entry) != E)
					continue
				if(entry.args["hidden"])
					return -1
				granted = TRUE
	return granted ? 1 : 0

/// The store's rule for key `key` on `owner` (an atom or client), store entries on `E`.
/proc/verb_store_wants(datum/E, owner, key)
	var/active = verb_activations_want(E, key)
	if(active < 0)
		return FALSE
	var/datum/lifecycle_decls/decls = isatom(owner) ? lifecycle_decls_of(owner) : null
	if(decls && (decls.work & DECL_WORK_VERBS) && decls.verbs_hidden && (key in decls.verbs_hidden))
		return FALSE
	// hidden_verbs() (dx_conventions.md §4): derived from state, applied by the refresh engine.
	if(isatom(owner))
		var/atom/hider = owner
		if(hider.rx?.refresh_hidden_verbs && (key in hider.rx?.refresh_hidden_verbs))
			return FALSE
	if(isatom(owner) && verb_entries_want(owner, key) == FALSE)
		return FALSE // verb_entry(path, hidden = TRUE)
	if(active > 0)
		return TRUE
	// granted_verbs() (capabilities' verbs(), a mob's species and traits): derived, applied by the refresh engine.
	if(isatom(owner))
		var/atom/granter = owner
		if(granter.rx?.refresh_granted_verbs && (key in granter.rx?.refresh_granted_verbs))
			return TRUE
	if(istext(key))
		return FALSE // a named verb exists only while granted
	var/owner_type = verb_static_owner(key)
	if(owner_type && istype(owner, owner_type))
		return TRUE
	// type_verbs(): verbs a type has by what it is (a per-type list, no per-instance entry); a login entry
	// (type_verb(..., login = TRUE)) only once a player has had the mob.
	if(isatom(owner) && (type_derive_flags(owner) & TYPE_DERIVES_TYPE_VERBS))
		if(key in type_verbs_always(owner))
			return TRUE
		if(ismob(owner) && (key in type_verbs_login(owner)))
			var/mob/player = owner
			return !!player.key
	if(isatom(owner) && verb_entries_want(owner, key))
		return TRUE // verb_entry(path, ...) of the type (code/engine/present/verbs.dm)
	if(!decls || !(decls.work & DECL_WORK_VERBS))
		return FALSE
	if(decls.verbs_always && (key in decls.verbs_always))
		return TRUE
	var/var_name = decls.verbs_if?[key]
	if(var_name)
		var/atom/A = owner
		return !!A.vars[var_name]
	if(decls.verbs_login && (key in decls.verbs_login))
		var/mob/M = owner
		return !!M.key
	return FALSE

/// TRUE when verb `key` (a path, or a VERB_NAMED key) is on `target` (an atom or client) now.
/proc/has_verb(target, key)
	if(!target)
		return FALSE
	if(!istext(key))
		var/atom/A = target // clients have verbs too; the var is read the same way
		return key in A.verbs
	var/datum/E = verb_grant_target(target, FALSE)
	var/datum/scheduler_record/rec = E?.om_rec
	return !!rec?.named_verbs?[key]

// ---------------------------------------------------------------- the writer

/// Re-applies the rule for `keys` (a key or a list) on `target`. Call after changing what a
/// DECLARE_VERB_IF var or a type's circumstances say; grants and hides call it themselves.
/proc/verb_store_refresh(target, keys)
	var/datum/E = verb_grant_target(target)
	verb_store_sync(E, islist(keys) ? keys : list(keys))

/// Brings `keys` on `E`'s owner in line with verb_store_wants().
/proc/verb_store_sync(datum/E, list/keys)
	var/owner = verb_store_owner(E)
	if(!owner)
		return
	var/list/add
	var/list/remove
	for(var/key in keys)
		var/wants = verb_store_wants(E, owner, key)
		if(wants == verb_store_present(E, owner, key))
			continue
		if(wants)
			LAZYADD(add, key)
		else
			LAZYADD(remove, key)
	if(add || remove)
		verb_store_write(E, owner, add, remove)

/proc/verb_store_present(datum/E, owner, key)
	if(!istext(key))
		var/atom/A = owner
		return key in A.verbs
	var/datum/scheduler_record/rec = E.om_rec
	return !!rec?.named_verbs?[key]

/// The one place a verbs list changes. `add`/`remove`: keys (paths or VERB_NAMED keys).
/// Tells the client's stat panel when there is one to tell.
/proc/verb_store_write(datum/E, owner, list/add, list/remove)
	var/atom/A = owner // or a client: both have `verbs`
	var/client/C
	if(ismob(owner))
		var/mob/M = owner
		C = M.client
	else if(istype(owner, /client))
		C = owner
	var/list/panel_add
	var/list/panel_remove
	for(var/key in remove)
		var/procpath/P
		if(!istext(key))
			P = key
			A.verbs -= key
		else
			var/datum/scheduler_record/rec = E.om_rec
			P = rec?.named_verbs?[key]
			if(!P)
				continue
			A.verbs -= P
			rec.named_verbs -= key
			if(!length(rec.named_verbs))
				rec.named_verbs = null
		if(C)
			LAZYADD(panel_remove, list(list(P.category, P.name)))
	for(var/key in add)
		var/procpath/P
		if(!istext(key))
			P = key
			A.verbs += key
		else
			var/list/parts = splittext(key, "\n")
			var/verb_path = text2path(parts[1])
			if(!verb_path)
				stack_trace("verb store: bad named verb key [key]")
				continue
			var/datum/scheduler_record/rec = scheduler_record_of(E)
			P = new verb_path(owner, parts[2], length(parts) > 2 ? parts[3] : null)
			LAZYSET(rec.named_verbs, key, P)
		if(C)
			LAZYADD(panel_add, list(list(P.category, P.name, P.desc)))
	if(C)
		C.present_verb_changes(panel_add, panel_remove)

// ---------------------------------------------------------------- declared verbs

/// Init: the type's DECLARE_VERB, DECLARE_VERB_IF and DECLARE_VERB_HIDE lines (lifecycle_decls_init()).
/proc/verb_store_apply_declared(atom/A, datum/lifecycle_decls/decls)
	var/list/add
	for(var/verb_path in decls.verbs_always)
		if(!(verb_path in decls.verbs_hidden))
			LAZYADD(add, verb_path)
	for(var/verb_path in decls.verbs_if)
		if(A.vars[decls.verbs_if[verb_path]])
			LAZYADD(add, verb_path)
	var/list/remove
	for(var/verb_path in decls.verbs_hidden)
		if(verb_path in A.verbs)
			LAZYADD(remove, verb_path)
	if(add || remove)
		verb_store_write(A, A, add, remove)

/// Login: the type's login verbs (type_verb(..., login = TRUE) in type_verbs(), which DECLARE_LOGIN_VERB expands
/// to; the old declaration-table list while any type still fills it).
/proc/verb_store_login(mob/M)
	verb_entries_login(M)
	if(type_derive_flags(M) & TYPE_DERIVES_TYPE_VERBS)
		var/list/login = type_verbs_login(M)
		if(length(login))
			verb_store_sync(M, login)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(M)
	if(!decls?.verbs_login)
		return
	verb_store_sync(M, decls.verbs_login)


/client/proc/present_verb_changes(list/add, list/remove)
	return
