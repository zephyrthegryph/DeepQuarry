/// The one wait outside the kernel (doc/rewrite/kernel.md sec 1.7). A waiter is resolved by the thing the
/// caller waits for: a tgui modal's submit, an io_job on_done, or a timeout. await() is valid only inside a
/// dispatched (already detached) handler.
/datum/waiter
	var/done = FALSE
	var/result
	/// world.time the waiter times out at; 0: never.
	var/deadline = 0
	var/cancelled = FALSE
	var/timed_out = FALSE
	var/created_at = 0

/datum/waiter/New(timeout = WAITER_NO_TIMEOUT)
	..()
	created_at = world.time // ALLOW(sys_world_time_write): the kernel clock: a scheduler timestamp of the kernel itself, not a per-entity expiry
	if(timeout > 0)
		deadline = world.time + timeout // ALLOW(sys_world_time_write): the kernel clock: a scheduler timestamp of the kernel itself, not a per-entity expiry

/// The kernel's list of open waiters, in creation order.
/proc/kernel_waiters()
	var/static/list/open = list() // ALLOW(sys_static_getter): the kernel's list of open waiters: a mutable registry, not a constant table
	return open

/// Resolves `W` with `result`. Returns TRUE when this call resolved it (a second resolve is ignored).
/proc/waiter_resolve(datum/waiter/W, result)
	if(!W || W.done)
		return FALSE
	W.done = TRUE
	W.result = result
	var/list/open = kernel_waiters()
	open -= W
	return TRUE

/// Resolves `W` as cancelled (its owner is gone): the awaiting proc wakes with a null result.
/proc/waiter_cancel(datum/waiter/W)
	if(!waiter_resolve(W, null))
		return FALSE
	W.cancelled = TRUE
	return TRUE

/// The once-per-tick check of every open waiter: times out the overdue ones. Idempotent within a tick,
/// so every awaiting proc may call it and only the first does the work.
/proc/kernel_waiters_pass()
	var/static/last_pass = -1
	if(last_pass == world.time)
		return
	last_pass = world.time // ALLOW(sys_world_time_write): the kernel clock: a scheduler timestamp of the kernel itself, not a per-entity expiry
	var/list/open = kernel_waiters()
	for(var/datum/waiter/W as anything in open.Copy())
		if(W.deadline && world.time >= W.deadline && !W.done) // ALLOW(sys_world_time_expiry): the kernel clock: a scheduler timestamp of the kernel itself, not a per-entity expiry
			W.timed_out = TRUE
			waiter_resolve(W, null)

/// Parks the calling proc until `W` resolves, is cancelled or times out; returns the result (null after
/// a cancel or a timeout; check W.timed_out). Replaces UNTIL() and per-modal stoplag() loops.
/proc/await(datum/waiter/W)
	if(!W)
		return null
	if(!W.done)
		var/list/open = kernel_waiters()
		open |= W
	while(!W.done)
		kernel_waiters_pass()
		if(W.done)
			break
		sleep(world.tick_lag) // ALLOW(scheduler): the kernel's own wait; the one place a handler parks
	return W.result

/// Telemetry: how many waiters are open and the age of the oldest, in deciseconds.
/proc/kernel_waiter_metrics()
	var/list/open = kernel_waiters()
	var/oldest = 0
	if(length(open))
		var/datum/waiter/first = open[1]
		oldest = world.time - first.created_at
	return alist("open" = length(open), "oldest_age" = oldest)
