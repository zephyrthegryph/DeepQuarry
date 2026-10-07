/*
=== Item Click Call Sequences ===
These are the default click code call sequences used when clicking on stuff with an item.

Atoms:

/mob/ClickOn() calls the item's resolve_attackby() proc.
item/resolve_attackby() calls the target atom's attackby() proc.

Mobs:

A mob's "Attack" default interaction (hit_with_item()) checks for surgery, then calls the item's attack() proc.
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
	var/datum/act/attack_self/use = ACT_TRY(src, attack_self, user)
	if(!use)
		return TRUE
	act_done(use)
	// Converted handlers (I7): interactions with entry = INTERACTION_ENTRY_SELF.
	if(run_interaction_entry(user, src, src, INTERACTION_ENTRY_SELF))
		return TRUE
	// The item's in_hand() ops: the Z key and an item's action button reach them here (a click on the held item resolves them in the inbox first).
	if(op_resolve_click(user, src, src, GESTURE_SELF, ORIGIN_CLICK))
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
	var/datum/act/pre_attack/swing = ACT_TRY(src, pre_attack, A, user, params)
	if(!swing)
		return TRUE
	act_done(swing)
	return FALSE //return TRUE to avoid calling attackby after this proc does stuff

//I would prefer to rename this to attack(), but that would involve touching hundreds of files.
/obj/item/proc/resolve_attackby(atom/A, mob/user, attack_modifier = 1, click_parameters)
	add_fingerprint(user)
	var/list/modifiers = islist(click_parameters) ? click_parameters : params2list(click_parameters)
	var/secondary = GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, secondary_table), INPUT_ACTION_ALTERNATE_SECONDARY)
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
				PUBLISH_LEGACY(tool, /datum/notice/item_tool_acted, src, user, tool_quality, modifiers)
			PUBLISH_LEGACY(tool, /datum/notice/tool_atom_acted, tool_quality, secondary, src, user, modifiers)
		if(result & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING | ITEM_INTERACT_SKIP_TO_ATTACK))
			return result
	return NONE

/// Emits the tool-act event, then invokes the corresponding focused hook.
/atom/proc/tool_act(mob/user, obj/item/tool, tool_quality, secondary = FALSE)
	// A hook on the atom (a dormant core repaired on its body) takes the tool use over and answers the ITEM_INTERACT_* result.
	var/datum/act/tool_act/use = ACT_TRY(src, tool_act, tool_quality, secondary, user, tool)
	if(!use)
		return ACT_TAKEN_OVER ? ACT_REPLY : ITEM_INTERACT_BLOCKING
	act_cancel(use)
	var/result = NONE
	// Dormant material assemblies intentionally own no signal handlers. A
	// deliberate diagnostic interaction is itself their admission event.
	if(secondary && tool_quality == TOOL_MULTITOOL && isobj(src))
		var/obj/object = src
		result = object.material_diagnostics_tool_act(user, tool)
		if(result & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING | ITEM_INTERACT_SKIP_TO_ATTACK))
			return result
	if(secondary)
		// Secondary (right-click) tool use has no focused hooks: it runs the declared
		// interactions for this quality whose default action is Alternate
		// (doc/rewrite/interactions.md §9).
		return interaction_tool_act(user, tool, tool_quality, TRUE)
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

/**
 * Used with an item. Converted handlers (I7) are interactions with
 * `entry = INTERACTION_ENTRY_ITEM`; they run first, where the type's own
 * attackby override used to. Returns TRUE when the input was used up, so the
 * item's afterattack doesn't follow.
 */
