/**
 * Generic grant system (doc/rewrite/grants.md): the ONE place any subsystem records
 * "this source gives this mob that thing", so nothing reimplements source-tracked,
 * refcounted grants for itself. See code/datums/abilities/ability.dm (ABILITY),
 * code/modules/mob/language/language.dm (LANGUAGE) and code/modules/body/factors.dm
 * (FACTORS) for the three kinds built on this.
 *
 * A grant is keyed by (mob, kind, id, source) - kind is a GRANT_KIND_* define
 * (code/__defines/grants.dm), id is whatever that kind uses to name what's granted
 * (a string/number id for ABILITY and LANGUAGE, the source's own factor table for
 * FACTORS), and source is the datum that owns the grant (never a string). Grants are
 * refcounted per (mob, kind, id): the first source to grant it calls the kind's
 * on_grant(), the last to revoke it calls on_revoke() - two sources granting the same
 * thing never fight each other or need the caller to track who else granted it.
 *
 * Whoever calls grant() owns calling revoke() when their source goes away - same
 * discipline as signals and components. Forgetting is still caught: deleting the
 * source datum auto-revokes every grant it made, across every kind and every mob
 * (COMSIG_QDELETING, via the source index below).
 *
 *	// Granting (an item, implant, organ, trait, component, mind, ...):
 *	grant(L, GRANT_KIND_ABILITY, ABILITY_ID_EXAMPLE, src)
 *	// ... and when that source goes away, if it isn't simply qdel'd:
 *	revoke(L, GRANT_KIND_ABILITY, ABILITY_ID_EXAMPLE, src)
 *
 *	// A source leaving a mob entirely (unequip, uninstall) without being deleted:
 *	revoke_all(L, src)
 *
 *	// Reading:
 *	L.has_grant(GRANT_KIND_ABILITY, id)      // any source granting it right now?
 *	L.grant_sources(GRANT_KIND_ABILITY, id)  // the list of sources, for UI/debugging
 *	grants_from(src)                         // every (mob, kind, id) src currently grants
 */

/mob/var/list/grants // GRANT_KIND_* -> (id -> list of sources). LAZYLIST: null on a mob with no grants.

/// Base type for a source that exists only to be a grant()/revoke() source - no
/// behaviour of its own, just an identity. Use this instead of a bare /datum when a
/// source doesn't otherwise need to be anything (see kind_language.dm's
/// legacy_primitive_speech sentinel).
/datum/grant_source

/// `source` now grants `id` (a GRANT_KIND_* `kind`) to `M`. Idempotent: granting the
/// same (kind, id, source) twice is a no-op. Calls the kind's on_grant() the first
/// time ANY source grants this (kind, id) to `M`.
/proc/grant(mob/M, kind, id, datum/source)
	if(!M || isnull(id) || !source)
		CRASH("grant() needs a mob, an id and a source")
	LAZYINITLIST(M.grants)
	LAZYINITLIST(M.grants[kind])
	var/list/sources = M.grants[kind][id]
	if(!sources)
		sources = list()
		M.grants[kind][id] = sources
	if(source in sources)
		return
	var/first_grant = !length(sources)
	sources += source
	_grant_index_add(M, kind, id, source)
	if(first_grant)
		var/datum/grant_kind/K = grant_kind_by_id(kind)
		if(K)
			K.on_grant(M, id, source)
		else
			stack_trace("grant(): no /datum/grant_kind registered for kind [kind]")

/// `source` no longer grants `id` to `M`. Calls the kind's on_revoke() only once
/// every source has revoked. A no-op if `source` never granted this.
/proc/revoke(mob/M, kind, id, datum/source)
	var/list/sources = M?.grants?[kind]?[id]
	if(!sources || !(source in sources))
		return
	sources -= source
	_grant_index_remove(M, kind, id, source)
	if(length(sources))
		return
	M.grants[kind] -= id
	if(!length(M.grants[kind]))
		M.grants -= kind
		if(!length(M.grants))
			M.grants = null
	var/datum/grant_kind/K = grant_kind_by_id(kind)
	if(K)
		K.on_revoke(M, id, source)
	else
		stack_trace("revoke(): no /datum/grant_kind registered for kind [kind]")

