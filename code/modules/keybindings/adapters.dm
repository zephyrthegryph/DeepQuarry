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

/// Click classification rows for this adapter (see /datum/input_router). Shared, read-only.
TYPE_TABLE_DECLARE(/datum/input_adapter, adapter_click_table, TYPE_TABLE_GET(GLOB.input_router, standard_click_table))

/// The mob proc that runs a non-Use action, or null if the action does nothing.
/// Each action is one mob proc named after it; mob types override the proc (AI, cyborgs, hardsuits).
/datum/input_adapter/proc/handler_for(action)
	var/static/list/handlers = list(
		INPUT_ACTION_INSPECT = TYPE_PROC_REF(/mob, action_inspect),
		INPUT_ACTION_POINT = TYPE_PROC_REF(/mob, action_point),
		INPUT_ACTION_QUICK = TYPE_PROC_REF(/mob, action_quick),
		INPUT_ACTION_LOOT = TYPE_PROC_REF(/mob, action_loot),
		INPUT_ACTION_TAG = TYPE_PROC_REF(/mob, action_tag),
		INPUT_ACTION_SWAP_HANDS = TYPE_PROC_REF(/mob, action_swap_hands),
		INPUT_ACTION_ALTERNATE_SECONDARY = TYPE_PROC_REF(/mob, action_alternate_secondary),
		INPUT_ACTION_ALTERNATE = TYPE_PROC_REF(/mob, action_alternate),
		INPUT_ACTION_PULL = TYPE_PROC_REF(/mob, action_pull),
	)
	return handlers[action]

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
	return !(INTERACTION_TAG_OBSERVER in interaction.tags) && !(INTERACTION_TAG_SILICON in interaction.tags) && !(INTERACTION_TAG_TELEKINESIS in interaction.tags)

/// Use through the resolver with nothing in hand. TRUE if an interaction answered.
/datum/input_adapter/proc/use_interaction(mob/user, atom/target)
	return try_interaction(user, target, null, INPUT_ACTION_USE, null, TRUE, src) ? TRUE : FALSE

/// The Use action.
/datum/input_adapter/proc/use(mob/user, atom/target, list/modifiers, params)
	return

/// What this kind of actor's Use does when no interaction answers.
/datum/input_adapter/proc/default_use(mob/user, atom/target)
	return FALSE

/// actor_use(/datum/input_adapter/ai, user, target): use_as() on that adapter's singleton.
/proc/actor_use(adapter_type, mob/user, atom/target)
	var/datum/input_adapter/adapter = GLOB.input_adapters[adapter_type]
	return adapter.use_as(user, target)

/// actor_use_default(/datum/input_adapter/ghost, user, target): that adapter's default Use.
/proc/actor_use_default(adapter_type, mob/user, atom/target)
	var/datum/input_adapter/adapter = GLOB.input_adapters[adapter_type]
	return adapter.default_use(user, target)

/// Use `target` as this kind of actor, for code that makes an actor use something directly
/// (an AI hotkey, a pAI reaching through a cable): its interactions, then its default.
/datum/input_adapter/proc/use_as(mob/user, atom/target)
	if(use_interaction(user, target))
		return TRUE
	return default_use(user, target)

/**
 * One Use run as a Disarm or Grab (use_attack_variant() has set the variant).
 * Only actors with hands have the variants; others do nothing.
 */
/datum/input_adapter/proc/use_variant(mob/user, atom/target, variant)
	return FALSE

/// The Self-use action: the held item used on itself.
/datum/input_adapter/proc/self_use(mob/user, obj/item/held, list/modifiers)
	held.attack_self(user, modifiers)

/// The Drag action: the inbox resolves it (the target's ops see the dragged atom as the held one), and what no op answers is drag_legacy().
/datum/input_adapter/proc/drag(mob/user, atom/dragged, atom/over, src_location, over_location, src_control, over_control, params)
	if(!dragged.Adjacent(user) || !over.Adjacent(user))
		return // should stop you from dragging through windows
	if(user.is_incorporeal())
		return
	input_submit(new /datum/input_event/drag(user, dragged, over, list(src_location, over_location, src_control, over_control, params)))

