/**
 * Capability adapters (doc/rewrite/interactions.md §4).
 *
 * An adapter says how one kind of actor turns actions into effects: whether a
 * click is accepted at all, which click table it reads, and what Use does. The
 * modifier actions (Inspect, Alternate, Pull, ...) go through handler_for(),
 * which names the mob proc that runs them; AI and borgs override those procs.
 *
 * Use and Alternate first ask the interaction resolver (I2,
 * code/datums/interactions/). When no interaction answers, they fall back to
 * today's handlers: attackby through resolve_attackby (whose tool_act path
 * reaches the resolver again for tool interactions), attack_hand through
 * UnarmedAttack, attack_ai, attack_robot, attack_ghost, attack_tk, click_alt.
 * allows_interaction() is where each kind of actor limits what it can do.
 *
 * I3: the AI, cyborg, ghost and telekinesis adapters produce the same actions
 * as hands, filtered through what the actor can do:
 * - AI: remote, no hands, needs camera sight. Only INTERACTION_TAG_REMOTE.
 * - Cyborg: its modules are its held items; everything but observer-only.
 * - Ghost: observer-only (INTERACTION_TAG_OBSERVER); Use opens UIs to view.
 * - Telekinesis: at range, no tools.
 * Their Use tries the resolver first, then the legacy proc. Where that legacy
 * proc only forwarded to the hand's (attack_ai -> attack_hand and friends), the
 * override is gone and the type sets `silicon_use` instead (SILICON_USE_*).
 */

/atom
	/// SILICON_USE_* / ROBOT_USE_*: what the AI's and cyborgs' plain Use does when
	/// the type doesn't override attack_ai or attack_robot. A type var: no per-instance cost.
	var/silicon_use = NONE
/datum/input_adapter
	var/name = "abstract"

/// Adapters are singletons; GLOB.input_adapters maps type -> instance.
GLOBAL_LIST_INIT(input_adapters, init_input_adapters())

/proc/init_input_adapters()
	var/list/adapters = list()
	for(var/datum/input_adapter/adapter_type as anything in subtypesof(/datum/input_adapter))
		adapters[adapter_type] = new adapter_type
	return adapters

/// This mob's capability adapter.
/mob/proc/input_adapter()
	return INPUT_ADAPTER(hands)

/mob/observer/dead/input_adapter()
	return INPUT_ADAPTER(ghost)

/mob/living/silicon/ai/input_adapter()
	return INPUT_ADAPTER(ai)

/mob/living/silicon/robot/input_adapter()
	return INPUT_ADAPTER(robot)

/// Returns TRUE if the click should be routed. Handles cooldowns, click intercepts and buildmode.
/datum/input_adapter/proc/accept_click(mob/user, atom/target, params)
	if(!user.checkClickCooldown())
		return FALSE
	user.setClickCooldown(1)
	if(user.check_click_intercept(params, target))
		return FALSE
	if(user.client?.buildmode)
		build_click(user, user.client.buildmode, params, target)
		return FALSE
	return TRUE

/datum/input_adapter/proc/click_table()
	return GLOB.input_router.standard_click_table()

/// The mob proc that runs a non-Use action, or null if the action does nothing.
/datum/input_adapter/proc/handler_for(action)
	switch(action)
		if(INPUT_ACTION_INSPECT)
			return TYPE_PROC_REF(/mob, ShiftClickOn)
		if(INPUT_ACTION_POINT)
			return TYPE_PROC_REF(/mob, ShiftMiddleClickOn)
		if(INPUT_ACTION_QUICK)
			return TYPE_PROC_REF(/mob, CtrlShiftClickOn)
		if(INPUT_ACTION_LOOT)
			return TYPE_PROC_REF(/mob, alt_shift_click_on)
		if(INPUT_ACTION_TAG)
			return TYPE_PROC_REF(/mob, CtrlMiddleClickOn)
		if(INPUT_ACTION_SWAP_HANDS)
			return TYPE_PROC_REF(/mob, MiddleClickOn)
		if(INPUT_ACTION_ALTERNATE_SECONDARY)
			return TYPE_PROC_REF(/mob, AltClickSecondaryOn)
		if(INPUT_ACTION_ALTERNATE)
			return TYPE_PROC_REF(/mob, AltClickOn)
		if(INPUT_ACTION_PULL)
			return TYPE_PROC_REF(/mob, CtrlClickOn)
	return null

