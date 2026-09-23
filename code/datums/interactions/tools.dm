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
 * `toolspeed`, so timings do not change. Returns TRUE when the tool was used.
 */
/// The last use_tool() call: its unscaled delay, quality, amount and volume. Parity tests read it; only unit tests write it.
GLOBAL_LIST_EMPTY(dq_tool_last_use)

/proc/use_tool(mob/actor, obj/item/tool, atom/target, datum/interaction/interaction, delay = 0, quality, tier = 1, amount = 0, volume = 50, message_self, message_others, datum/callback/extra_checks, silent = FALSE)
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

	// 4. The wait.
	if(time > 0)
		if(!do_after(actor, time, target = target, extra_checks = extra_checks))
			return FALSE
		if(QDELETED(target) || (tool && QDELETED(tool)))
			return FALSE
		// The wait may have turned the welder off or emptied it.
		if(quality && tool_quality_failure(tool, quality, tier))
			return FALSE

	// 5. Resources.
	if(tool && !tool.tool_use_resources(actor, amount, silent))
		return FALSE
	return TRUE

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