/// The drag no op took: the gesture entries, then MouseDrop_T of the target.
/datum/input_adapter/proc/drag_legacy(mob/user, atom/dragged, atom/over, list/legacy)
	if(try_gesture_drag(user, dragged, over))
		return
	INVOKE_ASYNC(over, TYPE_PROC_REF(/atom, MouseDrop_T), dragged, user, legacy?[1], legacy?[2], legacy?[3], legacy?[4], legacy?[5]) // ALLOW(scheduler): MouseDrop_T overrides may prompt/do_after

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
	if(user.check_click_intercept(params, target) || has_trait(user, TRAIT_NO_TRANSFORM))
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
	if(user.intercept_use(A, params, user.input_stance()))
		return

	if(INCAPACITATED_IGNORING(user, INCAPABLE_RESTRAINTS|INCAPABLE_STASIS))
		return

	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_STUNNED))
		return

	user.face_atom(A) // change direction to face what you clicked on

	if(istype(user.loc, /obj/mecha))
		if(!locate_in_list(list(A, A.loc), /turf)) // Prevents inventory from being drilled
			return
		var/obj/mecha/M = user.loc
		return M.click_action(A, user, params)

	// A restrained mob can still make unarmed attacks on adjacent mobs (bites).
	// For other restrained interactions, override RestrainedClickOn.
	var/currently_restrained = FALSE
	if(user.restrained())
		user.setClickCooldown(10)
		user.RestrainedClickOn(A, user.input_stance())
		currently_restrained = TRUE

	if(!currently_restrained && user.in_throw_mode && (isturf(A) || isturf(A.loc)) && user.throw_item(A, user.input_stance()))
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
				after_click(W, A, user, 1, params, user.input_stance()) // 1 indicates adjacency
		else
			if(ismob(A)) // No instant mob attacking
				user.setClickCooldown(user.get_attack_speed())
			user.UnarmedAttack(A, 1, user.input_stance())

		user.trigger_aiming(TARGET_CAN_CLICK)
		return 1

	if(!currently_restrained && isbelly(user.loc) && (user.loc == A.loc))
		if(W)
			var/resolved = W.resolve_attackby(A, user)
			if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
				after_click(W, A, user, 1, params, user.input_stance()) // 1: clicking something Adjacent
		else
			if(ismob(A)) // No instant mob attacking
				user.setClickCooldown(user.get_attack_speed())
			user.UnarmedAttack(A, 1, user.input_stance())
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
				user.UnarmedAttack(A, 1, user.input_stance())
				user.trigger_aiming(TARGET_CAN_CLICK)
				return
		else
			if(A.Adjacent(user) || (W && W.attack_can_reach(user, A, W.reach))) // see adjacent.dm
				if(W && !user.restrained())
					// Return 1 in attackby() to prevent afterattack() effects (when safely moving items for example)
					var/resolved = W.resolve_attackby(A, user, click_parameters = params)
					if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
						after_click(W, A, user, 1, params, user.input_stance()) // 1: clicking something Adjacent
				else
					if(ismob(A)) // No instant mob attacking
						user.setClickCooldown(user.get_attack_speed())
					user.UnarmedAttack(A, 1, user.input_stance())
				user.trigger_aiming(TARGET_CAN_CLICK)
				return
			else // non-adjacent click
				if(W)
					after_click(W, A, user, 0, params, user.input_stance()) // 0: not Adjacent
				else
					user.RangedAttack(A, params, user.input_stance())

				user.trigger_aiming(TARGET_CAN_CLICK)
	return 1

/// Hook for mobs that take over a plain Use click before the hands chain runs
/// (the swoopie's vacuum). Return TRUE if handled. Modifier clicks never get here.
/mob/proc/intercept_use(atom/A, params, stance = I_HURT)
	return FALSE

// ---------------------------------------------------------------------------
// Telekinesis: remote reach for a mob with a telekinetic grip.

/datum/input_adapter/telekinesis
	name = "telekinesis"

/// Telekinesis reaches, but holds no tools: only tool-less interactions.
/datum/input_adapter/telekinesis/allows_interaction(mob/user, atom/target, datum/interaction/interaction)
	if(interaction.tool)
		return FALSE
	if(INTERACTION_TAG_TELEKINESIS in interaction.tags)
		return TRUE
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
	default_use(user, target)

/**
 * A telekinetic Use no interaction answered: grab a loose object (an item on the floor,
 * or anything unanchored) with a telekinetic grab; otherwise poke it as an unarmed hand
 * would. Mobs, carried items and objects with `tk_reach = FALSE` are left alone.
 */
/datum/input_adapter/telekinesis/default_use(mob/user, atom/target)
	if(user.stat || ismob(target))
		return FALSE
	var/obj/O = target
	if(istype(O))
		if(!O.tk_reach)
			return FALSE
		if(isitem(O) && !isturf(O.loc))
			return FALSE
	if(!istype(O) || (O.anchored && !isitem(O)))
		user.UnarmedAttack(target, 0, user.input_stance())
		return TRUE
	var/obj/item/tk_grab/grab = new(O)
	user.put_in_active_hand(grab)
	rel_set(grab, nameof(grab.host), user)
	grab.focus_object(O)
	return TRUE

// ---------------------------------------------------------------------------
// Ghosts: observer-only.

/datum/input_adapter/ghost
	name = "ghost"

/// Ghosts only observe: they get observer-only interactions and nothing else. An op is an observer's when it answers the
/// observer profile's gesture (ACT_EXAMINE) over the observer route (ROUTE_UI, mob/observer/dead/op_route()): the old
/// INTERACT_OBSERVER as cap_op(action = ACT_EXAMINE, via = ROUTE_UI, by = NONE).
/datum/input_adapter/ghost/allows_interaction(mob/user, atom/target, datum/interaction/interaction)
	if(INTERACTION_TAG_OBSERVER in interaction.tags)
		return TRUE
	var/datum/interaction/capability/E = interaction
	if(istype(E) && E.op && !E.op.legacy)
		return E.op.action == ACT_EXAMINE && (E.op.via & ROUTE_UI) ? TRUE : FALSE
	return FALSE