/// Revoke every grant `source` holds on `M`, across every kind. Use this when a
/// source leaves a mob without being deleted (unequip, uninstall, a modifier
/// expiring) - a deleted source is handled automatically via COMSIG_QDELETING.
/proc/revoke_all(mob/M, datum/source)
	if(!M?.grants || !source)
		return
	var/list/to_revoke = list()
	for(var/kind in M.grants)
		var/list/by_id = M.grants[kind]
		for(var/id in by_id)
			if(source in by_id[id])
				to_revoke += list(list(kind, id))
	for(var/list/pair in to_revoke)
		revoke(M, pair[1], pair[2], source)

/// TRUE if any source currently grants `id` (a GRANT_KIND_* `kind`) to this mob.
/mob/proc/has_grant(kind, id)
	return length(grants?[kind]?[id]) > 0

/// The sources currently granting `id` (a GRANT_KIND_* `kind`) to this mob, for
/// UI/debugging/queries. Null if none. Never mutate the returned list.
/mob/proc/grant_sources(kind, id)
	return grants?[kind]?[id]

// ---------------------------------------------------------------------------
// Source index: which (mob, kind, id) triples a given source currently grants.
// This is what makes grants_from(source) possible and what lets a deleted source
// auto-revoke everything it granted, without every source having to register its
// own COMSIG_QDELETING handler.

/// source (by ref) -> list of /datum/grant_link. Only sources that currently grant
/// something appear here - nothing is allocated for a source with no grants.
GLOBAL_LIST_EMPTY(grant_source_index)

/datum/grant_link
	var/mob/M
	var/kind
	var/id

/datum/grant_link/New(mob/M, kind, id)
	src.M = M
	src.kind = kind
	src.id = id

/datum/grant_link/Destroy(force)
	M = null
	return ..()

/// The singleton that listens for a granting source's deletion. One instance, so
/// registering/unregistering COMSIG_QDELETING doesn't need a per-source datum.
/datum/grants_manager
	var/list/registered_sources = list()

GLOBAL_DATUM_INIT(grants_manager, /datum/grants_manager, new)

/datum/grants_manager/proc/on_source_qdeleting(datum/source)
	SIGNAL_HANDLER
	var/list/entries = GLOB.grant_source_index[source]
	if(!entries)
		return
	GLOB.grant_source_index -= source
	registered_sources -= source
	for(var/datum/grant_link/link as anything in entries)
		if(link.M)
			revoke(link.M, link.kind, link.id, source)

/proc/_grant_index_add(mob/M, kind, id, datum/source)
	var/list/entries = GLOB.grant_source_index[source]
	if(!entries)
		entries = list()
		GLOB.grant_source_index[source] = entries
		GLOB.grants_manager.registered_sources += source
		GLOB.grants_manager.RegisterSignal(source, COMSIG_QDELETING, TYPE_PROC_REF(/datum/grants_manager, on_source_qdeleting))
	entries += new /datum/grant_link(M, kind, id)

/proc/_grant_index_remove(mob/M, kind, id, datum/source)
	var/list/entries = GLOB.grant_source_index[source]
	if(!entries)
		return
	for(var/datum/grant_link/link as anything in entries)
		if(link.M == M && link.kind == kind && link.id == id)
			entries -= link
			qdel(link)
			break
	if(!length(entries))
		GLOB.grant_source_index -= source
		GLOB.grants_manager.registered_sources -= source
		GLOB.grants_manager.UnregisterSignal(source, COMSIG_QDELETING)

/// Every grant `source` currently holds, as a list of /datum/grant_link (mob, kind,
/// id). Null if it grants nothing right now. Never mutate the returned list.
/proc/grants_from(datum/source)
	return GLOB.grant_source_index[source]
