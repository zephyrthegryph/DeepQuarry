/**
 * The input router (doc/rewrite/interactions.md §4).
 *
 * Every click on the map, for every mob, comes through route_click(). The
 * router asks the mob's capability adapter whether the click is accepted
 * (cooldowns, click intercepts, buildmode), turns the click modifiers into one
 * abstract action with the adapter's click table, and hands the action to the
 * adapter. This is the only place click modifiers are read; the lint
 * "input: modifier ladders" in tools/ci/check_grep.sh enforces that.
 */
/datum/input_router

GLOBAL_DATUM_INIT(input_router, /datum/input_router, new)

/// The standard click table. Rows are checked in order; the first whose
/// modifiers are all held wins. No match means Use.
TYPE_TABLE_DECLARE(/datum/input_router, standard_click_table, list( \
		list(list(BUTTON4), INPUT_ACTION_NONE), \
		list(list(BUTTON5), INPUT_ACTION_NONE), \
		list(list(SHIFT_CLICK, MIDDLE_CLICK), INPUT_ACTION_POINT), \
		list(list(SHIFT_CLICK, CTRL_CLICK), INPUT_ACTION_QUICK), \
		list(list(SHIFT_CLICK, ALT_CLICK), INPUT_ACTION_LOOT), \
		list(list(SHIFT_CLICK), INPUT_ACTION_INSPECT), \
		list(list(MIDDLE_CLICK, CTRL_CLICK), INPUT_ACTION_TAG), \
		list(list(MIDDLE_CLICK), INPUT_ACTION_SWAP_HANDS), \
		list(list(ALT_CLICK, RIGHT_CLICK), INPUT_ACTION_ALTERNATE_SECONDARY), \
		list(list(ALT_CLICK), INPUT_ACTION_ALTERNATE), \
		list(list(CTRL_CLICK), INPUT_ACTION_PULL), \
		list(list(RIGHT_CLICK), INPUT_ACTION_RIGHT_CLICK_BINDING), \
	))

/// The screen click catcher: middle click swaps hands.
TYPE_TABLE_DECLARE(/datum/input_router, click_catcher_table, list(list(list(MIDDLE_CLICK), INPUT_ACTION_SWAP_HANDS)))

/// Shift alone means Inspect (the click catcher faces the clicked tile).
TYPE_TABLE_DECLARE(/datum/input_router, shift_table, list(list(list(SHIFT_CLICK), INPUT_ACTION_INSPECT)))

/// Alt alone means Alternate (screen buttons and consoles with an alt-click toggle).
TYPE_TABLE_DECLARE(/datum/input_router, alternate_table, list(list(list(ALT_CLICK), INPUT_ACTION_ALTERNATE)))

/// Right-click means the secondary action (screen buttons, secondary item interactions, click intercepts).
TYPE_TABLE_DECLARE(/datum/input_router, secondary_table, list(list(list(RIGHT_CLICK), INPUT_ACTION_ALTERNATE_SECONDARY)))

/// A plain left click means Use (click intercepts that ignore middle clicks).
TYPE_TABLE_DECLARE(/datum/input_router, primary_table, list(list(list(LEFT_CLICK), INPUT_ACTION_USE)))

/// Whether a click (params text or list) produces `action` with `table`. No match is no action.
/// For screen objects and click intercepts that read one action outside the adapters.
/datum/input_router/proc/click_is(params, list/table, action)
	var/list/modifiers = islist(params) ? params : params2list(params)
	return classify(modifiers, table, INPUT_ACTION_MENU, INPUT_ACTION_NONE) == action

/// Turns click modifiers into an action with a click table; `fallback` when no row matches.
/datum/input_router/proc/classify(list/modifiers, list/table, right_click_binding = INPUT_ACTION_MENU, fallback = INPUT_ACTION_USE)
	for(var/list/row as anything in table)
		var/matched = TRUE
		for(var/modifier in row[1])
			if(!modifiers[modifier])
				matched = FALSE
				break
		if(!matched)
			continue
		var/action = row[2]
		return action == INPUT_ACTION_RIGHT_CLICK_BINDING ? right_click_binding : action
	return fallback

/// The action a click with these params produces for this mob.
/datum/input_router/proc/action_for_click(mob/user, params)
	var/datum/input_adapter/adapter = user.input_adapter()
	var/list/modifiers = params2list(params)
	return classify(modifiers, TYPE_TABLE_GET(adapter, adapter_click_table), user.client ? user.client.right_click_binding() : INPUT_ACTION_MENU)

/// Entry point for every map click.
/datum/input_router/proc/route_click(mob/user, atom/target, params)
	var/datum/input_adapter/adapter = user.input_adapter()
	if(!adapter.accept_click(user, target, params))
		return
	// A click that did not come through the input inbox gets what the inbox gives a player's: the ops of the target, the held item and the actor first
	// (input_resolve_click()); what no op takes goes on to the actor's adapter, which does not resolve them again (GLOB.op_click_resolved).
	var/ops_tried = GLOB.op_click_resolved[user]
	if(!ops_tried)
		var/gesture = op_gesture_of_params(params)
		var/obj/held = user.held_for_ops()
		if(!isnull(gesture) && target && (op_has_ops(target) || op_has_ops(held) || op_has_click_ops(user)))
			var/datum/op_result/result = op_resolve_click_with_params(user, target, held, gesture, ORIGIN_CLICK, params, TRUE, TRUE)
			if(result)
				return TRUE
		GLOB.op_click_resolved[user] = TRUE
	var/list/modifiers = params2list(params)
	var/action = classify(modifiers, TYPE_TABLE_GET(adapter, adapter_click_table), user.client ? user.client.right_click_binding() : INPUT_ACTION_MENU)
	. = adapter.perform(user, target, action, modifiers, params)
	if(!ops_tried)
		GLOB.op_click_resolved -= user

/// Entry point for drag and drop: the Drag action.
/datum/input_router/proc/route_drag(mob/user, atom/dragged, atom/over, src_location, over_location, src_control, over_control, params)
	if(!user || !over)
		return
	var/datum/input_adapter/adapter = user.input_adapter()
	return adapter.drag(user, dragged, over, src_location, over_location, src_control, over_control, params)

/// Entry point for interaction-category keys.
/datum/input_router/proc/route_category(mob/user, atom/target, category)
	var/datum/input_adapter/adapter = user.input_adapter()
	log_input("Input: [key_name(user)] pressed the [category] key on [target] ([target.type]).")
	return adapter.perform_category(user, target, category)

/atom/Click(location, control, params) // This is their reaction to being clicked on (standard proc)
	if(src)
		// The input inbox (code/engine/kernel/inbox.dm): the click resolves on the spot while the tick has room, and
		// otherwise waits for phase K's drain, in arrival order, behind the clicker's own earlier inputs.
		input_submit(new /datum/input_event/click(usr, src, location, control, params)) // ALLOW(sys_usr_outside_verb): atom/Click is BYOND's entry point: usr is the clicking mob here

/atom/DblClick(location, control, params)
	if(src)
		usr.DblClickOn(src, params)

/atom/MouseWheel(delta_x,delta_y,location,control,params)
	if(src)
		usr.MouseWheelOn(src, delta_x, delta_y, params)

/atom/MouseDrop(atom/over, src_location, over_location, src_control, over_control, params)
	GLOB.input_router.route_drag(usr, src, over, src_location, over_location, src_control, over_control, params)

/// A mob's click. Subtypes that must see a click before routing (pAI card
/// machines, the folded protean) override this and call ..().
/mob/proc/ClickOn(atom/A, params)
	return GLOB.input_router.route_click(src, A, params)
