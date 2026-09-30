/// Urgent requests (doc/rewrite/kernel.md sec 1.2 phase U).
///
/// request_urgent(member, work, deadline) asks the kernel to run one member's work item ahead of its cadence,
/// from a slice of the tick reserved for it (KERNEL_URGENT_SHARE, phase U). The rules:
///   - dedup: one pending request per (member, work). A second request keeps the earlier deadline;
///   - execution token: the run stamps the item's last-run time for that member (work_item.take_dt), so the
///     cadence pass that follows applies only the time since then, never the same span twice, and skips the
///     member outright when it already ran at this instant;
///   - breach metric: a request still pending, or run, after its deadline is counted once in `urgent_breaches`,
///     and the lateness of a late run is summed. Late runs still happen: a breach is a measurement.
/// Only an item declared `urgent = TRUE` accepts requests. At least one request runs per tick even when the
/// slice is spent, so a full queue cannot starve the earliest deadline.

/datum/urgent_request
	var/datum/work_item/work
	/// The member the work runs for, or null for a memberless item.
	var/datum/member
	/// Absolute world.time by which the work should have run.
	var/deadline = 0
	var/requested_at = 0
	var/breached = FALSE

/// world.time `delay` deciseconds from now, for request_urgent()'s deadline.
/proc/urgent_deadline(delay)
	return world.time + delay

/// Asks for `member`'s run of `work` (a /datum/work_item, or its key) by `deadline` (absolute world.time). Returns the
/// pending request, or null when `work` is unknown, not urgent, or parked.
/proc/request_urgent(datum/member, work, deadline)
	var/datum/controller/kernel/K = kernel()
	return K.request_urgent(member, work, deadline)

/datum/controller/kernel/proc/request_urgent(datum/member, work, deadline)
	var/datum/work_item/W = istype(work, /datum/work_item) ? work : work_by_key["[work]"]
	if(!W || !W.urgent || W.parked)
		return null
	urgent_requested++
	var/token = member || W
	var/datum/urgent_request/existing = W.urgent_pending?[token]
	if(existing)
		urgent_deduped++
		if(deadline < existing.deadline)
			existing.deadline = deadline
			urgent_queue -= existing
			queue_urgent(existing)
		return existing
	var/datum/urgent_request/R = new
	R.work = W
	R.member = member
	R.deadline = deadline
	// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
	R.requested_at = world.time
	LAZYSET(W.urgent_pending, token, R)
	queue_urgent(R)
	return R

/// Inserts `R` into the queue by deadline (earliest first; equal deadlines keep request order).
/datum/controller/kernel/proc/queue_urgent(datum/urgent_request/R)
	var/at = length(urgent_queue) + 1
	for(var/i in 1 to length(urgent_queue))
		var/datum/urgent_request/other = urgent_queue[i]
		if(other.deadline > R.deadline)
			at = i
			break
	urgent_queue.Insert(at, R)

/// Removes a finished or dropped request.
/datum/controller/kernel/proc/finish_urgent(datum/urgent_request/R)
	urgent_queue -= R
	R.work.urgent_pending?.Remove(R.member || R.work)
	if(R.work.urgent_pending && !length(R.work.urgent_pending))
		R.work.urgent_pending = null

/// Phase U: runs pending requests, earliest deadline first, until the reserved slice is spent (`limit_abs`).
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/run_urgent(limit_abs, now = world.time)
	if(!length(urgent_queue))
		return
	for(var/datum/urgent_request/R as anything in urgent_queue.Copy())
		if(R.member && QDELETED(R.member))
			finish_urgent(R)
			urgent_dropped++
			continue
		if(now > R.deadline && !R.breached)
			R.breached = TRUE
			urgent_breaches++
	var/ran = 0
	for(var/datum/urgent_request/R as anything in urgent_queue.Copy())
		if(ran && TICK_USAGE >= limit_abs)
			return
		ran++
		var/datum/work_item/W = R.work
		finish_urgent(R)
		if(W.parked)
			urgent_dropped++
			continue
		var/datum/owner = W.owner()
		if(!owner || QDELETED(owner))
			urgent_dropped++
			continue
		urgent_run++
		if(now > R.deadline)
			urgent_lateness_ds += now - R.deadline
		try
			if(W.runnable(owner, R.member))
				var/dt = W.take_dt(R.member, now)
				if(dt > 0)
					W.perform(owner, R.member, dt)
					W.member_runs++
					W.runs++
		catch(var/exception/e)
			W.faults++
			var/msg = "urgent run of [W.key] runtime: [e] ([e.file]:[e.line])"
			report_fault(e, msg)
