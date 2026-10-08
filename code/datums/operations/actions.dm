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

/// The hostile use. No gesture binds it by itself: the bind profile's stance table puts it ahead of ACT_USE for a click in
/// a hostile stance (harm, disarm), so a help-stance click never reaches an attack.
/datum/action_def/attack
	id = ACT_ATTACK
	name = "Attack"
	radial_icon = "hand-fist"
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

/**
 * The stance modifier: stance (I_HELP, I_DISARM, I_GRAB, I_HURT) -> (gesture -> list(ACT_*, ...)). A gesture the
 * actor's stance lists here uses that list in place of table()'s: a click in harm is ACT_ATTACK before ACT_USE, a click
 * in help is only ACT_USE, so an attack op is reached by stance and never by a help click. A proc-static list per subtype.
 */
/datum/bind_profile/proc/stance_table()
	return list()

/// The actions `gesture` in `stance` reaches, in priority order: the stance's list for the gesture (stance_table()), else
/// this profile's list (table()), then the actions whose definition binds the gesture (in definition order).
/datum/bind_profile/proc/actions_for(gesture, stance)
	var/list/listed
	if(stance)
		var/list/by_stance = stance_table()[stance]
		listed = by_stance?[gesture]
	listed ||= table()[gesture]
	. = listed ? listed.Copy() : list()
	for(var/id in GLOB.action_defs)
		var/datum/action_def/def = GLOB.action_defs[id]
		if(gesture in def.binds)
			. |= def.id

/datum/bind_profile/default

/datum/bind_profile/default/table()
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/binds = list(
		GESTURE_CLICK = list(ACT_USE, ACT_LOCK), // a click holding a card the lock takes is a swipe (an op's click_with)
		GESTURE_SELF = list(ACT_USE),
		GESTURE_ALT = list(ACT_TOGGLE, ACT_OPEN, ACT_CLOSE, ACT_LOCK, ACT_UNLOCK, ACT_EJECT),
		GESTURE_CTRL = list(ACT_PULL),
		GESTURE_SHIFT = list(ACT_EXAMINE),
		GESTURE_DRAG = list(ACT_DROP_ONTO, ACT_INSERT),
		GESTURE_RIGHT = list(ACT_PRY, ACT_REPAIR, ACT_DISMANTLE),
	)
	return binds

/// Harm and disarm are the hostile stances (STANCE_IS_HOSTILE): their click tries the attack ops first and falls back to
/// the ordinary use (a door still opens in combat mode). Help and grab keep the plain click; a grab-only op narrows
/// itself with cap_op(stance = I_GRAB).
/datum/bind_profile/default/stance_table()
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/binds = list(
		I_HURT = list(GESTURE_CLICK = list(ACT_ATTACK, ACT_USE, ACT_LOCK)),
		I_DISARM = list(GESTURE_CLICK = list(ACT_ATTACK, ACT_USE, ACT_LOCK)),
	)
	return binds

/// Silicons work things at a distance with a click that also toggles, and lock with alt.
/datum/bind_profile/silicon

/datum/bind_profile/silicon/table()
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/binds = list(
		GESTURE_CLICK = list(ACT_USE, ACT_TOGGLE),
		GESTURE_SELF = list(ACT_USE),
		GESTURE_ALT = list(ACT_LOCK, ACT_UNLOCK, ACT_OPEN, ACT_CLOSE, ACT_EJECT),
		GESTURE_SHIFT = list(ACT_EXAMINE),
	)
	return binds

