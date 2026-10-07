// Native (Rust-owned) watches (doc/rewrite/object_model_core.md, Verdigris).
//
// A watch is declared by its owner: what to watch (a threshold, band or set
// on a heat body or cell, a gas mixture's dependency mask, ...) and the proc
// to call on the owner when it fires. The watch is its own handle: an
// entity in SSvg's table, which is also the subscriber Rust wakes carry. The
// domain drains hand each wake to kernel_native_native_dispatch(), which finds the
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
	/// NATIVE_SRC_* this watch's deliveries are counted under (native_adapter.dm).
	var/delivery_source = NATIVE_SRC_OTHER
	/// The on_cross reaction this watch feeds (native_watch_for_reaction()): its crossings deliver through
	/// rx_crossed() instead of the owner's callback.
	var/datum/reaction/rx_reaction
	/// The observer listener of a dynamic on_cross this watch feeds, if any.
	var/datum/rx_listener/rx_listener

/datum/native_watch/New(datum/owner, callback)
	..()
	owner_ref = entity_handle(owner)
	src.callback = callback
	handle = bind_native()

/// Phase 1 (unbind): the Rust-side watch is cancelled.
/datum/native_watch/lifecycle_unbind()
	. = ..()
	cancel()

/// Stops the watch: drops its Rust registration and frees its handle.
/datum/native_watch/proc/cancel()
	if(!handle)
		return
	unregister()
	unbind_native(handle)
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
	var/datum/owner = resolve_handle(owner_ref)
	if(!owner)
		spent(src)
		return
	native_fired(delivery_source)
	call(owner, callback)(arglist(list(src) + arguments))

/// The frame reported this watch crossing `band` (`detail` is the record's numbers): by default the
/// owner's callback runs with them. World watches queue on their lane, heat watches pick the wake or
/// set-crossing form (native_crossed(), code/datums/native/system.dm).
/datum/native_watch/proc/crossed(band, list/detail)
	fire(detail)
	return TRUE

/// Finds the live watch behind `handle`, or null.
/proc/kernel_native_native_watch_of(handle)
	var/datum/native_watch/W = native_watch_provider().lookup(handle)
	if(!istype(W) || W.handle != handle || QDELETED(W))
		return null
	return W

/// A Rust wake for the watch behind `handle`: runs its owner's proc.
/proc/kernel_native_native_dispatch(handle, list/arguments)
	var/datum/native_watch/W = kernel_native_native_watch_of(handle)
	W?.fire(arguments)
