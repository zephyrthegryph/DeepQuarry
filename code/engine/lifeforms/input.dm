// Input with an actor (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 9): click_on(), drag_onto(), drag_over(), hover(),
// tooltip() and with_actor().
//
//	CAPABILITIES(/atom/movable/screen/alert)
//		tooltip(PROC_REF(alert_tooltip))                        // MouseEntered/MouseExited open and close it for the hovering mob
//		click_on(PROC_REF(alert_clicked))                       // x(datum/act/input/A): A.actor is the clicking mob
//	CAPABILITIES(/obj/machinery/feeder)
//		drag_onto("feeder.attach", onto = /mob/living/carbon)   // an op key: the drop performs it with the dragging mob as its actor
//	CAPABILITIES(/atom/movable/screen/radial/slice)
//		hover(PROC_REF(slice_hovered))                          // x(A) on enter and exit: A.entered
//
//	with_actor(user, CALLBACK(target, TYPE_PROC_REF(/datum, vv_edit_var), name, value))   // admin and callback code: runs it as `user`
//
// There is one input path. BYOND's native mouse callbacks are overridden in one place, code/engine/kernel/entry.dm: each reads `usr` once, builds a typed
// /datum/input_event with the actor in it and hands it to input_submit(). When the event resolves (on the spot, or later from the inbox, the same code)
// input_dispatch() looks up the target type's declared entry for the input in the type tables, runs the first that takes it, and otherwise the input
// goes on to its default handling (the click router, the drop's ops, the mob's hover tracking). No type overrides a native mouse proc
// (the `mouse_override` lint rejects it). Content never reads usr: the handler gets the actor in its context (A.actor), and an op key runs through
// perform_op() with it, so requirements, reach and logging apply as for any input.
//
// tooltip(PROC_REF(x)): x(mob/user) answers list(title, content) or the content alone (the holder's name is the title); the tooltip opens on
// enter and closes on exit (openToolTip(), closeToolTip()). `theme =` picks a tooltip theme.
//
// with_actor(actor, CALLBACK(...)) runs a callback with `actor` as the acting mob for the code below it that still reads usr: BYOND's own
// procs (input(), alert(), browse() through them) and legacy procs not yet converted. It is the engine's one writer of usr.

/proc/click_on(handler)
	return entry_make(ENTRY_INPUT, "input:[INPUT_CLICK_ON]", list("input" = INPUT_CLICK_ON, "handler" = handler))

/// double_click_on(PROC_REF(x)): x(datum/act/input/A) on the native DblClick of the holder.
/proc/double_click_on(handler)
	return entry_make(ENTRY_INPUT, "input:[INPUT_DOUBLE_CLICK]", list("input" = INPUT_DOUBLE_CLICK, "handler" = handler))

/proc/drag_onto(handler, onto = null)
	return entry_make(ENTRY_INPUT, "input:[INPUT_DRAG_ONTO]", list("input" = INPUT_DRAG_ONTO, "handler" = handler, "onto" = onto))

/// drag_over(PROC_REF(x)): x(A) on each native MouseDrag while the holder is being dragged (A.over is what it is over now), before the native
/// drag goes on. For hover feedback during a drag; the drop itself is drag_onto().
/proc/drag_over(handler)
	return entry_make(ENTRY_INPUT, "input:[INPUT_DRAG_OVER]", list("input" = INPUT_DRAG_OVER, "handler" = handler))

/proc/hover(handler)
	return entry_make(ENTRY_INPUT, "input:[INPUT_HOVER]", list("input" = INPUT_HOVER, "handler" = handler))

/proc/tooltip(handler, theme = null)
	return entry_make(ENTRY_TOOLTIP, "tooltip", list("handler" = handler, "theme" = theme))

/// The context an input handler gets: the holder, the acting mob, and what the input carried.
/datum/act/input
	parent_type = /datum/act/action
	/// The input kind (INPUT_CLICK_ON, INPUT_DOUBLE_CLICK, INPUT_DRAG_ONTO, INPUT_DRAG_OVER, INPUT_HOVER).
	var/input
	/// The client's params text (modifier keys, screen location).
	var/params
	/// A drag's destination.
	var/atom/over
	/// A hover: TRUE on enter, FALSE on exit.
	var/entered = FALSE
	/// The native hook's own arguments by name (location, control, src_location, over_location, src_control, over_control, params).
	var/list/native

/// The lifeform plan of `holder`'s type (the declared inputs and the tooltip), or null for a type that declares nothing the engine runs.
/proc/input_plan_of(atom/holder)
	var/datum/type_table/T = type_table_cache()[holder.type] || table_of(holder)
	if(!(T.hook_flags & ENGINE_HOOK_LIFEFORMS))
		return null
	return lifeform_plan_of(holder)