/// A cyborg in combat mode swings what its module holds before it works the target.
/datum/bind_profile/silicon/stance_table()
	// ALLOW(sys_static_getter): a memoized per-type table built once on first call
	var/static/list/binds = list(
		I_HURT = list(GESTURE_CLICK = list(ACT_ATTACK, ACT_USE, ACT_TOGGLE)),
		I_DISARM = list(GESTURE_CLICK = list(ACT_ATTACK, ACT_USE, ACT_TOGGLE)),
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
//
// A gesture reaches one op in a fixed order (doc/rewrite/operations_and_actions.md §5):
//	1. the actor's bind profile: the actions the gesture reaches in the actor's stance, in the listed order;
//	2. within one action, the op priority (cap_op(priority =), higher first);
//	3. then the declaration order (capabilities() order).
// Within that order the first op that is meant and would run now answers; when none would run, the first meant one
// answers with its refusal. What the gesture does not reach stays in the Menu, the radial and the command bar, where an
// op is named by its key or name (ACT_NONE ops are reached only there).

/// Every capabilities() list -> its op index (action id -> op entries, best first). Per type: the list is per type.
GLOBAL_LIST_EMPTY(op_action_indexes)

/// action id -> the op entries of A's type answering it, sorted by op priority (higher first); equal priorities keep the
/// declaration order. Built once per capabilities() list and shared.
/proc/op_action_index(atom/A)
	var/list/caps = caps_of(A)
	var/list/index = GLOB.op_action_indexes[caps]
	if(index)
		return index
	index = list()
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		var/datum/op_def/op = E.op
		if(!op)
			continue
		var/list/entries = index[op.action]
		if(!entries)
			entries = list()
			index[op.action] = entries
		var/position = length(entries) + 1
		for(var/i in 1 to length(entries))
			var/datum/interaction/capability/other = entries[i]
			if(op.priority > other.op.priority)
				position = i
				break
		entries.Insert(position, E)
	GLOB.op_action_indexes[caps] = index
	return index

/// The op entries of `target` that answer action `id`, best first (op priority, then declaration order). skip_legacy:
/// not the cap_hand / cap_tool / cap_use_on / cap_insert presets, which keep the resolver's own ordering.
/proc/action_entries(atom/target, id, skip_legacy = FALSE)
	. = list()
	for(var/datum/interaction/capability/E as anything in op_action_index(target)[id])
		if((!skip_legacy || !E.op.legacy) && E.applies_to(target))
			. += E

/**
 * The entry to run for action `id` on target: in action_entries() order, the first that the held item selects and that
 * would run now; else the first the held item selects (so the refusal explains itself); else null.
 * The narrowing a click brings: `quality` (only ops of that tool quality) and `no_tool` (only ops needing no tool) as the
 * resolver's tool_act path narrows; `routed`: an op that does not accept `route` at all is not a candidate (a hand-only op
 * under a silicon's interface click); `adapter`: an op this kind of actor may never do is not a candidate.
 */
/proc/action_entry_for(mob/user, atom/target, id, obj/item/held, route = ROUTE_PHYSICAL, skip_legacy = FALSE, quality, no_tool = FALSE, routed = FALSE, datum/input_adapter/adapter)
	RETURN_TYPE(/datum/interaction/capability)
	var/datum/interaction/capability/meant
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	for(var/datum/interaction/capability/E as anything in action_entries(target, id, skip_legacy))
		if(quality && E.tool != quality)
			continue
		if(no_tool && E.tool)
			continue
		if(routed && !(E.op.via & route))
			continue
		if(adapter && !adapter.allows_interaction(user, target, E))
			continue
		if(!E.is_meant(user, target, held))
			continue
		meant ||= E
		if(!E.why_not(user, target, held))
			GLOB.op_route_now = saved
			return E
	GLOB.op_route_now = saved
	return meant

/**
 * Gesture -> actions -> the first applicable op: list(action id, entry), or null when nothing on the target answers the
 * gesture. The actions are the actor's bind profile's for the gesture in the actor's stance (input_stance(): the stance is
 * a gesture modifier, so a harm click reaches ACT_ATTACK first). `explicit_held`: `held` is exactly what is meant (null:
 * nothing), not to be replaced by the actor's active hand. `skip_legacy`: only the real ops. `quality`, `no_tool`,
 * `routed` and `adapter` narrow as action_entry_for() says.
 */
/proc/resolve_gesture(mob/user, atom/target, gesture, obj/item/held, route = ROUTE_PHYSICAL, explicit_held = FALSE, skip_legacy = FALSE, quality, no_tool = FALSE, routed = FALSE, datum/input_adapter/adapter)
	if(isnull(held) && user && !explicit_held)
		held = user.get_active_hand()
	var/saved_gesture = GLOB.op_gesture_now
	GLOB.op_gesture_now = gesture
	var/stance = ismob(user) ? user.input_stance() : null
	for(var/id in bind_profile_of(user).actions_for(gesture, stance))
		var/datum/interaction/capability/E = action_entry_for(user, target, id, held, route, skip_legacy, quality, no_tool, routed, adapter)
		if(E)
			GLOB.op_gesture_now = saved_gesture
			return list(id, E)
	GLOB.op_gesture_now = saved_gesture
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
	return op_entry_attempt(E, user, target, held, route)

/// Runs op entry E for user on target over `route`. TRUE when it ran or started.
/proc/op_entry_attempt(datum/interaction/capability/E, mob/user, atom/target, obj/item/held, route = ROUTE_PHYSICAL)
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	. = E.attempt(user, target, held) == INTERACTION_TRY_RAN
	GLOB.op_route_now = saved

// ---- ops by key or name: the Menu, the radial and the command bar ----

/// The op entry of `target` that `text` names: its key (any case, hyphens or spaces for underscores) or its name or
/// current display name (any case). Null when none applies. How an op with no gesture (ACT_NONE) is reached.
/proc/op_entry_named(mob/user, atom/target, text)
	RETURN_TYPE(/datum/interaction/capability)
	if(!target || !istext(text))
		return null
	var/wanted = lowertext(trim(text))
	if(!length(wanted))
		return null
	var/wanted_key = replacetext(replacetext(wanted, " ", "_"), "-", "_")
	for(var/datum/interaction/capability/E as anything in cap_interactions(target))
		var/datum/op_def/op = E.op
		if(!op || !E.applies_to(target))
			continue
		if(lowertext(op.key) == wanted_key || lowertext("[op.name]") == wanted || lowertext("[E.display_name(user, target)]") == wanted)
			return E
	return null

/// null when the op `text` names would run for user on target over `route` now, else why not (player-facing text).
/proc/test_op(mob/user, atom/target, text, route = ROUTE_PHYSICAL, obj/item/held)
	if(isnull(held) && user)
		held = user.get_active_hand()
	var/datum/interaction/capability/E = op_entry_named(user, target, text)
	if(!E)
		return "there is no such thing to do there"
	var/saved = GLOB.op_route_now
	GLOB.op_route_now = route
	. = E.why_not(user, target, held)
	GLOB.op_route_now = saved

/// Runs the op `text` names (its key or name) for user on target over `route`, whatever action it answers: the Menu, the
/// radial and the command bar reach every op this way, and an ACT_NONE op only this way. TRUE when it ran or started.
/proc/legacy_perform_op(mob/user, atom/target, text, route = ROUTE_PHYSICAL, obj/item/held)
	if(isnull(held) && user)
		held = user.get_active_hand()
	var/datum/interaction/capability/E = op_entry_named(user, target, text)
	if(!E)
		if(user)
			to_chat(user, span_warning("There is no such thing to do there."))
		return FALSE
	return op_entry_attempt(E, user, target, held, route)

// ---- the input router ----

/**
 * The entry point of the click router: input goes gesture -> actions -> op, and only what no op answers
 * falls back to the interaction resolver (interactions_for() / try_interaction(): INTERACT_* entries and
 * the legacy presets). The op entry that `gesture` reaches on `target` for `actor` (resolve_gesture(): the actor's bind
 * profile in its stance, then op priority, then declaration order), or null. `quality` / `no_tool` narrow it the
 * way the resolver's tool_act path narrows: an entry needing another tool quality (or any tool, with
 * no_tool) is not this click's. An op that would be refused now still is: its refusal is what the player sees.
 * `adapter` (default: the actor's own) says how this kind of actor reaches (its route: the telekinesis adapter's is
 * ROUTE_TK) and whether it may do an op at all. No side effect: nothing runs.
 */
/proc/gesture_entry_for(mob/actor, atom/target, obj/item/held, gesture, quality, no_tool = FALSE, datum/input_adapter/adapter, explicit_held = TRUE)
	RETURN_TYPE(/datum/interaction/capability)
	if(!actor || !target || !length(caps_of(target)))
		return null
	adapter ||= actor.input_adapter()
	var/route = adapter.op_route(actor, held)
	// routed: a click is not a request for an op that cannot travel its route at all (a hand-only op under a silicon's
	// interface click); such an op is passed over and, when nothing else answers, the click falls through to the resolver.
	var/list/resolved = resolve_gesture(actor, target, gesture, held, route, explicit_held, TRUE, quality, no_tool, TRUE, adapter)
	if(!resolved)
		return null
	// The op takes the click whether or not it would run now: a refusal is the op's answer (gesture_attempt() tells
	// the actor the typed reason from the fixed stage order), never a cue to hand the click to the legacy resolver.
	return resolved[2]

/// Runs `E` (from gesture_entry_for()) as a click over `route` (default: the actor's adapter's, input_adapter/op_route()).
/// Returns INTERACTION_TRY_* like the resolver: INTERACTION_TRY_BLOCKED after telling the actor why when a requirement
/// refuses it.
/proc/gesture_attempt(datum/interaction/capability/E, mob/actor, atom/target, obj/item/held, route)
	var/saved = GLOB.op_route_now
	if(isnull(route))
		var/datum/input_adapter/adapter = actor?.input_adapter()
		route = adapter ? adapter.op_route(actor, held) : ROUTE_PHYSICAL
	GLOB.op_route_now = route
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
	if(!gesture || !actor)
		return null
	adapter ||= actor.input_adapter()
	var/datum/interaction/capability/E = gesture_entry_for(actor, target, held, gesture, quality, no_tool, adapter)
	if(!E)
		return null
	return gesture_attempt(E, actor, target, held, adapter.op_route(actor, held))

/// A drag: `dragged` dropped onto `over` reaches ACT_DROP_ONTO / ACT_INSERT ops of `over` (the dragged item is
/// what is put there). TRUE when an op took it (it runs async: it may ask something), FALSE to fall back to MouseDrop_T.
/proc/try_gesture_drag(mob/actor, atom/dragged, atom/over)
	var/obj/item/item = istype(dragged, /obj/item) ? dragged : null
	var/datum/interaction/capability/E = gesture_entry_for(actor, over, item, GESTURE_DRAG)
	if(!E)
		return FALSE
	var/datum/input_adapter/adapter = actor.input_adapter()
	// ALLOW(scheduler): a gesture attempt runs prompts and do_afters, so it is detached from the click that started it
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(gesture_attempt), E, actor, over, item, adapter.op_route(actor, item))
	return TRUE

