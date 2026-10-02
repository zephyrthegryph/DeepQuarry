// Chunked work (doc/rewrite/final_api.html, section 2 "Chunked work and paths"; section 19 "E6").
//
//     job(owner, PROC_REF(step), budget = 10, then = PROC_REF(finished))
//
// A long job that must give the tick back is a job(). `step(datum/act/timer/A)` does one chunk of work and returns JOB_MORE or
// JOB_DONE; A.holder is the owner and A.dt the time since the job's last step. `budget` caps how much of a tick the job's steps may
// take in one run, in percent of a tick, so a step that finishes quickly runs again at once (inside the budget) and a job that
// uses its budget waits for the next tick. A job dies with its owner: nothing runs for a deleted owner and then() is not called.
// When a step returns JOB_DONE, `then(datum/act/timer/A)` (a PROC_REF on the owner) runs once. A step never sleeps.
//
// The map loader, site generation, the POI queue and zone cleanup are the first users: they replace their stoplag() and INVOKE_ASYNC.

/// One chunked job.
/datum/kernel_job
	/// The owner whose proc the step is. A plain reference: a deleted owner is QDELETED and the job is dropped at its next run.
	var/datum/owner
	/// A PROC_REF on the owner, or a GLOBAL_PROC_REF called with the owner first.
	var/step
	/// A PROC_REF on the owner run once when the job is done, or null.
	var/then
	/// Percent of a tick one run of this job may use.
	var/budget = 10
	/// Steps run, ms spent, and the world.time of the last step (the next step's dt).
	var/steps = 0
	var/total_ms = 0
	var/last_step = 0

/// Starts a chunked job. Returns the job, or null when the owner is already gone. The first step runs on the next kernel pass.
/proc/job(datum/owner, step, budget = 10, then = null)
	RETURN_TYPE(/datum/kernel_job)
	if(!owner || QDELETED(owner))
		return null
	var/datum/kernel_job/J = new
	J.owner = owner
	J.step = step
	J.then = then
	J.budget = clamp(budget, 1, 100)
	J.last_step = world.time // ALLOW(sys_world_time_write): the job's own step stamp, read for dt, not an entity expiry
	SSkernel_jobs.start(J)
	return J

SYSTEM_DEF(kernel_jobs)
	name = "Jobs"
	phase = KERNEL_PHASE_P
	latency_class = LATENCY_L2
	init_stage = INITSTAGE_FIRST
	/// The jobs, oldest first.
	var/list/jobs = list() // ALLOW(instance_list): a singleton system's own table
	var/started = 0
	var/finished = 0
	var/dropped = 0
	/// Where the next run starts, so a budget that ends mid-list does not always favour the same jobs.
	var/next_job

/datum/system/kernel_jobs/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(run_jobs), when = PROC_REF(has_jobs))

/datum/system/kernel_jobs/proc/has_jobs()
	return length(jobs) > 0

/datum/system/kernel_jobs/proc/start(datum/kernel_job/J)
	jobs += J // ALLOW(ownership): the system holds a job until it is done or its owner is gone
	started++

/// One kernel pass: every job runs steps inside its own budget, until the pass's limit is reached.
/datum/system/kernel_jobs/proc/run_jobs(dt)
	var/pass_limit = Master.current_ticklimit
	var/list/running = jobs.Copy()
	var/at = next_job ? running.Find(next_job) : 1
	if(at > 1)
		running = running.Copy(at) + running.Copy(1, at)
	next_job = null
	for(var/datum/kernel_job/J as anything in running)
		if(TICK_USAGE >= pass_limit)
			next_job = J
			return STEP_YIELD
		if(!(J in jobs))
			continue
		var/datum/owner = J.owner
		if(!owner || QDELETED(owner))
			jobs -= J
			dropped++
			continue
		run_job(J, owner, pass_limit)
	return STEP_DONE

/// Runs `J`'s steps until it is done, its budget is spent, or the pass's limit is.
/datum/system/kernel_jobs/proc/run_job(datum/kernel_job/J, datum/owner, pass_limit)
	var/started_usage = TICK_USAGE
	var/limit = min(pass_limit, started_usage + J.budget)
	var/result = JOB_MORE
	while(result == JOB_MORE)
		var/datum/act/timer/A = take(/datum/act/timer)
		A.holder = owner
		A.dt = world.time - J.last_step
		J.last_step = world.time // ALLOW(sys_world_time_write): the job's own step stamp, read for dt, not an entity expiry
		var/step_start = TICK_USAGE
		if(istext(J.step))
			result = call(owner, J.step)(A)
		else
			result = call(J.step)(owner, A)
		J.total_ms += TICK_USAGE_TO_MS(step_start)
		J.steps++
		A.release()
		if(result != JOB_MORE)
			break
		if(TICK_USAGE >= limit)
			break
	if(result != JOB_MORE && result != JOB_DONE)
		var/message = "job: [J.step] on [owner.type] returned [isnull(result) ? "nothing" : result] (a step returns JOB_MORE or JOB_DONE): the job is dropped"
		kernel().report_fault(new /exception(message, "jobs.dm", 0), message)
		jobs -= J
		dropped++
		return
	if(result == JOB_DONE)
		jobs -= J
		finished++
		if(J.then && !QDELETED(owner))
			var/datum/act/timer/D = take(/datum/act/timer)
			D.holder = owner
			call(owner, J.then)(D)
			D.release()

/datum/system/kernel_jobs/metrics()
	. = ..()
	.["jobs"] = length(jobs)
	.["started"] = started
	.["finished"] = finished
	.["dropped"] = dropped
