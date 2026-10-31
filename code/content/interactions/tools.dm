// The tool helpers: what a tool can do (tool_quality_failure()), how long a tool's work takes (tool_delay()). A tool used on something is
// an op with a tool() binding and, when it takes time, a wait() (doc/rewrite/final_api.html section 9); the legacy timer helper and its tool jobs are gone.

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
	return delay * tooling_of(tool).speed * tool_skill_factor(actor, quality)

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

/// Human-readable article and quality names used by actual tool refusals.
/proc/dq_pred_article(noun)
	return "[(copytext(noun, 1, 2) in list("a", "e", "i", "o", "u")) ? "an" : "a"] [noun]"

/proc/dq_pred_tool_name(quality)
	switch(quality)
		if(TOOL_CABLE_COIL)
			return "cable coil"
		if(TOOL_BLOODFILTER)
			return "blood filter"
		if(TOOL_ROLLINGPIN)
			return "rolling pin"
		if(TOOL_MINING)
			return "mining tool"
	return quality
