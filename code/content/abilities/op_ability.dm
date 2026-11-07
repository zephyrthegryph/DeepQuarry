// Abilities that are ops (op(key, ..., menu(button = "Name", bind = "..."), ...)): a species' powers (the shadekin's phase shift), a cyborg's
// module toggles, a simple mob's special attacks. The engine keeps them as ops of the mob (a type's own, or granted with grant()); this keeps
// one entry in the mob's ability list for each, added when the mob comes to have the op and dropped when it loses it, so the Abilities tab
// shows them with the items' and the innate powers. Using the entry performs the op exactly as its keybinding does.

/// An ability that is the op `op_key` of the mob it is granted to.
/datum/action/op_ability
	ability_category = ABILITY_CATEGORY_SPECIES
	check_flags = NONE
	/// The key of the op this entry performs.
	var/op_key

/datum/action/op_ability/ability_id()
	return "[ability_category]/op/[op_key]"

/// The compiled plan of the op for the mob that has it, or null.
/datum/action/op_ability/proc/plan()
	var/mob/owner = action_owner()
	return owner ? op_plan_for(owner, op_key, list()) : null

/datum/action/op_ability/ability_desc()
	var/datum/op_plan/plan = plan()
	return (plan ? op_menu_desc(plan) : null) || name

/// What the op costs, as "50 energy" text, or null.
/datum/action/op_ability/ability_cost()
	var/datum/op_plan/plan = plan()
	if(!plan || !length(plan.costs))
		return null
	var/list/parts = list()
	for(var/res_id in plan.cost_order)
		var/amount = plan.costs[res_id]
		var/datum/resource/resource = resource_of(res_id)
		if(!amount || !resource)
			continue
		parts += "[amount] [resource.name]"
	return length(parts) ? jointext(parts, ", ") : null

/datum/action/op_ability/ability_cooldown_left()
	var/mob/owner = action_owner()
	var/ends = owner?.rx?.op_cooldowns?[op_key]
	return isnum(ends) ? max(0, ends - op_now()) : 0

/// The op's own requirements say whether it can be used and why not (the same answer as the Menu gives).
/datum/action/op_ability/ability_refusal()
	var/mob/owner = action_owner()
	if(!owner)
		return "nobody has this ability"
	if(ability_cooldown_left() > 0)
		return "recharging"
	for(var/list/row as anything in op_menu(owner, owner, null))
		if(row["key"] == op_key)
			return row["enabled"] ? null : (row["reason"] || "not available now")
	return "not available now"

/datum/action/op_ability/Trigger(trigger_flags)
	var/mob/owner = action_owner()
	if(!owner)
		return FALSE
	var/datum/op_result/result = perform_op(owner, owner, op_key, null, ORIGIN_HOTKEY)
	// An op that still waits (a channel, a prompt) comes back with no outcome yet: it was started.
	return result && (isnull(result.outcome) || (result.outcome & ACT_COMMITTED))

/// Makes the mob's ability list match the ops with a button that it has now: an entry for each, none for an op it lost.
/mob/proc/sync_op_abilities()
	var/list/wanted = list()
	// Read from each index's interned button table: a capability change (every equip and drop) walks the activations, not every op of the mob.
	var/datum/type_table/T = table_of(src)
	var/list/indexes = list(op_index_of_table(T))
	for(var/datum/activation/A as anything in rx?.activations)
		if(!A.dead && A.runs && !T.caps[A.def.key])
			indexes += op_index_of_def(T, A.def)
	for(var/datum/op_index/index as anything in indexes)
		var/list/buttons = op_index_buttons(index)
		for(var/key in buttons)
			wanted[key] = buttons[key]
	for(var/datum/action/op_ability/entry in actions?.Copy())
		if(!wanted[entry.op_key])
			entry.Remove(src)
			spent(entry)
		else
			wanted -= entry.op_key
	for(var/key in wanted)
		var/datum/action/op_ability/entry = new
		entry.name = wanted[key]
		entry.op_key = key
		entry.Grant(src)
