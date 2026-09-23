/**
 * A grant kind: what actually happens when a mob picks up (or loses) its first
 * (last) source of some grant. One singleton per GRANT_KIND_* (code/__defines/grants.dm),
 * registered once at world start. See kind_ability.dm / kind_language.dm / kind_factors.dm.
 *
 * To add a new kind: pick the next free GRANT_KIND_* id, subtype /datum/grant_kind
 * with `kind = GRANT_KIND_YOURS`, implement on_grant()/on_revoke(), and `new` it once
 * at file scope (GLOBAL_DATUM_INIT or a bare `new` - see the existing kinds). Nothing
 * else needs to know it exists; grant()/revoke() look it up by id.
 */
/datum/grant_kind
	/// The GRANT_KIND_* this instance handles.
	var/kind

/datum/grant_kind/New()
	. = ..()
	if(isnull(kind))
		CRASH("[type] has no kind set")
	if(grant_kind_registry()[kind])
		CRASH("GRANT_KIND_ [kind] is already registered to [grant_kind_registry()[kind]]")
	grant_kind_registry()[kind] = src

/// `id` just went from zero sources to one, on `M`, via `source`.
/datum/grant_kind/proc/on_grant(mob/M, id, datum/source)
	return

/// `id` just went from one source to zero, on `M`. `source` is the one that revoked
/// (already removed from the source list) - it may be QDELETED when this runs.
/datum/grant_kind/proc/on_revoke(mob/M, id, datum/source)
	return

/// GRANT_KIND_* -> /datum/grant_kind. Built lazily so kind singletons can register
/// in any include order.
/proc/grant_kind_registry()
	var/static/list/registry = list()
	return registry

/// The registered /datum/grant_kind for `kind`, or null.
/proc/grant_kind_by_id(kind)
	return grant_kind_registry()[kind]