/atom/proc/attackby(obj/item/W, mob/user, attack_modifier, click_parameters)
	var/list/outcome = list()
	var/saved_params = dq_interaction_set_click_params(user, click_parameters)
	var/saved_modifier = GLOB.interaction_entry_attack_modifier[user]
	if(user)
		GLOB.interaction_entry_attack_modifier[user] = attack_modifier
	var/datum/interaction/answered
	try
		answered = run_interaction_entry(user, src, W, INTERACTION_ENTRY_ITEM, outcome)
	catch(var/exception/error)
		dq_interaction_set_click_params(user, saved_params)
		dq_interaction_restore_attack_modifier(user, saved_modifier)
		throw error
	dq_interaction_set_click_params(user, saved_params)
	dq_interaction_restore_attack_modifier(user, saved_modifier)
	if(answered)
		return (INTERACTION_TRY_PASS in outcome) ? FALSE : answered.consumes_input
	if(attackby_stopped(src, W, user, click_parameters))
		return TRUE
	return FALSE

/// The gate every item use on `target` passes: a hook on the target (observe(target, /datum/act/attackby, ...), a capability's extend()) may stop it.
/// TRUE when something did. The use is announced (/datum/notice/attacked_by) when nothing stopped it.
/proc/attackby_stopped(atom/target, obj/item/W, mob/user, click_parameters)
	var/datum/act/attackby/use = ACT_TRY(target, attackby, W, user, click_parameters)
	if(!use)
		return TRUE
	act_done(use)
	return FALSE

/// The attack_modifier of the item entry each actor is inside (a charged or off-hand swing).
GLOBAL_LIST_EMPTY(interaction_entry_attack_modifier)

/proc/dq_interaction_restore_attack_modifier(mob/actor, saved)
	if(!actor)
		return
	if(isnull(saved))
		GLOB.interaction_entry_attack_modifier -= actor
	else
		GLOB.interaction_entry_attack_modifier[actor] = saved

/**
 * Every living mob's defaults, after everything else it offers. Each is declared
 * per stance, so the one that runs carries the intent: an empty hand helps,
 * disarms, grabs or punches it (unarmed_touch()), and an item is used on it, or
 * disarms, grabs or hits with it (hit_with_item()).
 */
/mob/living/declare_interactions(list/into)
	..()
	var/static/list/default_specs = list(
		INTERACT_HAND_DEFAULT_AS(I_HELP, "Help", PROC_REF(interaction_touch)),
		INTERACT_HAND_DEFAULT_AS(I_DISARM, "Shove", PROC_REF(interaction_touch)),
		INTERACT_HAND_DEFAULT_AS(I_GRAB, "Take hold", PROC_REF(interaction_touch)),
		INTERACT_HAND_DEFAULT_AS(I_HURT, "Punch", PROC_REF(interaction_touch)),
		INTERACT_ITEM_DEFAULT_AS(I_HELP, "Use on", PROC_REF(interaction_hit)),
		INTERACT_ITEM_DEFAULT_AS(I_DISARM, "Shove with", PROC_REF(interaction_hit)),
		INTERACT_ITEM_DEFAULT_AS(I_GRAB, "Hold with", PROC_REF(interaction_hit)),
		INTERACT_ITEM_DEFAULT_AS(I_HURT, "Hit", PROC_REF(interaction_hit)),
	)
	for(var/spec in default_specs)
		into += dq_interaction_from_spec(/mob/living, spec)

/mob/living/proc/interaction_touch(mob/living/user, obj/item/held, datum/interaction/interaction)
	unarmed_touch(user, interaction.stance)
	return TRUE

/// Signal listeners first (a nanoform's held body), then the hit. A hit that didn't use the input lets afterattack follow.
/mob/living/proc/interaction_hit(mob/user, obj/item/I, datum/interaction/interaction)
	if(attackby_stopped(src, I, user, dq_interaction_click_params(user)))
		return INTERACTION_HANDLED_PASS
	var/modifier = GLOB.interaction_entry_attack_modifier[user]
	var/hit = hit_with_item(I, user, isnull(modifier) ? 1 : modifier, interaction.stance)
	// An item that does no harm (attack() answers ITEM_INTERACT_FAILURE: force 0, no bludgeon, a stance that does not hit) did nothing to this mob: its own
	// afterattack follows, as it did before attack() answered with the ITEM_INTERACT_* flags (a spray, a syringe, a dropper, a splash all live there).
	if(hit == ITEM_INTERACT_FAILURE)
		return INTERACTION_HANDLED_PASS
	return hit ? TRUE : INTERACTION_HANDLED_PASS