/// Observer-only interactions first; then attack_ghost, which on /obj opens the
/// UI to view (so types no longer override it just to call tgui_interact).
/// Checking config.ghost_interaction is the responsibility of attack_ghost overrides.
/datum/input_adapter/ghost/use(mob/user, atom/target, list/modifiers, params)
	if(use_interaction(user, target))
		return TRUE
	default_use(user, target)

/// A ghost's Use when no observer interaction answers: an object's UI, to view; an inquisitive ghost examines.
/datum/input_adapter/ghost/default_use(mob/observer/dead/user, atom/target)
	if(isobj(target))
		target.tgui_interact(user)
	if(user.client?.inquisitive_ghost)
		user.examinate(target)
	return TRUE

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
TYPE_TABLE(/datum/input_adapter/ai, adapter_click_table, list( \
	list(list(SHIFT_CLICK, CTRL_CLICK), INPUT_ACTION_QUICK), \
	list(list(MIDDLE_CLICK), INPUT_ACTION_SWAP_HANDS), \
	list(list(SHIFT_CLICK), INPUT_ACTION_INSPECT), \
	list(list(ALT_CLICK), INPUT_ACTION_ALTERNATE), \
	list(list(CTRL_CLICK), INPUT_ACTION_PULL), \
	list(list(RIGHT_CLICK), INPUT_ACTION_RIGHT_CLICK_BINDING), \
))

/// The AI has no hands: only tool-less interactions tagged remote, and ops that travel the interface route (the old
/// INTERACT_SILICON as cap_control(), or cap_op(via = ROUTE_INTERFACE)), on what its cameras can see.
/datum/input_adapter/ai/allows_interaction(mob/living/silicon/ai/user, atom/target, datum/interaction/interaction)
	if(interaction.tool)
		return FALSE
	var/datum/interaction/capability/E = interaction
	var/remote_op = istype(E) && E.op && !E.op.legacy && (E.op.via & ROUTE_INTERFACE)
	if(!remote_op && !(INTERACTION_TAG_REMOTE in interaction.tags))
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
	default_use(user, target)

/// The AI's Use when no silicon interaction answers: what the type's `silicon_use` says.
/datum/input_adapter/ai/default_use(mob/user, atom/target)
	if(target.silicon_use & SILICON_USE_HAND)
		return target.attack_hand(user)
	if(target.silicon_use & SILICON_USE_UI)
		return target.tgui_interact(user)
	return FALSE

// ---------------------------------------------------------------------------
// Cyborgs: AI-style remote interfacing with an empty gripper, reach-limited items.

/datum/input_adapter/robot
	name = "robot"

/// A cyborg's empty-gripper Use when no interaction answers: a hand's Use where the type says so
/// (or on something with a mob buckled to it, so anti-robot valves can't be worked around it), else like the AI.
/datum/input_adapter/robot/default_use(mob/user, atom/target)
	if(target.silicon_use & ROBOT_USE_HAND)
		return target.attack_hand(user)
	if(target.silicon_use & ROBOT_USE_HAND_ADJACENT)
		return target.Adjacent(user) ? target.attack_hand(user) : FALSE
	if(isobj(target) && target.Adjacent(user))
		var/obj/O = target
		if(O.has_buckled_mobs())
			return O.attack_hand(user)
	return actor_use_default(/datum/input_adapter/ai, user, target)

/// Cyborgs get everything but observer-only and telekinesis-only interactions, silicon-only ones included.
/datum/input_adapter/robot/allows_interaction(mob/user, atom/target, datum/interaction/interaction)
	return !(INTERACTION_TAG_OBSERVER in interaction.tags) && !(INTERACTION_TAG_TELEKINESIS in interaction.tags)

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
	Cyborgs have no range restriction on empty-gripper Use, because it is basically an
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
		default_use(user, A)
		return
	// buckled cannot prevent machine interlinking but stops arm movement
	if(user?.buckled_to())
		return

	if(W == A)
		self_use(user, W)
		return

	// cyborgs are prohibited from using storage items, so (A.loc in contents) is not needed
	if(A == user.loc || (A in user.loc) || (is_in_holder(A, user)))
		// No adjacency checks
		var/resolved = W.resolve_attackby(A, user, click_parameters = params)
		if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
			after_click(W, A, user, 1, params, user.input_stance())
		return

	if(!isturf(user.loc))
		return

	var/sdepth = A.storage_depth_turf()
	if(isturf(A) || isturf(A.loc) || (sdepth <= MAX_STORAGE_REACH))
		if(A.Adjacent(user) || (W && W.attack_can_reach(user, A, W.reach))) // see adjacent.dm, allows robots to use ranged melee weapons
			PUBLISH_LEGACY(user, /datum/notice/robot_item_attack, W, user, params)
			var/resolved = W.resolve_attackby(A, user, click_parameters = params)
			if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
				after_click(W, A, user, 1, params, user.input_stance())
			return
		else
			after_click(W, A, user, 0, params, user.input_stance())
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
