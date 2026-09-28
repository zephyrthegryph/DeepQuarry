/**
 * The tool pipeline (doc/rewrite/interactions.md §9).
 *
 * use_tool() is the one place a tool is used on something. It:
 *	1. checks tool quality and tier;
 *	2. checks fuel or charge (tool_start_check());
 *	3. plays the tool's sound;
 *	4. runs do_after, scaled by the tool's speed and tool_skill_factor();
 *	5. consumes resources (tool_use_resources());
 *	6. sends the generated start messages, and failure messages when a check fails.
 *
 * Interactions reach it through /datum/interaction/proc/pay_cost(). Hand-written
 * tool sites (the ones I7 has not turned into interactions yet) call it with an
 * explicit `delay`:
 *
 *	if(!use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 100))
 *		return
 *
 * `delay` is the unscaled time, exactly what the site used to multiply by
 * `toolspeed`, so timings do not change. Nothing waits: a job with a wait is a timed
 * action, and what follows the job goes in `on_done` (a proc on `receiver`, called with
 * `done_args`; on_fail likewise when it is interrupted or the tool gives out):
 *
 *	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 100, receiver = src, on_done = PROC_REF(unwrenched), done_args = list(user))
 *
 * Returns FALSE when a check refused the job, TRUE when it was done at once (no wait;
 * on_done has run), or USE_TOOL_PENDING when the timed action started. `claims`: the target is
 * exclusive while the job runs (another claiming job on it is refused); `busy`: a datum the job
 * also claims (om_busy() holds while it runs; see om_do_after()).
 */
/// The last use_tool() call: its unscaled delay, quality, amount and volume. Parity tests read it; only unit tests write it.
GLOBAL_LIST_EMPTY(dq_tool_last_use)

/proc/use_tool(mob/actor, obj/item/tool, atom/target, datum/interaction/interaction, delay = 0, quality, tier = 1, amount = 0, volume = 50, message_self, message_others, datum/callback/extra_checks, silent = FALSE, datum/receiver, on_done, list/done_args, on_fail, list/fail_args, claims = FALSE, busy, job_type, list/job_params)
	if(!actor || !target)
		return FALSE
	if(interaction)
		quality = interaction.tool
		tier = interaction.tool_tier
		amount = interaction.tool_amount
		volume = interaction.tool_volume
		var/list/start = interaction.start_messages(actor, target, tool)
		if(start)
			message_self = start[1]
			message_others = start[2]
#ifdef UNIT_TESTS
	GLOB.dq_tool_last_use = list("delay" = interaction ? interaction.base_duration(actor, target) : delay, "quality" = quality, "amount" = amount, "volume" = volume)
#endif

	// 1. Quality and tier.
	if(quality)
		var/reason = tool_quality_failure(tool, quality, tier)
		if(reason)
			if(!silent)
				to_chat(actor, span_warning("That [reason]."))
			return FALSE

	// 2. Fuel or charge.
	if(tool && !tool.tool_start_check(actor, amount, silent))
		return FALSE

	// 3. Sound.
	if(tool && volume && tool.usesound)
		playsound(target, tool.usesound, volume, TRUE)

	var/time = interaction ? interaction.duration_for(actor, target, tool) : tool_delay(actor, tool, delay, quality)

	// 6a. Start messages (an interaction's only when it takes time).
	if((message_self || message_others) && (!interaction || time > 0))
		var/others_text = interaction ? interaction.fill_message(message_others, actor, target) : message_others
		var/self_text = interaction ? interaction.fill_message(message_self, actor, target) : message_self
		if(others_text)
			actor.visible_message(span_notice(others_text), self_text ? span_notice(self_text) : null)
		else if(self_text)
			to_chat(actor, span_notice(self_text))

	// 4. The wait: a tool job task, finished in use_tool_finish().
	// A job with state is its own tool_job subtype (`job_type`, its vars in `job_params`); it
	// overrides tool_done()/tool_failed() instead of passing done_args.
	var/list/job_vars = list(
		"duration" = max(time, 0),
		"tool" = tool,
		"quality" = quality,
		"tier" = tier,
		"amount" = amount,
		"silent" = silent,
		"on_behalf_of" = receiver,
		"done_proc" = on_done,
		"done_args" = done_args,
		"fail_proc" = on_fail,
		"fail_args" = fail_args,
		"extra_checks" = extra_checks,
		"busy" = busy)
	for(var/key in job_params)
		job_vars[key] = job_params[key]
	if(!job_type)
		job_type = claims ? /datum/om/task/timed/tool_job/claiming : /datum/om/task/timed/tool_job
	var/datum/om/task/timed/tool_job/job = om_task_launch(job_type, actor, target, job_vars, src, TRUE)
	if(istext(job))
		return FALSE
	if(job.state == OM_TASK_DONE)
		return job.succeeded
	return USE_TOOL_PENDING