/// An empty-hand touch on this mob in `stance` (I_HELP, I_DISARM, I_GRAB or I_HURT); mob types extend it (their unarmed combat). The base reacts for the AI and thorns.
/mob/living/proc/unarmed_touch(mob/living/user, stance = I_HELP)
	return

/// Hit with an item in `stance`: a patient-use, vore, then the attack (a phased swing when hostile).
/mob/living/proc/hit_with_item(obj/item/I, mob/user, attack_modifier = 1, stance = I_HURT)
	if(!ismob(user))
		return FALSE

	// Surgery is the patient's ops (surgery_ops.dm); scanners and stethoscopes take a use on a patient here.
	if(can_operate(src, user, stance) && I.use_on_patient(src, user, stance))
		return TRUE

	if(vore_attackby(I, user, stance)) // The vore, of course.
		return

	// Phased melee: a harm-intent attack with a real weapon winds up, telegraphs its swing
	// tiles, then resolves (see code/modules/mob/living/melee_swing.dm). Diverts the instant
	// attack. Non-harm intents, unarmed, and item-use on objects never reach this branch.
	if(isliving(user) && stance == I_HURT && I.force && !(I.flags & NOBLUDGEON))
		var/mob/living/attacker = user
		if(attacker.is_swinging)
			return FALSE // already mid-swing — ignore the queued attack click
		attacker.begin_melee_swing(src, I)
		return ITEM_INTERACT_SUCCESS // suppress afterattack; the swing resolves through I.attack() itself

	return I.attack(src, user, user.zone_sel?.selecting || BP_TORSO, attack_modifier, stance)

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
// `stance` is the input's stance (the adapter reads it once: input_stance()); I_HURT when a machine or AI fires it.
/obj/item/proc/afterattack(atom/target, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	return

//I would prefer to rename this attack_as_weapon(), but that would involve touching hundreds of files.
/// Used as a weapon on M in `stance`, the stance of the interaction that swung it (a mob's per-stance item defaults).
/obj/item/proc/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(!force || (flags & NOBLUDGEON))
		return ITEM_INTERACT_FAILURE
	if(M == user && stance != I_HURT)
		return ITEM_INTERACT_FAILURE
	if(M.is_incorporeal()) // No attacking phased entities :)
		return ITEM_INTERACT_FAILURE
	PUBLISH_LEGACY(src, /datum/notice/item_attack, M, user, target_zone)

	/////////////////////////
	M.lastattacker = user

	if(!no_attack_log)
		add_attack_logs(user,M,"attacked with [name] (STANCE: [uppertext(stance)]) (KIND: [injury_kind_name(injury_kind)])")
	/////////////////////////

	// A phased melee swing (melee_swing.dm) resolves its hits THROUGH this proc so
	// every weapon override / log / check above runs exactly once per victim — but
	// it has already set its own recovery cooldown and played the lunge, so skip the
	// instant-attack versions of both here.
	if(!user.melee_swing_resolving)
		user.setClickCooldown(user.get_attack_speed(src))
		user.do_attack_animation(M)

	var/hit_zone = M.resolve_item_attack(src, user, target_zone, stance)
	if(hit_zone)
		apply_hit_effect(M, user, hit_zone, attack_modifier, stance)

	return ITEM_INTERACT_SUCCESS

//Called when a weapon is used to make a successful melee attack on a mob. Returns the blocked result
// `stance` is the stance of the attack() that landed it (I_HURT unless the swing said otherwise).
/obj/item/proc/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier, stance = I_HURT)
	user.break_cloak()
	material_response_impact(get_turf(target), target)
	if(hitsound)
		playsound(src, hitsound, 50, 1, -1)

	var/power = force * user.factor(BF_MELEE_DAMAGE)

	if(user.has_mutation(HULK))
		power *= 2

	power *= attack_modifier

	return target.hit_with_weapon(src, user, power, hit_zone, stance)