// ---- radial and screentip data ----

/**
 * The radial menu's data for target: one row per op on it (an op is named by its key, never by its action: two ops that
 * both answer ACT_USE are two rows), in the gesture resolution order (action, op priority, declaration):
 * list(id = op key, name = its display name, action = the ACT_* it answers (ACT_NONE: no gesture reaches it), icon,
 * category, enabled, reason).
 */
/proc/legacy_action_options(mob/user, atom/target, route = ROUTE_PHYSICAL, operations_only = FALSE)
	. = list()
	var/obj/item/held = user?.get_active_hand()
	var/list/seen = list()
	for(var/datum/interaction/capability/E as anything in cap_interactions(target))
		var/datum/op_def/op = E.op
		if(!op || (operations_only && op.legacy) || seen[op.key] || !E.applies_to(target))
			continue
		seen[op.key] = TRUE
		var/datum/action_def/def = action_def_of(op.action)
		var/saved = GLOB.op_route_now
		GLOB.op_route_now = route
		var/why = E.why_not(user, target, held)
		GLOB.op_route_now = saved
		. += list(list(
			"id" = op.key,
			"name" = E.display_name(user, target),
			"action" = op.action,
			"icon" = def ? def.radial_icon : "ellipsis",
			"category" = def ? def.category : ACT_CAT_USE,
			"enabled" = !why,
			"reason" = why,
		))