/datum/input_adapter/proc/perform(mob/user, atom/target, action, list/modifiers, params)
	switch(action)
		if(INPUT_ACTION_USE)
			return use(user, target, modifiers, params)
		if(INPUT_ACTION_MENU)
			return open_interaction_menu(user, target)
		if(INPUT_ACTION_ALTERNATE)
			if(try_interaction(user, target, user.get_active_hand(), INPUT_ACTION_ALTERNATE))
				return TRUE
	var/handler = handler_for(action)
	if(handler)
		call(user, handler)(target, params)

/// Whether this kind of actor can ever do `interaction`. Excluded ones aren't even listed as blocked.
/// Observer-only interactions are for ghosts alone.
/datum/input_adapter/proc/allows_interaction(mob/user, atom/target, datum/interaction/interaction)
	return !(INTERACTION_TAG_OBSERVER in interaction.tags)

/// Use through the resolver with nothing in hand. TRUE if an interaction answered.
/datum/input_adapter/proc/use_interaction(mob/user, atom/target)
	return try_interaction(user, target, null, INPUT_ACTION_USE, null, TRUE, src) ? TRUE : FALSE

/// The Use action.
/datum/input_adapter/proc/use(mob/user, atom/target, list/modifiers, params)
	return

/**
 * One Use run as a Disarm or Grab (use_attack_variant() has set the variant).
 * Only actors with hands have the variants; others do nothing.
 */
/datum/input_adapter/proc/use_variant(mob/user, atom/target, variant)
	return FALSE

/// The Self-use action: the held item used on itself.
/datum/input_adapter/proc/self_use(mob/user, obj/item/held, list/modifiers)
	held.attack_self(user, modifiers)

/// The Drag action.
/datum/input_adapter/proc/drag(mob/user, atom/dragged, atom/over, src_location, over_location, src_control, over_control, params)
	if(!dragged.Adjacent(user) || !over.Adjacent(user))
		return // should stop you from dragging through windows
	if(user.is_incorporeal())
		return
	INVOKE_ASYNC(over, TYPE_PROC_REF(/atom, MouseDrop_T), dragged, user, src_location, over_location, src_control, over_control, params)

/// A category key: the best interaction of that category on the target.
/datum/input_adapter/proc/perform_category(mob/user, atom/target, category)
	return try_interaction_category(user, target, category)

// ---------------------------------------------------------------------------
// Hands: every mob that interacts by touch (humans, animals, simple mobs, pAIs).

/datum/input_adapter/hands
	name = "hands"

/datum/input_adapter/hands/accept_click(mob/user, atom/target, params)
	if(!user.checkClickCooldown())
		return FALSE
	user.setClickCooldown(1)
	if(user.check_click_intercept(params, target) || HAS_TRAIT(user, TRAIT_NO_TRANSFORM))
		return FALSE
	if(user.client?.buildmode)
		build_click(user, user.client.buildmode, params, target)
		return FALSE
	return TRUE

/datum/input_adapter/hands/use_variant(mob/user, atom/target, variant)
	return use(user, target, list(), "")

