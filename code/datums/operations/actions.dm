// Actions (doc/rewrite/dx_conventions.md, "Operations").
//
// An action is what the player means ("open", "lock", "insert"); an op (cap_op) is one way a target
// does it. Ops name the action they answer (cap_op(action = ACT_LOCK)); a gesture (click, alt-click,
// drag...) reaches actions through the actor's bind profile:
//
//	gesture -> profile's priority list of actions -> the first action with an applicable op on the target
//
// A plain click is ACT_USE, a drag is ACT_DROP_ONTO. The one entry points are
//	perform_action(mob, target, ACT_X)   run it
//	test_action(mob, target, ACT_X)      null when it would run, else why not
//	action_options(mob, target)          the radial menu's data
//	screentip_for(mob, target, gesture)  the screentip line for a gesture
// plus the UI route (act("action", {id}) on the window of any holder of op entries) and the "Act" command-bar verb.
// An action's ops are the cap_op() entries of the target with op.action == the action.

// ---- definitions ----

/datum/action_def
	abstract_type = /datum/action_def
	/// ACT_*: the id ops, profiles and the UI name it by.
	var/id
	var/name
	/// GESTURE_* this action answers when the profile has no list for the gesture.
	var/list/binds
	/// Icon state or font-awesome name for the radial menu.
	var/radial_icon
	/// ACT_CAT_*: radial / screentip grouping.
	var/category = ACT_CAT_USE

/datum/action_def/use
	id = ACT_USE
	name = "Use"
	binds = list(GESTURE_CLICK, GESTURE_SELF)
	radial_icon = "hand-pointer"
	category = ACT_CAT_USE

/datum/action_def/drop_onto
	id = ACT_DROP_ONTO
	name = "Put onto"
	binds = list(GESTURE_DRAG)
	radial_icon = "arrow-down"
	category = ACT_CAT_ITEM

/datum/action_def/open
	id = ACT_OPEN
	name = "Open"
	radial_icon = "door-open"
	category = ACT_CAT_STATE

/datum/action_def/close
	id = ACT_CLOSE
	name = "Close"
	radial_icon = "door-closed"
	category = ACT_CAT_STATE

/datum/action_def/toggle
	id = ACT_TOGGLE
	name = "Toggle"
	radial_icon = "toggle-on"
	category = ACT_CAT_STATE

/datum/action_def/lock
	id = ACT_LOCK
	name = "Lock"
	radial_icon = "lock"
	category = ACT_CAT_STATE

/datum/action_def/unlock
	id = ACT_UNLOCK
	name = "Unlock"
	radial_icon = "unlock"
	category = ACT_CAT_STATE

/datum/action_def/insert
	id = ACT_INSERT
	name = "Insert"
	radial_icon = "arrow-right-to-bracket"
	category = ACT_CAT_ITEM

/datum/action_def/eject
	id = ACT_EJECT
	name = "Eject"
	radial_icon = "eject"
	category = ACT_CAT_ITEM

/datum/action_def/pry
	id = ACT_PRY
	name = "Pry"
	radial_icon = "screwdriver"
	category = ACT_CAT_MAINTAIN

/datum/action_def/repair
	id = ACT_REPAIR
	name = "Repair"
	radial_icon = "wrench"
	category = ACT_CAT_MAINTAIN

/datum/action_def/dismantle
	id = ACT_DISMANTLE
	name = "Dismantle"
	radial_icon = "hammer"
	category = ACT_CAT_MAINTAIN

/datum/action_def/examine
	id = ACT_EXAMINE
	name = "Examine"
	binds = list(GESTURE_SHIFT)
	radial_icon = "magnifying-glass"
	category = ACT_CAT_INFO

/datum/action_def/pull
	id = ACT_PULL
	name = "Pull"
	binds = list(GESTURE_CTRL)
	radial_icon = "hand-back-fist"
	category = ACT_CAT_USE

/// ACT_* id -> the action definition singleton.
GLOBAL_LIST_INIT(action_defs, init_action_defs())

/proc/init_action_defs()
	. = list()
	for(var/datum/action_def/path as anything in subtypesof(/datum/action_def))
		if(!initial(path.id))
			continue
		var/datum/action_def/def = new path
		if(.[def.id])
			stack_trace("duplicate action id [def.id] ([path])")
			continue
		.[def.id] = def

/// The definition of action `id` (an ACT_* value), or null.
/proc/action_def_of(id)
	RETURN_TYPE(/datum/action_def)
	return GLOB.action_defs[id]

// ---- bind profiles ----