/proc/legacy_screentip_for(mob/user, atom/target, gesture)
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

/// A client's act("action", {id}) on an atom's window, over ROUTE_UI: `id` is an action (ACT_*: "lock" runs the op the
/// action reaches) or an op's key or name ("remove_power_cell": that op, whatever its action; ACT_NONE ops only so). It
/// is a UI action of the capability layer, not of every atom: every holder with a cap_op() carries op entries (this
/// capability type), and the dispatcher (ui_named_dispatch) finds act_action on the first of them. Runs on the shared
/// flyweight; `holder` is the atom whose window it is.
/datum/capability/entry/proc/act_action(mob/user, id, atom/holder)
	var/text = ui_text(id, 64)
	var/action = ui_choice(text, GLOB.action_defs)
	if(!isnull(action))
		return perform_action(user, holder, action, ROUTE_UI) ? TRUE : UI_REFUSED
	if(!isnull(text) && op_entry_named(user, holder, text))
		return legacy_perform_op(user, holder, text, ROUTE_UI) ? TRUE : UI_REFUSED
	return refuse(user, "That isn't something you can do.")

// ---- the command bar ----

/// The "Act" verb: `act lock` or `act remove power cell` on the thing next to you (or the target you name). Over ROUTE_VERB.
/mob/verb/act_on(action_id as text, atom/target as null|mob|obj|turf in view(1))
	set name = "Act"
	set category = VERB_CAT_IC
	set desc = "Do an action (use, open, lock, insert...) or a named operation to something next to you."
	command_action(src, action_id, target)

