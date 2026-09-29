// UI actions as named procs (doc/rewrite/dx_conventions.md §5).
//
//	/obj/machinery/atmospherics/binary/pump/proc/ui_set_pressure(mob/user, pressure)
//		pressure = ui_number(pressure, 0, MAX_PUMP_PRESSURE)
//		if(isnull(pressure))
//			return refuse(user, "That isn't a pressure.")
//		set_target_pressure(pressure)
//
// tgui_act() finds `ui_<action>` on the host and calls it as
// call(src, proc)(arglist(list("user" = user) + params)). An argument name the proc doesn't declare
// is a runtime, caught by dispatch_call(), logged and refused. Types are not enforced by DM: the
// body validates with ui_number/ui_text/ui_choice/ui_ref. ui_allowed() is the type-wide gate, and
// ui_logged() says which actions are logged. tools/ci/ui_actions_lint.py checks that every TSX
// act() names an existing ui_ proc with matching argument names.

/// The type-wide gate for every ui_<action>: FALSE refuses silently.
/datum/proc/ui_allowed(mob/user, action)
	return TRUE

/// Per-type list: action -> LOG_GAME / LOG_ADMIN, for the actions the dispatcher logs.
/datum/proc/ui_logged()
	return list()

/// Runs `ui_<action>` if the host has one. Returns list(handled, result).
/proc/ui_named_dispatch(datum/host, action, list/params, datum/tgui/ui)
	// Only [a-z0-9_]+ action names reach a proc lookup: a client can't name ui_ procs it has no row for
	// by smuggling other characters, and only procs that exist on the host are candidates.
	if(!istext(action) || !GLOB.ui_action_name_regex.Find(action))
		return null
	var/proc_name = "ui_[action]"
	if(!hascall(host, proc_name))
		return null
	// A legacy UI_ACT row for this action still wins until its host is migrated.
	var/datum/ui_decl/decl = ui_decl_of(host)
	if(decl?.acts[action])
		return null
	var/mob/user = ui?.user
	if(!host.ui_allowed(user, action))
		return list(TRUE, FALSE)
	// The client's keys first, then the reserved names LAST, so a payload can never set user (or
	// src/usr/ui/state). Every other ui_ parameter is client-facing by rule (ui_actions_lint): internal
	// flags live on separate procs.
	var/list/named = list()
	for(var/key in params)
		if(!istext(key) || !GLOB.ui_action_name_regex.Find(key) || (key in GLOB.ui_reserved_arg_names))
			continue
		named[key] = params[key]
	named["user"] = user
	var/datum/dispatch_context/ctx = new(user, host, null, null, ui)
	var/list/logged = type_list(host, TYPE_PROC_REF(/datum, ui_logged))
	var/result = dispatch_call(ctx, host, proc_name, named, action, logged[action])
	return list(TRUE, result != UI_REFUSED && result != FALSE)

/// Action names and argument keys: lowercase letters, digits and underscores only.
GLOBAL_DATUM_INIT(ui_action_name_regex, /regex, regex(@"^[a-z0-9_]+$"))
/// Argument names a client may never supply (the dispatcher sets or forbids them).
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state"))

// ---- validators: null when the value is not acceptable ----

/// A number (or numeric text) clamped to [min_value, max_value]; null if it isn't one.
/proc/ui_number(value, min_value = -INFINITY, max_value = INFINITY, round_to = 0)
	if(istext(value))
		value = text2num(value)
	if(!isnum(value) || value != value)
		return null
	if(round_to)
		value = round(value, round_to)
	return clamp(value, min_value, max_value)

/// Text, sanitised and cut to max_length; null if it isn't text (a number is rendered).
/proc/ui_text(value, max_length = MAX_MESSAGE_LEN)
	if(isnum(value))
		value = "[value]"
	if(!istext(value))
		return null
	return sanitize(value, max_length)

/// value if it is one of choices (a list), else null.
/proc/ui_choice(value, list/choices)
	if(isnull(value) || !(value in choices))
		return null
	return value

/// The datum a ref names, if it is in `within` (or anywhere with within null) and of type `type`.
/proc/ui_ref(value, list/within, type)
	if(!istext(value))
		return null
	var/datum/D = within ? locate(value) in within : locate(value)
	if(!D || (type && !istype(D, type)))
		return null
	return D
