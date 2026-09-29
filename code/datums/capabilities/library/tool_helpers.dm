// Tool-quality helpers for capability entries and needs procs: ask the held item whether it can do
// a job now, and spend what the job costs. They wrap the tool pipeline (code/datums/interactions/
// tools.dm): has_tool_quality() / tool_quality_failure() for the quality and tier, the readiness
// hooks below for fuel, charge, stack units and a multitool's buffer, and use_tool() /
// tool_use_resources() for spending. A tool() entry already runs use_tool(); these are for needs
// procs ("the welder must be lit before the entry is offered") and for handlers that spend again.
//
//	/obj/machinery/thing/proc/welder_ready(mob/user, obj/item/held)
//		return tool_ready(held, TOOL_WELDER, amount = 2)
//	. += tool("Weld shut", TOOL_WELDER, PROC_REF(weld), needs = PROC_REF(welder_ready))

/**
 * TRUE when `held` can do a `quality` job needing `amount` (fuel, charge or stack units) now, else the
 * reason as text (a needs proc can return it as is). Pure: no messages, no welder flash.
 * `needs_buffer`: a multitool must have something buffered (tool_buffer()).
 */
/proc/tool_ready(obj/item/held, quality, amount = 0, tier = 1, needs_buffer = FALSE)
	var/reason = tool_quality_failure(held, quality, tier)
	if(reason)
		return reason
	reason = held.tool_readiness(quality, amount)
	if(istext(reason))
		return reason
	if(needs_buffer && !tool_buffer(held))
		return "its buffer is empty"
	return TRUE

/**
 * Spends a `quality` job's cost on `held`: `amount` fuel, charge or stack units. With a user and a
 * target it goes through use_tool() (the checks, the sound, the start check's side effects), with no
 * wait; otherwise it checks readiness and spends silently. TRUE when it was spent.
 */
/proc/tool_use(obj/item/held, quality, amount = 0, mob/user, atom/target, silent = FALSE)
	if(!held || !held.has_tool_quality(quality))
		return FALSE
	if(user && target)
		return use_tool(user, held, target, quality = quality, amount = amount, delay = 0, silent = silent) == TRUE
	if(tool_ready(held, quality, amount) != TRUE)
		return FALSE
	return held.tool_use_resources(null, amount, TRUE)

/// What a multitool (or an item carrying one, get_multitool()) has buffered, or null.
/proc/tool_buffer(obj/item/held)
	var/obj/item/multitool/M = held?.get_multitool()
	if(!M)
		return null
	return M.connectable() || M.buffer() || M.connecting()

/// Readiness hook: TRUE when the item can start a `quality` job needing `amount`, else why not. Pure:
/// the silent twin of tool_start_check(). Items that lend another their tool forward to it.
/obj/item/proc/tool_readiness(quality, amount = 0)
	var/obj/item/welder = get_welder()
	if(welder && welder != src)
		return welder.tool_readiness(quality, amount)
	return TRUE

/obj/item/weldingtool/tool_readiness(quality, amount = 0)
	if(!isOn())
		return "it needs to be lit"
	if(get_fuel() < amount)
		return "it needs more fuel"
	return TRUE

/obj/item/stack/tool_readiness(quality, amount = 0)
	if(amount && get_amount() < amount)
		return "it needs [amount] of [src]"
	return TRUE

// Common needs procs, (mob/user, obj/item/held) on any holder.

/// needs: a lit welder in hand.
/atom/proc/cap_needs_lit_welder(mob/user, obj/item/held)
	return tool_ready(held, TOOL_WELDER)

/// needs: a multitool with something in its buffer.
/atom/proc/cap_needs_buffer(mob/user, obj/item/held)
	return tool_ready(held, TOOL_MULTITOOL, needs_buffer = TRUE)
