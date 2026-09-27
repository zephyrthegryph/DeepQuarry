// Native (Rust-owned) watches (doc/rewrite/object_model_core.md, Verdigris).
//
// A watch is declared by its owner: what to watch (a threshold, band or set
// on a heat body or cell, a gas mixture's dependency mask, ...) and the proc
// to call on the owner when it fires. The watch is its own handle: an
// entity in SSvg's table, which is also the subscriber Rust wakes carry. The
// domain drains hand each wake to om_native_dispatch(), which finds the
// watch by that handle and calls the owner's proc with the watch first:
//
//   call(owner, callback)(watch, ...wake arguments)
//
// Owners never compare handles or keep owner maps: each watch knows its own
// callback. Cancel with qdel(watch) (or watch.cancel()). The watch holds its
// owner weakly: a watch whose owner is gone is dropped at its next wake.
//
// Domain subtypes (/datum/native_watch/heat, /gas) implement register() and
// unregister() against their Rust binds.

/datum/native_watch
	/// OM handle of the datum whose proc runs (weak: the owner holds its watches, not the reverse).
	var/owner_ref
	/// Proc path called on `owner` as (watch, ...).
	var/callback
	/// SSvg entity handle: this watch's identity, and the subscriber Rust reports.
	var/handle = 0

/datum/native_watch/New(datum/owner, callback)
	..()
	owner_ref = om_handle(owner)
	src.callback = callback
	handle = SSvg.bind_datum(src)

/datum/native_watch/Destroy()
	cancel()
	return ..()

/// Stops the watch: drops its Rust registration and frees its handle.
/datum/native_watch/proc/cancel()
	if(!handle)
		return
	unregister()
	SSvg.unbind_datum(src, handle)
	handle = 0
	owner_ref = null

/// Registers with the Rust domain. Returns FALSE if it was refused.
/datum/native_watch/proc/register()
	return TRUE

/// Drops the Rust registration (the handle stays).
/datum/native_watch/proc/unregister()
	return

/// Calls the owner's proc with this watch and `args`.
/datum/native_watch/proc/fire(list/arguments)
	var/datum/owner = om_resolve(owner_ref)
	if(!owner)
		qdel(src)
		return
	call(owner, callback)(arglist(list(src) + arguments))

/// Finds the live watch behind `handle`, or null.
/proc/om_native_watch_of(handle)
	var/datum/native_watch/W = SSvg.entity_lookup(handle)
	if(!istype(W) || W.handle != handle || QDELETED(W))
		return null
	return W

/// A Rust wake for the watch behind `handle`: runs its owner's proc.
/proc/om_native_dispatch(handle, list/arguments)
	var/datum/native_watch/W = om_native_watch_of(handle)
	W?.fire(arguments)
