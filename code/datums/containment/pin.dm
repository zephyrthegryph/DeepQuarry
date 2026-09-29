// Pins (doc/rewrite/containment.md §4.7, C10): the generic demand model that
// decides whether an atom needs to stay real. No slot kind decides this by
// itself -- whatever actually needs `A` real takes a pin, and `A` stays real
// for as long as any pin is held. can_be_latent() (latency_policy.dm) never
// has to know *why* something is pinned, only whether it is.
//
// Two kinds of pin:
//   Explicit  A consumer calls latent_pin(reason) when it starts needing a
//             real atom (a storage screen showing it, a click catcher, a
//             component that only works on a live atom) and latent_unpin()
//             when it stops. Reason-keyed so two independent holders of the
//             same reason (two viewers of one storage) don't unpin each
//             other's need early.
//   Implicit  Cheap and always accurate to compute on demand, so nothing has
//             to remember to call anything: state_collapse_blockers() being
//             non-empty (running behaviour, outside refs, the weakref gap),
//             and sitting directly on a turf (isturf(loc)) -- visible to
//             everyone nearby the moment it's there, and nobody's job to
//             notice it left.
//
// Appearance-only consumers (a mob overlay, an inventory icon) don't pin:
// they can draw from the entry (type + state blob) without a real atom.

/atom/movable/var/tmp/list/latent_pins

/// Takes a pin on `src`: it may not be latent while this (or any other) pin
/// is held. Reason is any stable key (a type path, a string); repeatable.
/atom/movable/proc/latent_pin(reason)
	LAZYINITLIST(latent_pins)
	latent_pins[reason] = (latent_pins[reason] || 0) + 1

/// Releases one pin of `reason`. Excess unpins (no matching pin) are a no-op,
/// not an error: Destroy() paths and out-of-order UI teardown are common.
/atom/movable/proc/latent_unpin(reason)
	if(!latent_pins)
		return
	var/count = latent_pins[reason]
	if(!count)
		return
	if(count <= 1)
		latent_pins -= reason
	else
		latent_pins[reason] = count - 1
	if(!length(latent_pins))
		latent_pins = null

/// Whether `src` holds any explicit pin right now, ignoring implicit ones.
/atom/movable/proc/latent_explicitly_pinned()
	return LAZYLEN(latent_pins) > 0

/// The single read: whether `A` must stay real right now, for any reason.
/// Combines explicit pins, the collapse blockers (behaviour, outside refs,
/// the weakref gap, state.md §1/collapse.dm) and sitting on a turf.
/// `caller_refs`: references to `A` held by the frames above this one (each caller's own
/// variable or argument naming it), which the collapse check must not count as outside holders.
/// The default, 1, is a caller holding A in one variable.
/proc/dq_latent_pinned(atom/movable/A, caller_refs = 1)
	if(!A || QDELETED(A))
		return TRUE
	if(A.latent_explicitly_pinned())
		return TRUE
	if(isturf(A.loc))
		return TRUE
	// held_refs: this frame's own two (the `A` argument, and the reference a frame keeps to the
	// last object it called a method on: latent_explicitly_pinned() above) plus every caller
	// frame's reference. A fixed 2 left the callers' references uncounted, so every item the sweep
	// offered (loop var -> dq_latent_attempt_collapse -> can_be_latent -> here) read as held from
	// outside and the sweep never collapsed anything. A caller that itself called a method on A
	// holds that extra reference too and must count it in caller_refs.
	var/list/blockers = A.state_collapse_blockers(2 + caller_refs)
	if(!length(blockers))
		return FALSE
	GLOB.latency_last_pin_reason = jointext(blockers, "; ")
	return TRUE

/// The collapse blockers behind the last dq_latent_pinned() that returned TRUE for them.
GLOBAL_VAR_INIT(latency_last_pin_reason, "")
