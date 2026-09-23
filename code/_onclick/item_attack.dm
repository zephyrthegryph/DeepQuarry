/*
=== Item Click Call Sequences ===
These are the default click code call sequences used when clicking on stuff with an item.

Atoms:

/mob/ClickOn() calls the item's resolve_attackby() proc.
item/resolve_attackby() calls the target atom's attackby() proc.

Mobs:

/mob/living/attackby() after checking for surgery, calls the item's attack() proc.
item/attack() generates attack logs, sets click cooldown and calls the mob's attacked_with_item() proc. If you override this, consider whether you need to set a click cooldown, play attack animations, and generate logs yourself.
/mob/attacked_with_item() should then do mob-type specific stuff (like determining hit/miss, handling shields, etc) and then possibly call the item's apply_hit_effect() proc to actually apply the effects of being hit.

Item Hit Effects:

item/apply_hit_effect() can be overriden to do whatever you want. However "standard" physical damage based weapons should make use of the target mob's hit_with_weapon() proc to
avoid code duplication. This includes items that may sometimes act as a standard weapon in addition to having other effects (e.g. stunbatons on harm intent).
*/

/**
 * ## IF YOU ARE MAKING SOMETHING USE ATTACK SELF, ENSURE IT CALLS THE PARENT AND CHECKS FOR A TRUE RETURN VALUE, CANCELLING THE REST OF THE CHAIN IF SO.
 * Called when the item is in the active hand and clicked
 * alternately, there is an 'activate held object' verb or you can hit pagedown or Z in hotkey mode.
 * returns TRUE if the attack was handled by a signal handler and no further processing should occur.
 * returns FALSE if a signal handler did NOT handle it, resulting in the normal chain.
*/
/obj/item/proc/attack_self(mob/user, modifiers)
	SHOULD_CALL_PARENT(TRUE)
	if(!user)
		CRASH("attack_self was called without a user!")
	if(SEND_SIGNAL(src, COMSIG_ITEM_ATTACK_SELF, user) & COMPONENT_CANCEL_ATTACK_CHAIN)
		return TRUE
	// Converted handlers (I7): interactions with entry = INTERACTION_ENTRY_SELF.
	if(run_interaction_entry(user, src, src, INTERACTION_ENTRY_SELF))
		return TRUE
	return

/**
 * Called at the start of resolve_attackby(), before the actual attack.
 *
 * Arguments:
 * * atom/A - The atom about to be hit
 * * mob/living/user - The mob doing the htting
 * * params - click params such as alt/shift etc
 *
 * See: [/obj/item/proc/melee_attack_chain]
 */

/obj/item/proc/pre_attack(atom/A, mob/user, params) //do stuff before attackby!
	if(SEND_SIGNAL(src, COMSIG_ITEM_PRE_ATTACK, A, user, params) & COMPONENT_CANCEL_ATTACK_CHAIN)
		return TRUE
	return FALSE //return TRUE to avoid calling attackby after this proc does stuff

//I would prefer to rename this to attack(), but that would involve touching hundreds of files.
/obj/item/proc/resolve_attackby(atom/A, mob/user, attack_modifier = 1, click_parameters)
	add_fingerprint(user)
	var/list/modifiers = islist(click_parameters) ? click_parameters : params2list(click_parameters)
	var/secondary = !!LAZYACCESS(modifiers, RIGHT_CLICK)
	if(!secondary)
		. = pre_attack(A, user, click_parameters)
		if(.)	// We're returning the value of pre_attack, important if it has a special return.
			return
	var/interaction_result
	if(secondary)
		interaction_result = A.item_interaction_secondary(user, src, modifiers)
	else
		interaction_result = A.item_interaction(user, src, modifiers)
	if(ITEM_INTERACT_CONSUMED(interaction_result))
		return interaction_result
	// SKIP_TO_ATTACK deliberately bypasses the modern interaction hooks but still
	// enters attackby(), which is the canonical attack/fallback path during migration.
	return A.attackby(src, user, attack_modifier, click_parameters)

/**
 * Modern item interaction entry point: every quality offered by a multi-purpose
 * tool, in order, then the interactions that answer Use without a tool
 * (doc/rewrite/interactions.md §7). The base *_act procs below end in the
 * resolver too, so tool interactions run there. Returning no flags falls
 * through to the legacy attackby path in resolve_attackby().
 */