/// gesture -> priority list of actions, per kind of actor. One shared singleton per profile type;
/// an actor's type picks it (bind_profile_type()).
/datum/bind_profile
	abstract_type = /datum/bind_profile

/// The table gesture -> list(ACT_*, ...), first listed wins. A proc-static list per subtype.
/datum/bind_profile/proc/table()
	return list()

/// The actions `gesture` reaches, in priority order: this profile's list, then the actions whose
/// definition binds the gesture (in definition order).
/datum/bind_profile/proc/actions_for(gesture)
	var/list/listed = table()[gesture]
	. = listed ? listed.Copy() : list()
	for(var/id in GLOB.action_defs)
		var/datum/action_def/def = GLOB.action_defs[id]
		if(gesture in def.binds)
			. |= def.id

/datum/bind_profile/default

/datum/bind_profile/default/table()
	var/static/list/binds = list(
		GESTURE_CLICK = list(ACT_USE),
		GESTURE_SELF = list(ACT_USE),
		GESTURE_ALT = list(ACT_TOGGLE, ACT_OPEN, ACT_CLOSE, ACT_LOCK, ACT_UNLOCK),
		GESTURE_CTRL = list(ACT_PULL),
		GESTURE_SHIFT = list(ACT_EXAMINE),
		GESTURE_DRAG = list(ACT_DROP_ONTO, ACT_INSERT),
		GESTURE_RIGHT = list(ACT_PRY, ACT_REPAIR, ACT_DISMANTLE),
	)
	return binds

/// Silicons work things at a distance with a click that also toggles, and lock with alt.
/datum/bind_profile/silicon

/datum/bind_profile/silicon/table()
	var/static/list/binds = list(
		GESTURE_CLICK = list(ACT_USE, ACT_TOGGLE),
		GESTURE_SELF = list(ACT_USE),
		GESTURE_ALT = list(ACT_LOCK, ACT_UNLOCK, ACT_OPEN, ACT_CLOSE),
		GESTURE_SHIFT = list(ACT_EXAMINE),
	)
	return binds

/// Observers only look.
/datum/bind_profile/observer

/datum/bind_profile/observer/table()
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/binds = list(
		GESTURE_CLICK = list(ACT_EXAMINE),
		GESTURE_ALT = list(ACT_EXAMINE),
		GESTURE_SHIFT = list(ACT_EXAMINE),
	)
	return binds

/// The profile type of a kind of mob.
/mob/proc/bind_profile_type()
	return /datum/bind_profile/default

/mob/living/silicon/bind_profile_type()
	return /datum/bind_profile/silicon

/mob/observer/bind_profile_type()
	return /datum/bind_profile/observer

/// The shared profile singleton for `path`.
/proc/bind_profile_of(mob/user)
	RETURN_TYPE(/datum/bind_profile)
	var/static/list/singletons = list()
	var/path = user ? user.bind_profile_type() : /datum/bind_profile/default
	var/datum/bind_profile/profile = singletons[path]
	if(!profile)
		profile = new path
		singletons[path] = profile
	return profile

// ---- resolution ----

/// The cap_op() entries of `target` that answer action `id`, in capability order (skip_legacy: not the
/// cap_hand / cap_tool / cap_use_on / cap_insert presets, which keep the resolver's own ordering).
/proc/action_entries(atom/target, id, skip_legacy = FALSE)
	. = list()
	for(var/datum/interaction/capability/E as anything in cap_interactions(target))
		if(E.op?.action == id && (!skip_legacy || !E.op.legacy) && E.applies_to(target))
			. += E

/// The entry to run for action `id` on target: the first that the held item selects and that
/// would run now; else the first the held item selects (so the refusal explains itself); else null.
/proc/action_entry_for(mob/user, atom/target, id, obj/item/held, route = ROUTE_PHYSICAL, skip_legacy = FALSE)
	RETURN_TYPE(/datum/interaction/capability)
	var/datum/interaction/capability/meant
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	for(var/datum/interaction/capability/E as anything in action_entries(target, id, skip_legacy))
		if(!E.is_meant(user, target, held))
			continue
		meant ||= E
		if(!E.why_not(user, target, held))
			GLOB.op_route_now = saved
			return E
	GLOB.op_route_now = saved
	return meant

/// Gesture -> actions -> the first applicable op: list(action id, entry), or null when nothing on the
/// target answers the gesture. `explicit_held`: `held` is exactly what is meant (null: nothing), not to be
/// replaced by the actor's active hand. `skip_legacy`: only the real cap_op() entries.
/proc/resolve_gesture(mob/user, atom/target, gesture, obj/item/held, route = ROUTE_PHYSICAL, explicit_held = FALSE, skip_legacy = FALSE)
	if(isnull(held) && user && !explicit_held)
		held = user.get_active_hand()
	for(var/id in bind_profile_of(user).actions_for(gesture))
		var/datum/interaction/capability/E = action_entry_for(user, target, id, held, route, skip_legacy)
		if(E)
			return list(id, E)
	return null

