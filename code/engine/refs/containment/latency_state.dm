// latency: lazy state of /atom/movable (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// The latency sweep's clocks (latency_policy.dm): read with STATE_PEEK(A, latency, field), write with STATE_SET(A, latency, field, value).

/datum/latency_state
	parent_type = /datum/lazy_state
	/// The sweep's idle clock: the last point on the world clock something touched the atom (dq_latent_touch()).
	var/latent_touched_at = 0
	/// When the sweep may offer this atom again after a refusal (a world.time end).
	var/latent_refused_until = 0

// Engine-owned state is not read-driven tracked (the framework's bookkeeping publishes itself), so STATE_SET()'s setters are written here.
/datum/latency_state/proc/set_latent_touched_at(value)
	latent_touched_at = value
	return TRUE

/datum/latency_state/proc/set_latent_refused_until(value)
	latent_refused_until = value
	return TRUE