/// A tool job (use_tool()): the wait, then the tool must still do the job and pays for it, and
/// `done_proc` runs on whoever asked (`on_behalf_of`) with `done_args`; `fail_proc` if it was
/// interrupted or the tool gave out. The caller's procs take at most two arguments: anything
/// more is state, and belongs on its own task type.
/datum/om/task/timed/tool_job
	complete_proc = /proc/use_tool_finish
	cancel_proc = /proc/use_tool_interrupted
	var/obj/item/tool
	var/quality
	var/tier = 1
	var/amount = 0
	var/silent = FALSE
	var/datum/on_behalf_of
	var/done_proc
	var/list/done_args
	var/fail_proc
	var/list/fail_args
	var/datum/callback/extra_checks
	/// Set when the job completed and the tool did it.
	var/succeeded = FALSE

/datum/om/task/timed/tool_job/claiming
	claims = TRUE

/datum/om/task/timed/tool_job/timed_check()
	return !extra_checks || extra_checks.Invoke()

/**
 * The end of a tool job: after the wait, the tool must still do the job (the wait may
 * have turned the welder off or emptied it), then the resources are used and `done_proc`
 * runs with `done_args` (a /proc/ path is called globally). Sets the task's `succeeded`.
 */
/proc/use_tool_finish(datum/om/task/timed/tool_job/job)
	var/obj/item/tool = job.tool
	if(QDELETED(job.target) || (job.quality && tool_quality_failure(tool, job.quality, job.tier)))
		use_tool_interrupted(job)
		return
	// 5. Resources.
	if(tool && !tool.tool_use_resources(job.actor, job.amount, job.silent))
		use_tool_interrupted(job)
		return
	job.succeeded = TRUE
	job.tool_done()

/proc/use_tool_interrupted(datum/om/task/timed/tool_job/job)
	job.tool_failed()

/// The tool did the job. Subtypes with state call their receiver with it.
/datum/om/task/timed/tool_job/proc/tool_done()
	om_call_ref(on_behalf_of, done_proc, done_args)

/// The job was interrupted or the tool gave out.
/datum/om/task/timed/tool_job/proc/tool_failed()
	om_call_ref(on_behalf_of, fail_proc, fail_args)

// ---- tool jobs with state (use_tool(job_type = ...)): the state is on the task.

/// An interaction's time cost paid by a tool: cost_paid() runs with the held item.
/datum/om/task/timed/tool_job/interaction
	var/obj/item/held

/datum/om/task/timed/tool_job/interaction/tool_done()
	var/datum/interaction/I = on_behalf_of
	I?.cost_paid(actor, target, held)

/// Unwrenching a pipe: whether it was under pressure when the job started, and how much.
/datum/om/task/timed/tool_job/pipe_unwrench
	var/unsafe = FALSE
	var/pressure = 0

/datum/om/task/timed/tool_job/pipe_unwrench/tool_done()
	var/obj/machinery/atmospherics/pipe/P = target
	P.wrench_act_tool_done(actor, unsafe, pressure)

/// Repairing a flash's bulb with a screwdriver.
/datum/om/task/timed/tool_job/flash_repair/tool_done()
	var/obj/item/flash/F = target
	F.screwdriver_act_tool_done(actor, tool)

/datum/om/task/timed/tool_job/flash_repair/tool_failed()
	var/obj/item/flash/F = target
	F.screwdriver_act_tool_failed(actor, tool)

