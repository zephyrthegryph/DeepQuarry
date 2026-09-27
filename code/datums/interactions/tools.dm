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

/proc/use_tool(mob/actor, obj/item/tool, atom/target, datum/interaction/interaction, delay = 0, quality, tier = 1, amount = 0, volume = 50, message_self, message_others, datum/callback/extra_checks, silent = FALSE, datum/receiver, on_done, list/done_args, on_fail, list/fail_args, claims = FALSE, busy)
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

	// 4. The wait: a timed action (timed_action.dm) that finishes in use_tool_finish().
	var/list/finish_args = list(actor, tool, target, quality, tier, amount, silent, receiver, on_done, done_args, on_fail, fail_args)
	if(time <= 0)
		return use_tool_finish(arglist(finish_args))
	var/started = om_do_after(actor, time, target, null, GLOBAL_PROC_REF(use_tool_finish), finish_args, 		on_fail = GLOBAL_PROC_REF(use_tool_interrupted), fail_args = list(receiver, on_fail, fail_args), 		check_proc = extra_checks ? GLOBAL_PROC_REF(om_check_callback) : null, check_args = extra_checks ? list(extra_checks) : null, claims = claims, busy = busy)
	return istext(started) ? FALSE : USE_TOOL_PENDING

/**
 * The end of a tool job: after the wait, the tool must still do the job (the wait may
 * have turned the welder off or emptied it), then the resources are used and `on_done`
 * runs on `receiver` with `done_args` (a /proc/ path is called globally). TRUE if it did.
 */
/proc/use_tool_finish(mob/actor, obj/item/tool, atom/target, quality, tier, amount, silent, datum/receiver, on_done, list/done_args, on_fail, list/fail_args)
	if(QDELETED(target) || (tool && QDELETED(tool)) || (quality && tool_quality_failure(tool, quality, tier)))
		om_call_ref(receiver, on_fail, fail_args)
		return FALSE
	// 5. Resources.
	if(tool && !tool.tool_use_resources(actor, amount, silent))
		om_call_ref(receiver, on_fail, fail_args)
		return FALSE
	om_call_ref(receiver, on_done, done_args)
	return TRUE

/proc/use_tool_interrupted(datum/receiver, on_fail, list/fail_args)
	om_call_ref(receiver, on_fail, fail_args)

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