/// null when action `id` would run for user on target now, else why not (player-facing text).
/proc/test_action(mob/user, atom/target, id, route = ROUTE_PHYSICAL, obj/item/held)
	if(isnull(held) && user)
		held = user.get_active_hand()
	var/datum/interaction/capability/E = action_entry_for(user, target, id, held, route)
	if(!E)
		return "there is nothing to [action_def_of(id)?.name ? lowertext(action_def_of(id).name) : "do"] there"
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	. = E.why_not(user, target, held)
	GLOB.op_route_now = saved

/// Runs action `id` for user on target over `route`. TRUE when an op ran or started (a timed op
/// counts once it starts); FALSE otherwise (the user was told why).
/proc/perform_action(mob/user, atom/target, id, route = ROUTE_PHYSICAL, obj/item/held)
	if(isnull(held) && user)
		held = user.get_active_hand()
	var/datum/interaction/capability/E = action_entry_for(user, target, id, held, route)
	if(!E)
		if(user)
			to_chat(user, span_warning("There is nothing to [lowertext(action_def_of(id)?.name || "do")] there."))
		return FALSE
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	. = E.attempt(user, target, held) == INTERACTION_TRY_RAN
	GLOB.op_route_now = saved

// ---- the input router ----

/**
 * The entry point of the click router: input goes gesture -> actions -> op, and only what no op answers
 * falls back to the interaction resolver (interactions_for() / try_interaction(): INTERACT_* entries and
 * the legacy presets). The op entry that `gesture` reaches on `target` for `actor` (the first applicable
 * cap_op() of the first action the actor's bind profile lists), or null. `quality` / `no_tool` narrow it the
 * way the resolver's tool_act path narrows: an entry needing another tool quality (or any tool, with
 * no_tool) is not this click's, and so is one that would be refused now. `adapter` (default: the actor's own) is asked whether this kind of actor
 * may do it at all. No side effect: nothing runs.
 */
/proc/gesture_entry_for(mob/actor, atom/target, obj/item/held, gesture, quality, no_tool = FALSE, datum/input_adapter/adapter, explicit_held = TRUE)
	RETURN_TYPE(/datum/interaction/capability)
	if(!actor || !target || !length(caps_of(target)))
		return null
	var/list/resolved = resolve_gesture(actor, target, gesture, held, ROUTE_PHYSICAL, explicit_held, TRUE)
	if(!resolved)
		return null
	var/datum/interaction/capability/E = resolved[2]
	if(quality && E.tool != quality)
		return null
	if(no_tool && E.tool)
		return null
	adapter ||= actor.input_adapter()
	if(!adapter.allows_interaction(actor, target, E))
		return null
	// Only an op that would run now takes the click; a refused one leaves it to the resolver and the
	// legacy handlers, which say why (or do what the click always did) exactly as before.
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = ROUTE_PHYSICAL
	var/why = E.why_not(actor, target, held)
	GLOB.op_route_now = saved
	return why ? null : E

/// Runs `E` (from gesture_entry_for()) as a physical-route click. Returns INTERACTION_TRY_* like the resolver.
/proc/gesture_attempt(datum/interaction/capability/E, mob/actor, atom/target, obj/item/held)
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = ROUTE_PHYSICAL
	. = E.attempt(actor, target, held)
	GLOB.op_route_now = saved

/// The gesture a resolver action (INPUT_ACTION_USE / INPUT_ACTION_ALTERNATE, with or without a tool quality:
/// the secondary click of a tool) stands for; null for actions that are not gestures.
/proc/gesture_of_action(action, quality)
	switch(action)
		if(INPUT_ACTION_USE)
			return GESTURE_CLICK
		if(INPUT_ACTION_ALTERNATE)
			return quality ? GESTURE_RIGHT : GESTURE_ALT
	return null

/**
 * A click through the router: the op the gesture reaches, run. Returns the attempt's result
 * (INTERACTION_TRY_RAN / _BLOCKED, ...) or null when no op answers, and the caller falls back to the resolver.
 * try_interaction() asks this first, so every click path (use, alternate, tool_act) goes gesture -> op.
 */
/proc/try_gesture(mob/actor, atom/target, obj/item/held, action, quality, no_tool = FALSE, datum/input_adapter/adapter)
	var/gesture = gesture_of_action(action, quality)
	if(!gesture)
		return null
	var/datum/interaction/capability/E = gesture_entry_for(actor, target, held, gesture, quality, no_tool, adapter)
	if(!E)
		return null
	return gesture_attempt(E, actor, target, held)

