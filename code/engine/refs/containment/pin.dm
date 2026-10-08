// Pins (doc/rewrite/containment.md Â§4.7, C10): the generic demand model that
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

/// Pin reads do not allocate per-entity state.
/atom/movable/proc/latent_pin_count(reason)
	return rx?.containment_pins?[reason] || 0

/atom/movable/proc/latent_pin(reason)
	var/datum/rx_state/S = rx_of(src)
	LAZYINITLIST(S.containment_pins)
	S.containment_pins[reason] = (S.containment_pins[reason] || 0) + 1

/atom/movable/proc/latent_unpin(reason)
	var/datum/rx_state/S = rx
	if(!S?.containment_pins)
		return
	var/count = S.containment_pins[reason]
	if(!count)
		return
	if(count <= 1)
		S.containment_pins -= reason
	else
		S.containment_pins[reason] = count - 1
	if(!length(S.containment_pins))
		S.containment_pins = null

/atom/movable/proc/latent_explicitly_pinned()
	return length(rx?.containment_pins) > 0

/// The single read: whether `A` must stay real right now, for any reason.
/// Combines explicit pins, the collapse blockers (behaviour, outside refs,
/// the weakref gap, state.md Â§1/collapse.dm) and sitting on a turf.
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
