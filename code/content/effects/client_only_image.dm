/*
* Sending images to clients can cause memory leaks if not handled safely.
* This is a wrapper for handling it safely. Mostly used by self deleting effects.
*/
/image/client_only
	/// Relation list view: the clients this image is shown to (clients are roots: untracked,
	/// a client that leaves reads null). lifecycle_dematerialize() takes it off each one.
	var/list/clients

/// Self-deleting client images waiting on their expiry timer. The timer names
/// its target by handle (weak), and a client's images list is the only other
/// reference, so an echo shown to nobody (or to a client that left) would be
/// collected by BYOND before its qdel() ran. This list is what owns them.
GLOBAL_LIST_EMPTY(client_only_images_expiring)

/// Deletes this image after `delay`, keeping it alive until then.
/image/client_only/proc/expire_in(delay)
	GLOB.client_only_images_expiring += src // ALLOW(registry): /image is not a datum (no registry hooks) and joins only once it starts expiring
	after(null, delay, GLOBAL_PROC_REF(qdel), with = list(src))

/image/client_only/proc/append_client(client/C)
	C.images += src
	rel_add(src, nameof(clients), C)

CAPABILITIES(/image/client_only)
	ref_many(nameof(clients))

// comes off every client it was shown to (clients aren't datums, so no pair can do it).
/image/client_only/lifecycle_dematerialize()
	for(var/client/C in clients)
		C.images -= src
	..()
	GLOB.client_only_images_expiring -= src

// Mostly for motion echos, but someone will probably find another use for it... So parent type gets it instead!
/image/client_only/proc/place_from_root(turf/At)
	pixel_x = ((At.x - loc.x) * 32)
	pixel_y = ((At.y - loc.y) * 32)