/// A drag: `dragged` dropped onto `over` reaches ACT_DROP_ONTO / ACT_INSERT ops of `over` (the dragged item is
/// what is put there). TRUE when an op took it (it runs async: it may ask something), FALSE to fall back to MouseDrop_T.
/proc/try_gesture_drag(mob/actor, atom/dragged, atom/over)
	var/obj/item/item = istype(dragged, /obj/item) ? dragged : null
	var/datum/interaction/capability/E = gesture_entry_for(actor, over, item, GESTURE_DRAG)
	if(!E)
		return FALSE
	// ALLOW(scheduler): a gesture attempt runs prompts and do_afters, so it is detached from the click that started it
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(gesture_attempt), E, actor, over, item)
	return TRUE

// ---- radial and screentip data ----

/// The radial menu's data for target: one row per action something on the target answers:
/// list(id, name, icon, category, enabled, reason).
/proc/action_options(mob/user, atom/target, route = ROUTE_PHYSICAL)
	. = list()
	var/obj/item/held = user?.get_active_hand()
	var/list/seen = list()
	for(var/datum/interaction/capability/E as anything in cap_interactions(target))
		var/id = E.op?.action
		if(!id || seen[id] || !E.applies_to(target))
			continue
		var/datum/action_def/def = action_def_of(id)
		if(!def)
			continue
		seen[id] = TRUE
		var/why = test_action(user, target, id, route, held)
		. += list(list(
			"id" = def.id,
			"name" = def.name,
			"icon" = def.radial_icon,
			"category" = def.category,
			"enabled" = !why,
			"reason" = why,
		))

/// The screentip line for gesture on target ("Click: Open cover"), or null.
/proc/screentip_for(mob/user, atom/target, gesture)
	var/list/resolved = resolve_gesture(user, target, gesture)
	if(!resolved)
		return null
	var/datum/interaction/capability/E = resolved[2]
	var/label = E.display_name(user, target)
	return "[action_gesture_label(gesture)]: [label]"

/proc/action_gesture_label(gesture)
	switch(gesture)
		if(GESTURE_CLICK)
			return "Click"
		if(GESTURE_SELF)
			return "Use in hand"
		if(GESTURE_ALT)
			return "Alt-click"
		if(GESTURE_CTRL)
			return "Ctrl-click"
		if(GESTURE_SHIFT)
			return "Shift-click"
		if(GESTURE_DRAG)
			return "Drag"
		if(GESTURE_RIGHT)
			return "Right-click"
	return gesture

// ---- the UI route: act("action", {id}) ----

/// A client's act("action", {id: "lock"}) on an atom's window: runs the action over ROUTE_UI. It is a UI
/// action of the capability layer, not of every atom: every holder with a cap_op() carries op entries
/// (this capability type), and the dispatcher (ui_named_dispatch) finds act_action on the first of them.
/// Runs on the shared flyweight; `holder` is the atom whose window it is.
/datum/capability/entry/proc/act_action(mob/user, id, atom/holder)
	id = ui_choice(ui_text(id, 64), GLOB.action_defs)
	if(isnull(id))
		return refuse(user, "That isn't something you can do.")
	if(!perform_action(user, holder, id, ROUTE_UI))
		return UI_REFUSED
	return TRUE

// ---- the command bar ----

/// The "Act" verb: `act lock` on the thing next to you (or the target you name). Over ROUTE_VERB.
/mob/verb/act_on(action_id as text, atom/target as null|mob|obj|turf in view(1))
	set name = "Act"
	set category = "IC"
	set desc = "Do an action (use, open, lock, insert...) to something next to you."
	command_action(src, action_id, target)

/// Runs a typed action for user: the id is normalised (case, hyphens), the target defaults to the
/// first thing within reach that has an op for it. Returns TRUE when something ran.
/proc/command_action(mob/user, text, atom/target)
	var/id = ui_action_key(trim("[text]"))
	if(!id || !GLOB.action_defs[id])
		if(user)
			to_chat(user, span_warning("Unknown action. Try: [english_list(GLOB.action_defs, and_text = ", ")]."))
		return FALSE
	if(!target)
		for(var/atom/A in view(1, user))
			if(length(action_entries(A, id)))
				target = A
				break
	if(!target)
		to_chat(user, span_warning("There is nothing next to you to [lowertext(action_def_of(id).name)]."))
		return FALSE
	return perform_action(user, target, id, ROUTE_VERB)