/// The resolver's lookup (every input event runs it when it resolves, whether it was resolved on arrival or waited in the inbox): the holder's
/// declared entry for `input`, run with `actor`. A holder proc gets the context; an op key runs through perform_op(). Returns TRUE when a handler took
/// the input; FALSE when the holder declares none, none accepts, or the handler answered INPUT_FALLTHROUGH, and the caller goes on to the default handling.
/proc/input_dispatch(atom/holder, mob/actor, input, params = null, atom/over = null, entered = FALSE, list/native = null)
	if(!holder || QDELETED(holder))
		return FALSE
	var/datum/lifeform_plan/P = input_plan_of(holder)
	if(!P)
		return FALSE
	. = FALSE
	for(var/datum/centry/C as anything in P.inputs)
		var/datum/entry/E = C.item
		if(E.args["input"] != input)
			continue
		if(input == INPUT_DRAG_ONTO && E.args["onto"] && !istype(over, E.args["onto"]))
			continue
		var/handler = E.args["handler"]
		if(istext(handler) && hascall(holder, handler))
			var/datum/act/input/A = take(/datum/act/input)
			A.holder = holder // ALLOW(ownership): a one-input context, dropped when the handler returns
			A.actor = actor
			A.target = holder
			A.input = input
			A.params = params
			A.over = over // ALLOW(ownership): a one-input context, dropped when the handler returns
			A.entered = entered
			A.native = native
			A.origin = ORIGIN_CLICK
			var/reply = call(holder, handler)(A)
			A.release()
			return reply != INPUT_FALLTHROUGH
		if(istext(handler))
			perform_op(actor, holder, handler, null, ORIGIN_CLICK)
			return TRUE
	return .

/// The tooltip of `holder` for `user`: opened on enter, closed on exit.
/proc/input_tooltip(atom/holder, mob/user, entered, params)
	var/datum/lifeform_plan/P = input_plan_of(holder)
	var/datum/centry/C = P?.tooltip
	if(!C || !user)
		return FALSE
	if(!entered)
		user.close_declared_tooltip(holder)
		return TRUE
	var/datum/entry/E = C.item
	var/answer = call(holder, E.args["handler"])(user)
	if(isnull(answer))
		return TRUE
	var/title = holder.name
	var/content = answer
	if(islist(answer))
		var/list/pair = answer
		title = pair[1]
		content = length(pair) > 1 ? pair[2] : ""
	var/theme = E.args["theme"]
	if(istext(theme) && (theme in holder.vars))
		theme = holder.vars[theme] // tooltip(theme = nameof(var)): the holder's own style
	user.open_declared_tooltip(holder, params, title, content, theme || "")
	return TRUE

/// Runs `callback` with `actor` as the acting mob (usr) for the procs below it that still read it; restores the previous one. Returns the
/// callback's result.
/proc/with_actor(mob/actor, datum/actor_callback/callback, ...)
	var/mob/previous = usr
	usr = actor
	try
		if(istype(callback))
			. = length(args) > 2 ? callback.invoke_actor(arglist(args.Copy(3))) : callback.invoke_actor()
		else // with_actor(actor, target, proc_ref, args...): the same without a callback datum (GLOBAL_PROC as the target for a global proc)
			var/target = callback
			var/proc_ref = args[3]
			var/list/rest = args.Copy(4)
			. = target == GLOBAL_PROC ? call(proc_ref)(arglist(rest)) : call(target, proc_ref)(arglist(rest))
	catch(var/exception/e)
		usr = previous
		throw e
	usr = previous

/// Does this atom declare a tooltip or a hover entry (so a press on it closes one)?
/proc/input_declares_tooltip(atom/holder)
	var/datum/lifeform_plan/P = input_plan_of(holder)
	if(!P)
		return FALSE
	if(P.tooltip)
		return TRUE
	for(var/datum/centry/C as anything in P.inputs)
		var/datum/entry/E = C.item
		if(E.args["input"] == INPUT_HOVER)
			return TRUE
	return FALSE

/// The acting mob of the native input running now (usr), for the engine's own entry points. Content gets its actor as an argument.
/proc/input_actor()
	return usr

/// A compatibility callback has an engine-level invocation interface.
/datum/actor_callback

/datum/actor_callback/proc/invoke_actor(...)
	return

/mob/proc/close_declared_tooltip(atom/holder)
	return

/mob/proc/open_declared_tooltip(atom/holder, params, title, content, theme)
	return