/atom/proc/item_interaction(mob/user, obj/item/tool, list/modifiers)
	. = tool_interaction(user, tool, modifiers, FALSE)
	if(.)
		return
	// Interactions that need no tool quality but answer Use with an item in hand.
	switch(try_interaction(user, src, tool, INPUT_ACTION_USE, null, TRUE))
		if(INTERACTION_TRY_RAN)
			return ITEM_INTERACT_SUCCESS
		if(INTERACTION_TRY_MENU, INTERACTION_TRY_BLOCKED)
			return ITEM_INTERACT_BLOCKING
	return NONE

/// Right-click counterpart to item_interaction().
/atom/proc/item_interaction_secondary(mob/user, obj/item/tool, list/modifiers)
	return tool_interaction(user, tool, modifiers, TRUE)

/// Dispatches all qualities on a tool in their declared order.
/atom/proc/tool_interaction(mob/user, obj/item/tool, list/modifiers, secondary = FALSE)
	if(!LAZYLEN(tool.tool_qualities))
		return NONE
	for(var/tool_quality in tool.tool_qualities)
		var/result = tool_act(user, tool, tool_quality, secondary)
		if(result & ITEM_INTERACT_SUCCESS)
			if(!secondary)
				SEND_SIGNAL(tool, COMSIG_ITEM_TOOL_ACTED, src, user, tool_quality, modifiers)
			SEND_SIGNAL(tool, secondary ? COMSIG_TOOL_ATOM_ACTED_SECONDARY(tool_quality) : COMSIG_TOOL_ATOM_ACTED_PRIMARY(tool_quality), src, user, modifiers)
		if(result & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING | ITEM_INTERACT_SKIP_TO_ATTACK))
			return result
	return NONE

/// Sends the quality-specific signal, then invokes the corresponding focused hook.
/atom/proc/tool_act(mob/user, obj/item/tool, tool_quality, secondary = FALSE)
	var/result = SEND_SIGNAL(src, secondary ? COMSIG_ATOM_SECONDARY_TOOL_ACT(tool_quality) : COMSIG_ATOM_TOOL_ACT(tool_quality), user, tool)
	if(result & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING | ITEM_INTERACT_SKIP_TO_ATTACK))
		return result
	// Dormant material assemblies intentionally own no signal handlers. A
	// deliberate diagnostic interaction is itself their admission event.
	if(secondary && tool_quality == TOOL_MULTITOOL && isobj(src))
		var/obj/object = src
		result = object.material_diagnostics_tool_act(user, tool)
		if(result & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING | ITEM_INTERACT_SKIP_TO_ATTACK))
			return result
	if(secondary)
		switch(tool_quality)
			if(TOOL_SCREWDRIVER) return screwdriver_act_secondary(user, tool)
			if(TOOL_CROWBAR) return crowbar_act_secondary(user, tool)
			if(TOOL_WRENCH) return wrench_act_secondary(user, tool)
			if(TOOL_WIRECUTTER) return wirecutter_act_secondary(user, tool)
			if(TOOL_MULTITOOL) return multitool_act_secondary(user, tool)
			if(TOOL_WELDER) return welder_act_secondary(user, tool)
	else
		switch(tool_quality)
			if(TOOL_SCREWDRIVER) return screwdriver_act(user, tool)
			if(TOOL_CROWBAR) return crowbar_act(user, tool)
			if(TOOL_WRENCH) return wrench_act(user, tool)
			if(TOOL_WIRECUTTER) return wirecutter_act(user, tool)
			if(TOOL_MULTITOOL) return multitool_act(user, tool)
			if(TOOL_WELDER) return welder_act(user, tool)
		// Every other TOOL_* quality has no focused hook: it goes straight to the
		// interactions that name it (doc/rewrite/interactions.md §9).
		return interaction_tool_act(user, tool, tool_quality)
	return NONE

/atom/proc/screwdriver_act(mob/user, obj/item/tool)
	return interaction_tool_act(user, tool, TOOL_SCREWDRIVER)
/atom/proc/crowbar_act(mob/user, obj/item/tool)
	return interaction_tool_act(user, tool, TOOL_CROWBAR)
/atom/proc/wrench_act(mob/user, obj/item/tool)
	return interaction_tool_act(user, tool, TOOL_WRENCH)
/atom/proc/wirecutter_act(mob/user, obj/item/tool)
	return interaction_tool_act(user, tool, TOOL_WIRECUTTER)
/atom/proc/multitool_act(mob/user, obj/item/tool)
	return interaction_tool_act(user, tool, TOOL_MULTITOOL)
/atom/proc/welder_act(mob/user, obj/item/tool)
	return interaction_tool_act(user, tool, TOOL_WELDER)
/atom/proc/screwdriver_act_secondary(mob/user, obj/item/tool)
	return NONE
/atom/proc/crowbar_act_secondary(mob/user, obj/item/tool)
	return NONE