/// Welding a disposal pipe segment in place: what kind of segment it was.
/datum/om/task/timed/tool_job/disposal_weld
	var/nicetype
	var/ispipe = FALSE

/datum/om/task/timed/tool_job/disposal_weld/tool_done()
	var/obj/structure/disposalconstruct/C = target
	C.welder_act_tool_done(actor, nicetype, ispipe)

/// Removing a table's material or reinforcement layer.
/datum/om/task/timed/tool_job/table_layer_remove
	claims = TRUE
	var/datum/material/material
	var/what
	var/which

/datum/om/task/timed/tool_job/table_layer_remove/tool_done()
	var/obj/structure/table/T = target
	T.common_material_remove_tool_done(actor, material, what, which)

/// Why `tool` can't be used as `quality` at `tier`, or null if it can.
/proc/tool_quality_failure(obj/item/tool, quality, tier = 1)
	var/noun = dq_pred_article(dq_pred_tool_name(quality))
	if(!tool || !tool.has_tool_quality(quality))
		return "needs [noun]"
	if(tier > 1 && dq_tool_tier(tool, quality) < tier)
		return "needs [noun] (tier [tier])"
	return null

/// The scaled time of a tool action: `delay` times the tool's speed and the actor's skill.
/proc/tool_delay(mob/actor, obj/item/tool, delay, quality)
	if(!delay)
		return 0
	if(!tool)
		return delay
	return delay * tool.toolspeed * tool_skill_factor(actor, quality)

/**
 * Multiplier on tool time for this actor's skill with `quality`. Always 1 until
 * skills exist: the hook is here so they can be added without touching sites.
 */
/proc/tool_skill_factor(mob/actor, quality)
	return 1

// ---------------------------------------------------------------------------
// Resource hooks. Tools that burn something (welders: fuel or charge; stacks:
// units) override these. An item that lends another its tool (the transforming
// tools' welder, get_welder()) forwards to it.

/**
 * Can this tool start a job that uses `amount`? Tells the actor why not unless
 * `silent`. Side effects of starting (a welder's flash) happen here.
 */
/obj/item/proc/tool_start_check(mob/actor, amount = 0, silent = FALSE)
	var/obj/item/welder = get_welder()
	if(welder && welder != src)
		return welder.tool_start_check(actor, amount, silent)
	return TRUE

/// Uses up `amount` at the end of the job. FALSE if it could not.
/obj/item/proc/tool_use_resources(mob/actor, amount = 0, silent = FALSE)
	var/obj/item/welder = get_welder()
	if(welder && welder != src)
		return welder.tool_use_resources(actor, amount, silent)
	return TRUE

/obj/item/weldingtool/tool_start_check(mob/actor, amount = 0, silent = FALSE)
	if(!isOn())
		if(!silent)
			to_chat(actor, span_warning("\The [src] needs to be on for this task."))
		return FALSE
	if(get_fuel() < amount)
		if(!silent)
			to_chat(actor, span_warning("You need more welding fuel to complete this task."))
		return FALSE
	eyecheck(actor)
	return TRUE

/**
 * Burns `amount` fuel. With `amount` 0 this still goes through remove_fuel(),
 * as the hand-written sites did: it resets the idle burn counter, and an
 * electric welder pays its charge_cost.
 */
/obj/item/weldingtool/tool_use_resources(mob/actor, amount = 0, silent = FALSE)
	if(!isOn())
		if(!silent)
			to_chat(actor, span_warning("\The [src] needs to be on for this task."))
		return FALSE
	if(!remove_fuel(amount))
		if(!silent)
			to_chat(actor, span_warning("You need more welding fuel to complete this task."))
		return FALSE
	return TRUE

/obj/item/stack/tool_start_check(mob/actor, amount = 0, silent = FALSE)
	if(amount && get_amount() < amount)
		if(!silent)
			to_chat(actor, span_warning("You need [amount] of \the [src] for this."))
		return FALSE
	return TRUE

/obj/item/stack/tool_use_resources(mob/actor, amount = 0, silent = FALSE)
	if(!amount)
		return TRUE
	if(!use(amount))
		if(!silent)
			to_chat(actor, span_warning("You need [amount] of \the [src] for this."))
		return FALSE
	return TRUE