/*
	Use for a mob with hands. Checks state, whether an item is held and whether
	the target is in reach, then passes the click to whoever receives it:
	* mob/UnarmedAttack(atom, adjacent) - adjacent, no item in hand
	* atom/attackby(item, user) - adjacent, through resolve_attackby
	* item/afterattack(atom, user, adjacent, params) - ranged and adjacent
	* mob/RangedAttack(atom, params) - ranged, no item: laser eyes and telekinesis
*/
/datum/input_adapter/hands/use(mob/user, atom/A, list/modifiers, params)
	if(user.intercept_use(A, params))
		return

	if(INCAPACITATED_IGNORING(user, INCAPABLE_RESTRAINTS|INCAPABLE_STASIS))
		return

	if(user.stat || user.get_paralysis() || user.get_stunned())
		return

	user.face_atom(A) // change direction to face what you clicked on

	if(istype(user.loc, /obj/mecha))
		if(!locate(/turf) in list(A, A.loc)) // Prevents inventory from being drilled
			return
		var/obj/mecha/M = user.loc
		return M.click_action(A, user, params)

	// A restrained mob can still make unarmed attacks on adjacent mobs (bites).
	// For other restrained interactions, override RestrainedClickOn.
	var/currently_restrained = FALSE
	if(user.restrained())
		user.setClickCooldown(10)
		user.RestrainedClickOn(A)
		currently_restrained = TRUE

	if(!currently_restrained && user.in_throw_mode && (isturf(A) || isturf(A.loc)) && user.throw_item(A))
		user.trigger_aiming(TARGET_CAN_CLICK)
		user.throw_mode_off()
		return TRUE

	var/obj/item/W = user.get_active_hand()

	// Empty-handed interactions (I2) come before the legacy attack_hand chain.
	if(!currently_restrained && !W && try_interaction(user, A, null, INPUT_ACTION_USE, null, TRUE))
		user.trigger_aiming(TARGET_CAN_CLICK)
		return TRUE

	if(!currently_restrained && W == A)
		self_use(user, W, modifiers)
		user.trigger_aiming(TARGET_CAN_CLICK)
		user.update_inv_active_hand(0)
		return TRUE

	// Atoms on your person: A is your location but not a turf; or on you (backpack);
	// or on something on you (box in backpack). sdepth is needed because contents
	// depth does not equal inventory storage depth.
	var/sdepth = A.storage_depth(user)
	if(!currently_restrained && ((!isturf(A) && A == user.loc) || (sdepth <= MAX_STORAGE_REACH)))
		if(W)
			var/resolved = W.resolve_attackby(A, user, click_parameters = params)
			// A consumed result means resolve_attackby did something; skip afterattack.
			if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
				W.afterattack(A, user, 1, params) // 1 indicates adjacency
		else
			if(ismob(A)) // No instant mob attacking
				user.setClickCooldown(user.get_attack_speed())
			user.UnarmedAttack(A, 1)

		user.trigger_aiming(TARGET_CAN_CLICK)
		return 1

	if(!currently_restrained && isbelly(user.loc) && (user.loc == A.loc))
		if(W)
			var/resolved = W.resolve_attackby(A, user)
			if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
				W.afterattack(A, user, 1, params) // 1: clicking something Adjacent
		else
			if(ismob(A)) // No instant mob attacking
				user.setClickCooldown(user.get_attack_speed())
			user.UnarmedAttack(A, 1)
		return

	if(!isturf(user.loc)) // No telekinesis from inside a closet
		return

	// Atoms on turfs: A is a turf, on a turf, or in something on a turf (pen in a box),
	// but not something in something on a turf (pen in a box in a backpack).
	sdepth = A.storage_depth_turf()
	if(isturf(A) || isturf(A.loc) || (sdepth <= MAX_STORAGE_REACH))
		if(currently_restrained)
			if(ismob(A) && A.Adjacent(user)) // restrained and adjacent
				user.setClickCooldown(user.get_attack_speed())
				user.UnarmedAttack(A, 1)
				user.trigger_aiming(TARGET_CAN_CLICK)
				return
		else
			if(A.Adjacent(user) || (W && W.attack_can_reach(user, A, W.reach))) // see adjacent.dm
				if(W && !user.restrained())
					// Return 1 in attackby() to prevent afterattack() effects (when safely moving items for example)
					var/resolved = W.resolve_attackby(A, user, click_parameters = params)
					if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
						W.afterattack(A, user, 1, params) // 1: clicking something Adjacent
				else
					if(ismob(A)) // No instant mob attacking
						user.setClickCooldown(user.get_attack_speed())
					user.UnarmedAttack(A, 1)
				user.trigger_aiming(TARGET_CAN_CLICK)
				return
			else // non-adjacent click
				if(W)
					W.afterattack(A, user, 0, params) // 0: not Adjacent
				else
					user.RangedAttack(A, params)

				user.trigger_aiming(TARGET_CAN_CLICK)
	return 1

