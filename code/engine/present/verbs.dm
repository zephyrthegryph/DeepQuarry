// Verb entries and granted verbs (doc/rewrite/final_api.html, section 13 "Verbs and abilities"): the one declaration of a verb a type or a capability has,
// kept in the verb store (code/datums/om/grant_verbs.dm), which stays the only writer of a verbs list.
//
//   CAPABILITIES(/mob/living/simple_mob/vore/wolf)
//       verb_entry(/mob/living/proc/set_size, login = TRUE)           on a mob once a player has had it (the old DECLARE_LOGIN_VERB)
//       verb_entry(/mob/living/proc/ventcrawl)                         on every instance from init (DECLARE_VERB)
//       verb_entry(/obj/item/clothing/proc/change_color, when = nameof(polychromic))   while the condition holds (DECLARE_VERB_IF)
//       verb_entry(/mob/verb/toggle_gun_mode, hidden = TRUE)           never on an instance: hides what the type inherits (DECLARE_VERB_HIDE)
//
//   grant(M, granted_verb(/mob/living/proc/ventcrawl), source)         a runtime verb: on M while `source` holds it
//   grant(M, hidden_verb(/mob/verb/observe), source)                   a runtime hide (hidden_verb() is the legacy store form, code/datums/reactions/state.dm)
//   revoke(M, granted_verb(/mob/living/proc/ventcrawl), source)
//
// A type-level entry is part of the type: applied when an instance initializes (and at Login for login = TRUE), with no per-instance store entry. A `when =`
// condition is a var (or condition tree) of the instance whose changes the change layer publishes; the entry re-evaluates on each, through a synthesized
// on_change hook, so a setter writing the var is all the type does (the old DECLARE_VERB_IF needed a verb_store_refresh() after every write; that call still
// works). An entry inside a capability is a grant: applied for as long as the capability's activation lives and gone with it, so a verb granted through a
// capability, an op's grants() or a while_slotted() ends with its source. `on = ON_SOURCE` puts the verb on the activation's source instead of its holder
// (an item's own verb, listed while a mob carries it: held_verb()); `name =` / `desc =` rename the verb (VERB_NAMED).
//
// Which panel tab a verb is listed under is the verb's own category (`set category = ...`, the VERB_CAT_* defines): the store tells the client's stat panel
// when a verb is added or removed. A verb a gameplay ability starts is an op (menu()) under "Abilities"; a verb entry is for what the client does.

/// verb_entry(path, login =, when =, hidden =, name =, desc =, on =): see the header.
/proc/verb_entry(verb_path, login = FALSE, when = null, hidden = FALSE, name = null, desc = null, on = ON_HOLDER)
	if(isnull(verb_path) || istext(verb_path))
		declare_report("verb_entry(): the first argument must be a verb or proc path, got [isnull(verb_path) ? "null" : "[verb_path]"]")
		return null
	if(hidden && (login || !isnull(when)))
		declare_report("verb_entry([verb_path]): a hidden verb has neither login nor when")
		return null
	return entry_make(ENTRY_VERB, null, list("path" = verb_path, "login" = login, "when" = when, "hidden" = hidden, "name" = name, "desc" = desc, "on" = on))

/// The store key of a verb entry: the path, or the VERB_NAMED key when it renames the verb.
/proc/verb_entry_key(datum/entry/E)
	var/name = E.args["name"]
	if(isnull(name))
		return E.args["path"]
	return verb_named_key(E.args["path"], name, E.args["desc"])

// ---- type-level entries ----

/// A type's verb entries, split once: always (list of keys), login, whens (key -> condition), hidden. Shared; never written after the build.
/datum/verb_entry_set
	var/list/always
	var/list/login
	var/list/whens
	var/list/hidden

GLOBAL_LIST_EMPTY(verb_entry_sets) // type -> /datum/verb_entry_set, or FALSE for a type with none

/// The verb entries of `holder`'s type (a type-level capability's included), or null when it declares none.
/proc/verb_entries_of(atom/holder)
	RETURN_TYPE(/datum/verb_entry_set)
	if(!GLOB.verb_entry_sets)
		return null // the globals are still being built
	var/known = GLOB.verb_entry_sets[holder.type]
	if(!isnull(known))
		return known || null
	var/datum/type_table/T = table_of(holder)
	if(T == table_empty())
		return null // the globals are still being built: nothing is declared yet, nothing is cached
	var/datum/verb_entry_set/S
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_VERB))
		var/datum/entry/E = C.item
		if(!S)
			S = new
		var/key = verb_entry_key(E)
		if(E.args["hidden"])
			LAZYOR(S.hidden, key)
		else if(E.args["login"])
			LAZYOR(S.login, key)
		else if(!isnull(E.args["when"]))
			LAZYSET(S.whens, key, E.args["when"])
		else
			LAZYOR(S.always, key)
	GLOB.verb_entry_sets[holder.type] = S || FALSE
	return S