/atom/proc/wrench_act_secondary(mob/user, obj/item/tool)
	return NONE
/atom/proc/wirecutter_act_secondary(mob/user, obj/item/tool)
	return NONE
/atom/proc/multitool_act_secondary(mob/user, obj/item/tool)
	return NONE
/atom/proc/welder_act_secondary(mob/user, obj/item/tool)
	return NONE

/**
 * Used with an item. Converted handlers (I7) are interactions with
 * `entry = INTERACTION_ENTRY_ITEM`; they run first, where the type's own
 * attackby override used to. Returns TRUE when the input was used up, so the
 * item's afterattack doesn't follow.
 */
/atom/proc/attackby(obj/item/W, mob/user, attack_modifier, click_parameters)
	var/datum/interaction/answered = run_interaction_entry(user, src, W, INTERACTION_ENTRY_ITEM)
	if(answered)
		return answered.consumes_input
	if(SEND_SIGNAL(src, COMSIG_ATOM_ATTACKBY, W, user, click_parameters) & COMPONENT_CANCEL_ATTACK_CHAIN)
		return TRUE
	return FALSE

/mob/living/attackby(obj/item/I, mob/user, attack_modifier, click_parameters)
	if(!ismob(user))
		return FALSE

	if(SEND_SIGNAL(src, COMSIG_ATOM_ATTACKBY, I, user, click_parameters) & COMPONENT_CANCEL_ATTACK_CHAIN)
		return FALSE

	if(can_operate(src, user) && I.do_surgery(src,user))
		return TRUE

	if(vore_attackby(I, user)) // The vore, of course.
		return

	// Phased melee: a harm-intent attack with a real weapon winds up, telegraphs its swing
	// tiles, then resolves (see code/modules/mob/living/melee_swing.dm). Diverts the instant
	// attack. Non-harm intents, unarmed, and item-use on objects never reach this branch.
	if(isliving(user) && IS_HARMING(user) && I.force && !(I.flags & NOBLUDGEON))
		var/mob/living/attacker = user
		if(attacker.is_swinging)
			return FALSE // already mid-swing — ignore the queued attack click
		attacker.begin_melee_swing(src, I)
		return ITEM_INTERACT_SUCCESS // suppress afterattack; the swing applies its own hit

	return I.attack(src, user, user.zone_sel?.selecting || BP_TORSO, attack_modifier)

// Used to get how fast a mob should attack, and influences click delay.
// This is just for inheritence.
/mob/proc/get_attack_speed()
	return DEFAULT_ATTACK_COOLDOWN

// Same as above but actually does useful things.
// W is the item being used in the attack, if any. modifier is if the attack should be longer or shorter than usual, for whatever reason.
/mob/living/get_attack_speed(obj/item/W)
	var/speed = base_attack_cooldown
	if(W && istype(W))
		speed = W.attackspeed
	return speed * factor(BF_ATTACK_SPEED)

// Proximity_flag is 1 if this afterattack was called on something adjacent, in your square, or on your person.
// Click parameters is the params string from byond Click() code, see that documentation.
/obj/item/proc/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	return

//I would prefer to rename this attack_as_weapon(), but that would involve touching hundreds of files.
/obj/item/proc/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!force || (flags & NOBLUDGEON))
		return ITEM_INTERACT_FAILURE
	if(M == user && !IS_HARMING(user))
		return ITEM_INTERACT_FAILURE
	if(M.is_incorporeal()) // No attacking phased entities :)
		return ITEM_INTERACT_FAILURE
	SEND_SIGNAL(src, COMSIG_ITEM_ATTACK, M, user, target_zone)

	/////////////////////////
	M.lastattacker = user

	if(!no_attack_log)
		add_attack_logs(user,M,"attacked with [name] (STANCE: [uppertext(user.use_stance())]) (KIND: [injury_kind_name(injury_kind)])")
	/////////////////////////

	user.setClickCooldown(user.get_attack_speed(src))
	user.do_attack_animation(M)

	var/hit_zone = M.resolve_item_attack(src, user, target_zone)
	if(hit_zone)
		apply_hit_effect(M, user, hit_zone, attack_modifier)

	return ITEM_INTERACT_SUCCESS

//Called when a weapon is used to make a successful melee attack on a mob. Returns the blocked result
/obj/item/proc/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier)
	user.break_cloak()
	material_response_impact(get_turf(target), target)
	if(hitsound)
		playsound(src, hitsound, 50, 1, -1)

	var/power = force * user.factor(BF_MELEE_DAMAGE)

	if(HULK in user.mutations)
		power *= 2

	power *= attack_modifier

	return target.hit_with_weapon(src, user, power, hit_zone)