/// Hook for mobs that take over a plain Use click before the hands chain runs
/// (the swoopie's vacuum). Return TRUE if handled. Modifier clicks never get here.
/mob/proc/intercept_use(atom/A, params)
	return FALSE

// ---------------------------------------------------------------------------
// Telekinesis: remote reach for a mob with a telekinetic grip.

/datum/input_adapter/telekinesis
	name = "telekinesis"

/// Telekinesis reaches, but holds no tools: only tool-less interactions.
/datum/input_adapter/telekinesis/allows_interaction(mob/user, atom/target, datum/interaction/interaction)
	if(interaction.tool)
		return FALSE
	return ..()

/// Use at range: grab or poke the target telekinetically.
/datum/input_adapter/telekinesis/use(mob/user, atom/target, list/modifiers, params)
	if(get_dist(user, target) > TK_MAXRANGE)
		to_chat(user, TK_OUTRANGED_MESSAGE)
		return
	if(user.stat)
		return
	if(use_interaction(user, target))
		return TRUE
	target.attack_tk(user)

// ---------------------------------------------------------------------------
// Ghosts: observer-only.

/datum/input_adapter/ghost
	name = "ghost"

/// Ghosts only observe: they get observer-only interactions and nothing else.
/datum/input_adapter/ghost/allows_interaction(mob/user, atom/target, datum/interaction/interaction)
	return (INTERACTION_TAG_OBSERVER in interaction.tags) ? TRUE : FALSE

/// Observer-only interactions first; then attack_ghost, which on /obj opens the
/// UI to view (so types no longer override it just to call tgui_interact).
/// Checking config.ghost_interaction is the responsibility of attack_ghost overrides.
/datum/input_adapter/ghost/use(mob/user, atom/target, list/modifiers, params)
	if(use_interaction(user, target))
		return TRUE
	target.attack_ghost(user)

// ---------------------------------------------------------------------------
// AI: remote, no hands, acts through the camera network.

/datum/input_adapter/ai
	name = "ai"

/datum/input_adapter/ai/accept_click(mob/living/silicon/ai/user, atom/target, params)
	if(!user.checkClickCooldown())
		return FALSE
	user.setClickCooldown(1)
	if(user.client?.buildmode) // comes after object.Click to allow buildmode gui objects to be clicked
		build_click(user, user.client.buildmode, params, target)
		return FALSE
	if(user.multicam_on)
		var/turf/T = get_turf(target)
		if(T)
			for(var/atom/movable/screen/movable/pic_in_pic/ai/P in T.vis_locs)
				if(P.ai == user)
					P.Click(params)
					break
	if(user.check_click_intercept(params, target))
		return FALSE
	if(user.stat || user.control_disabled)
		return FALSE
	return TRUE

/// The AI reads fewer modifiers than other mobs: no extra mouse buttons, no
/// point, no loot panel, and alt-click ignores right-click.
/datum/input_adapter/ai/click_table()
	var/static/list/table = list(
		list(list(SHIFT_CLICK, CTRL_CLICK), INPUT_ACTION_QUICK),
		list(list(MIDDLE_CLICK), INPUT_ACTION_SWAP_HANDS),
		list(list(SHIFT_CLICK), INPUT_ACTION_INSPECT),
		list(list(ALT_CLICK), INPUT_ACTION_ALTERNATE),
		list(list(CTRL_CLICK), INPUT_ACTION_PULL),
		list(list(RIGHT_CLICK), INPUT_ACTION_RIGHT_CLICK_BINDING),
	)
	return table

/// The AI has no hands: only tool-less interactions tagged remote, on what its cameras can see.
/datum/input_adapter/ai/allows_interaction(mob/living/silicon/ai/user, atom/target, datum/interaction/interaction)
	if(interaction.tool || !(INTERACTION_TAG_REMOTE in interaction.tags))
		return FALSE
	return istype(user) ? user.has_camera_sight(target) : TRUE