/// The verb store's rule for a type-level entry: FALSE when the type hides `key`, TRUE when an entry puts it on `owner` now (always; a `when` that holds; login with a
/// player), null when the type's entries say nothing (what the type inherits or another source grants stands).
/proc/verb_entries_want(atom/owner, key)
	var/datum/verb_entry_set/S = verb_entries_of(owner)
	if(!S)
		return null
	if(S.hidden && (key in S.hidden))
		return FALSE
	if(S.always && (key in S.always))
		return TRUE
	if(S.whens && (key in S.whens))
		return change_condition(owner, S.whens[key]) ? TRUE : null
	if(S.login && (key in S.login))
		var/mob/M = owner
		return (istype(M) && M.key) ? TRUE : null
	return null

/// Instance init: the entries that hold now are on the instance (one write), the hidden ones off.
/proc/verb_entries_init(atom/holder)
	var/datum/verb_entry_set/S = verb_entries_of(holder)
	if(!S)
		return
	var/list/keys = list()
	keys |= S.always
	keys |= S.hidden
	if(S.whens)
		keys |= S.whens
	if(length(keys))
		verb_store_sync(holder, keys)

/// Login: the entries of login = TRUE are on the mob now that a player has it (verb_store_login() calls this).
/proc/verb_entries_login(mob/M)
	var/datum/verb_entry_set/S = verb_entries_of(M)
	if(S?.login)
		verb_store_sync(M, S.login)

/// The wake of a verb entry's `when =`: the condition changed value, so every conditional entry of the holder re-evaluates.
/proc/verb_entries_changed(datum/act/A)
	var/atom/holder = A.holder
	if(!istype(holder) || QDELETED(holder))
		return
	var/datum/verb_entry_set/S = verb_entries_of(holder)
	if(S?.whens)
		verb_store_sync(holder, S.whens)

/// The change hook of one `when =` verb entry: ANY change of its condition runs verb_entries_changed(). Built once per entry (hooks.dm asks for it).
/proc/verb_entry_hook_entry(datum/entry/E)
	var/static/list/made = list()
	var/datum/entry/known = made[E.sig]
	if(!known)
		known = entry_make(ENTRY_ON_CHANGE, null, list("cond" = E.args["when"], "edge" = ANY), list(then(GLOBAL_PROC_REF(verb_entries_changed))))
		made[E.sig] = known
	return known

// ---- entries of a capability: a grant ----

/datum/entry_engine/verb_entry_grant
	kind = ENTRY_VERB

/datum/entry_engine/verb_entry_grant/validate(datum/activation/A, datum/entry/E)
	if(E.args["login"] || !isnull(E.args["when"]))
		return "verb_entry() inside a capability is a grant that ends with it: login and when are for a type's own entries (use an enclosing when() block)"
	return null

/// Where a granted verb lands and who holds it: on = ON_SOURCE puts it on the activation's source (an item's own verb) held by the activation's holder, else on the
/// holder held by the activation's source (a shared verb_source() for a source that is a SOURCE_DEF id): remove() lets go of exactly this hold.
/proc/verb_grant_sides(datum/activation/A, datum/entry/E)
	if(E.args["on"] == ON_SOURCE)
		return list(A.source, A.holder)
	return list(A.holder, isdatum(A.source) ? A.source : verb_source("granted_verb"))

/datum/entry_engine/verb_entry_grant/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	var/list/sides = verb_grant_sides(A, E)
	var/datum/target = sides[1]
	var/datum/store_source = sides[2]
	if(!isdatum(target) || QDELETED(target) || !isdatum(store_source) || QDELETED(store_source))
		return FALSE
	grant_hold(target, E.args["hidden"] ? GRANT_VERB_HIDE : GRANT_VERB, verb_entry_key(E), store_source)
	return TRUE

/datum/entry_engine/verb_entry_grant/remove(datum/activation/A, datum/entry/E)
	var/list/sides = verb_grant_sides(A, E)
	var/datum/target = sides[1]
	var/datum/store_source = sides[2]
	if(!isdatum(target) || QDELETED(target) || !isdatum(store_source))
		return
	grant_release(target, E.args["hidden"] ? GRANT_VERB_HIDE : GRANT_VERB, verb_entry_key(E), store_source)

// ---- granted_verb(): a verb as a capability ----

CAPABILITY_DEF(granted_verb, CAP_GRANTED_VERB, key = verb_path, verb_path = null, verb_name = null, verb_desc = null, on = ON_HOLDER, hidden = FALSE)

/// grant(E, granted_verb(path), source): the verb is on E while `source` holds it (`hidden = TRUE`: off E while it holds it). It is a one-entry capability (a verb_entry), so every way a capability ends
/// ends it: revoke(), the source's deletion, lasts =, a while_slotted() scope.
/datum/capability/def/granted_verb/entries()
	return list(verb_entry(verb_path, name = verb_name, desc = verb_desc, on = on, hidden = hidden))
