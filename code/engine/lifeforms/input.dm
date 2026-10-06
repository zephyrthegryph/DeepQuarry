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
// The client's native hooks (Click(), MouseDrop(), MouseDrag(), MouseEntered(), MouseExited()) are the only places BYOND hands DM the acting mob, as `usr`.
// For a type that declares one of these entries, analyze gen declare writes the native override into code/engine/_generated/declare.dm: it
// reads usr there, once, and calls the engine with the actor as an argument. Content never reads usr: the handler gets the actor in its
// context (A.actor), and an op key runs through perform_op() with it, so requirements, reach and logging apply as for any input.
//
// tooltip(PROC_REF(x)): x(mob/user) answers list(title, content) or the content alone (the holder's name is the title); the tooltip opens on
// enter and closes on exit (openToolTip(), closeToolTip()). `theme =` picks a tooltip theme.
//
// with_actor(actor, CALLBACK(...)) runs a callback with `actor` as the acting mob for the code below it that still reads usr: BYOND's own
// procs (input(), alert(), browse() through them) and legacy procs not yet converted. It is the engine's one writer of usr.

/proc/click_on(handler)
	return entry_make(ENTRY_INPUT, "input:[INPUT_CLICK_ON]", list("input" = INPUT_CLICK_ON, "handler" = handler))

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
	/// The input kind (INPUT_CLICK_ON, INPUT_DRAG_ONTO, INPUT_HOVER).
	var/input
	/// The client's params text (modifier keys, screen location).
	var/params
	/// A drag's destination.
	var/atom/over
	/// A hover: TRUE on enter, FALSE on exit.
	var/entered = FALSE
	/// The native hook's own arguments by name (location, control, src_location, over_location, src_control, over_control, params).
	var/list/native

/// The input that fell through to the native parent right now (INPUT_FALLTHROUGH): list(holder, input). A parent type's generated override
/// that the fall reaches must not run the same (inherited or replaced) entry a second time; input_fell() clears it when the native chain returns.
GLOBAL_REAL_VAR(list/input_falling)

/// Runs the holder's handler for one input with `actor`: a holder proc gets the context; an op key runs through perform_op(). Returns TRUE
/// when a handler took the input.
/proc/input_dispatch(atom/holder, mob/actor, input, params = null, atom/over = null, entered = FALSE, list/native = null)
	if(!holder || QDELETED(holder))
		return FALSE
	if(input_falling && input_falling[1] == holder && input_falling[2] == input)
		return FALSE // a subtype's generated override already ran this holder's entry and fell through to its parent
	var/datum/type_table/T = type_table_cache()[holder.type] || table_of(holder)
	if(!(T.hook_flags & ENGINE_HOOK_LIFEFORMS))
		return FALSE
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
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
			if(reply == INPUT_FALLTHROUGH) // the native override goes on to ..(): a parent's generated override must not run it again
				input_falling = list(holder, input)
				return FALSE
			return TRUE
		if(istext(handler))
			perform_op(actor, holder, handler, null, ORIGIN_CLICK)
			return TRUE
	return .

/// The native chain of a generated override returned: the fall-through mark of `holder` is over.
/proc/input_fell(atom/holder)
	if(input_falling && input_falling[1] == holder)
		input_falling = null

/// The tooltip of `holder` for `user`: opened on enter, closed on exit.
/proc/input_tooltip(atom/holder, mob/user, entered, params)
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	var/datum/centry/C = P.tooltip
	if(!C || !user)
		return FALSE
	if(!entered)
		closeToolTip(user, holder)
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
	openToolTip(user, holder, params, title = title, content = content, theme = theme || "")
	return TRUE

/// Runs `callback` with `actor` as the acting mob (usr) for the procs below it that still read it; restores the previous one. Returns the
/// callback's result.
/proc/with_actor(mob/actor, datum/callback/callback, ...)
	var/mob/previous = usr
	usr = actor
	try
		if(istype(callback))
			. = length(args) > 2 ? callback.Invoke(arglist(args.Copy(3))) : callback.Invoke()
		else // with_actor(actor, target, proc_ref, args...): the same without a callback datum (GLOBAL_PROC as the target for a global proc)
			var/target = callback
			var/proc_ref = args[3]
			var/list/rest = args.Copy(4)
			. = target == GLOBAL_PROC ? call(proc_ref)(arglist(rest)) : call(target, proc_ref)(arglist(rest))
	catch(var/exception/e)
		usr = previous
		throw e
	usr = previous

/// The acting mob of the native input running now (usr), for the engine's own entry points. Content gets its actor as an argument.
/proc/input_actor()
	return usr