/datum/input_adapter/ai/use(mob/living/silicon/ai/user, atom/target, list/modifiers, params)
	var/obj/effect/overlay/aiholo/hologram = user.holo ? LAZYACCESS(user.holo.masters, user) : null
	if(istype(hologram))
		hologram.set_dir(get_dir(get_turf(hologram), get_turf(target)))

	if(user.aiCamera?.in_camera_mode)
		user.aiCamera.camera_mode_off()
		user.aiCamera.captureimage(target, user)
		return

	target.add_hiddenprint(user)
	if(use_interaction(user, target))
		return TRUE
	// attack_ai: the type's override, or the hand's Use per its silicon_use.
	target.attack_ai(user)

// ---------------------------------------------------------------------------
// Cyborgs: AI-style remote interfacing with an empty gripper, reach-limited items.

/datum/input_adapter/robot
	name = "robot"

/datum/input_adapter/robot/accept_click(mob/living/silicon/robot/user, atom/target, params)
	if(!user.checkClickCooldown())
		return FALSE
	if(user.check_click_intercept(params, target))
		return FALSE
	user.setClickCooldown(1)
	if(user.client?.buildmode) // comes after object.Click to allow buildmode gui objects to be clicked
		build_click(user, user.client.buildmode, params, target)
		return FALSE
	return TRUE

/*
	Cyborgs have no range restriction on attack_robot(), because it is basically an
	AI click. They do have a range restriction on item use.
*/
/datum/input_adapter/robot/use(mob/living/silicon/robot/user, atom/A, list/modifiers, params)
	if(!user.can_click_act())
		return

	user.face_atom(A) // change direction to face what you clicked on

	if(user.aiCamera && user.aiCamera.in_camera_mode)
		user.aiCamera.camera_mode_off()
		if(user.is_component_functioning(ROBOT_SLOT_CAMERA))
			user.aiCamera.captureimage(A, user)
		else
			to_chat(user, span_userdanger("Your camera isn't functional."))
		return

	var/obj/item/W = user.get_active_hand(A)

	// Cyborgs have no range-checking unless there is item use
	if(!W)
		// A bolted cyborg can't remotely interface with anything but its own module.
		if(user.get_restraining_bolt() && A.loc != user.module)
			return
		A.add_hiddenprint(user)
		if(use_interaction(user, A))
			return TRUE
		// attack_robot: the type's override, or silicon_use (the hand's Use, or interfacing like the AI).
		A.attack_robot(user)
		return
	// buckled cannot prevent machine interlinking but stops arm movement
	if(user.buckled)
		return

	if(W == A)
		self_use(user, W)
		return

	// cyborgs are prohibited from using storage items, so (A.loc in contents) is not needed
	if(A == user.loc || (A in user.loc) || (A in user.contents))
		// No adjacency checks
		var/resolved = W.resolve_attackby(A, user, click_parameters = params)
		if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
			W.afterattack(A, user, 1, params)
		return

	if(!isturf(user.loc))
		return

	var/sdepth = A.storage_depth_turf()
	if(isturf(A) || isturf(A.loc) || (sdepth <= MAX_STORAGE_REACH))
		if(A.Adjacent(user) || (W && W.attack_can_reach(user, A, W.reach))) // see adjacent.dm, allows robots to use ranged melee weapons
			SEND_SIGNAL(user, COMSIG_ROBOT_ITEM_ATTACK, W, user, params) // we ATTEMPTED to attack someone.
			var/resolved = W.resolve_attackby(A, user, click_parameters = params)
			if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
				W.afterattack(A, user, 1, params)
			return
		else
			W.afterattack(A, user, 0, params)
			return

/**
 * Whether the AI can see `target` to act on it: in its own view, or (installed
 * in a core) on the camera network, or (carded) within view range. The same
 * rule as the AI's tgui state (default_can_use_tgui_topic).
 */
/mob/living/silicon/ai/proc/has_camera_sight(atom/target)
	var/turf/T = get_turf(target)
	if(!T)
		return FALSE
	var/range = client ? client.view : world.view
	if(target in dview(range, get_turf(src))) // line of sight from its core, whatever the lighting
		return TRUE
	if(is_in_chassis())
		return (GLOB.cameranet && GLOB.cameranet.checkTurfVis(T)) ? TRUE : FALSE
	return get_dist(target, src) <= (isnum(range) ? range : world.view)