/// Runs a typed action or op for user. An action id (normalised: case, hyphens) runs the op the action reaches; anything
/// else names an op by its key or name (op_entry_named()). The target defaults to the first thing within reach that
/// answers it. Returns TRUE when something ran.
/proc/command_action(mob/user, text, atom/target)
	var/id = ui_action_key(trim("[text]"))
	if(id && GLOB.action_defs[id])
		if(!target)
			for(var/atom/A in view(1, user))
				if(length(action_entries(A, id)))
					target = A
					break
		if(!target)
			to_chat(user, span_warning("There is nothing next to you to [lowertext(action_def_of(id).name)]."))
			return FALSE
		return perform_action(user, target, id, ROUTE_VERB)
	if(!target && user)
		for(var/atom/A in view(1, user))
			if(op_entry_named(user, A, "[text]"))
				target = A
				break
	var/datum/interaction/capability/E = target ? op_entry_named(user, target, "[text]") : null
	if(E)
		return legacy_perform_op(user, target, "[text]", op_command_route(user, E))
	if(user)
		to_chat(user, span_warning("Unknown action. Try: [english_list(GLOB.action_defs, and_text = ", ")], or the name of something to do."))
	return FALSE

/// The route the command bar runs op E over for user: ROUTE_VERB when the op takes it, else the actor's own route (typing
/// "act remove power cell" at the thing next to you is your hand on it, as an object verb in view(1) was).
/proc/op_command_route(mob/user, datum/interaction/capability/E)
	if(E.op.via & ROUTE_VERB)
		return ROUTE_VERB
	return user ? user.op_route(user.get_active_hand()) : ROUTE_PHYSICAL

/// The route a click of this mob travels (ROUTE_*): hands on the target, by default.
/mob/proc/op_route(obj/item/held)
	return ROUTE_PHYSICAL

/// A silicon's empty-handed click works the target's interface (an AI at range, a cyborg's touch); what a cyborg
/// holds in a module is used on it physically.
/mob/living/silicon/op_route(obj/item/held)
	return held ? ROUTE_PHYSICAL : ROUTE_INTERFACE

/// An observer never touches: what it reaches it reaches through a window (a ghost's click opens a UI to view). Its bind
/// profile lists only ACT_EXAMINE, so its click reaches only an op that answers ACT_EXAMINE over ROUTE_UI.
/mob/observer/dead/op_route(obj/item/held)
	return ROUTE_UI

/// The route this kind of actor's click travels: the actor's own (mob/op_route()), except where the adapter reaches
/// another way (the telekinesis adapter: ROUTE_TK).
/datum/input_adapter/proc/op_route(mob/actor, obj/item/held)
	return actor ? actor.op_route(held) : ROUTE_PHYSICAL

/// A telekinetic click reaches over ROUTE_TK: the telekinesis affordance is its provider (op_ctx stage_provider()).
/datum/input_adapter/telekinesis/op_route(mob/actor, obj/item/held)
	return ROUTE_TK
