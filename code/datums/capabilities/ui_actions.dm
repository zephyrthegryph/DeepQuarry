// UI actions as named procs (doc/rewrite/dx_conventions.md §5).
//
//	/obj/machinery/atmospherics/binary/pump/proc/act_set_pressure(mob/user, pressure)
//		pressure = ui_number(pressure, 0, MAX_PUMP_PRESSURE)
//		if(isnull(pressure))
//			return refuse(user, "That isn't a pressure.")
//		set_target_pressure(pressure)
//
// tgui_act() finds `act_<action>` on the host: only procs named act_* are client actions (ui_* are
// framework hooks, ui_act_* legacy handlers; neither is reachable). The client's params become named
// args, then the reserved names (user, src, usr, ui, state) are written LAST, so a payload can never
// set them. Action names and keys are normalised in one place (ui_action_key(): lowercase, hyphens
// and camelCase to snake_case), shared with tools/ci/ui_actions_lint.py. An argument name the proc
// doesn't declare is a runtime, caught by dispatch_call(), logged and refused. Types are not
// enforced by DM: the body validates each param first with ui_number/ui_text/ui_choice/ui_ref/
// ui_bool (the validator-first lint). ui_allowed() is the type-wide gate; ui_logged() says which
// actions are logged. Any proc named act_* on a UI host is a client action by rule.

/// The type-wide gate for every ui_<action>: FALSE refuses silently.
/datum/proc/ui_allowed(mob/user, action)
	return TRUE

/// Per-type table: action -> LOG_GAME / LOG_ADMIN, for the actions the dispatcher logs. A type sets its
/// own with TYPE_TABLE(/type, ui_logged_actions, list("action" = LOG_GAME)); an empty table logs nothing. Shared and
/// read-only.
TYPE_TABLE_DECLARE(/datum, ui_logged_actions, list())

/datum/proc/ui_logged()
	return TYPE_TABLE_GET(src, ui_logged_actions)

/// Runs `ui_<action>` if the host has one. Returns list(handled, result).
/proc/ui_named_dispatch(datum/host, action, list/params, datum/tgui/ui)
	var/key = ui_action_key(action)
	if(!key)
		return null
	var/proc_name = "act_[key]"
	// The host's own act_<key>, else the first of its capabilities that owns one (power_channels()
	// owns act_channel / act_breaker / act_nightshift, so the APC writes none of them). A capability's
	// action proc runs on the shared flyweight with the holder passed as `holder`.
	var/datum/capability/owner_cap
	if(!hascall(host, proc_name))
		if(!isatom(host))
			return null
		for(var/datum/capability/C as anything in caps_all(host))
			if(hascall(C, proc_name))
				owner_cap = C
				break
		if(!owner_cap)
			return null
	var/mob/user = ui?.user
	// ui_rights (code/datums/sys/ui.dm): an admin panel refuses, and audits, anyone without one of its rights.
	if(host.ui_rights && !admin_require(user?.client, host.ui_rights, "[host.type]:[key]"))
		return list(TRUE, FALSE)
	if(!host.ui_allowed(user, key))
		return list(TRUE, FALSE)
	// The client's keys first, then the reserved names LAST.
	var/list/named = list()
	for(var/raw in params)
		var/arg = ui_action_key(raw)
		if(!arg || (arg in GLOB.ui_reserved_arg_names))
			continue
		named[arg] = params[raw]
	named["user"] = user
	var/datum/dispatch_context/ctx = new(user, host, null, null, ui)
	var/log_level
	if(owner_cap)
		named["holder"] = host
		log_level = owner_cap.ui_logged()?[key]
	else
		var/list/logged = type_list(host, TYPE_PROC_REF(/datum, ui_logged))
		log_level = logged[key]
	var/result = dispatch_call(ctx, host, proc_name, named, key, log_level, owner_cap)
	return list(TRUE, dispatch_succeeded(result))

/// The one normalisation of client action names and argument keys: "bolt-toggle" and "boltToggle"
/// both become "bolt_toggle". Null for anything that isn't text of [A-Za-z0-9_-] (max 64).
/proc/ui_action_key(raw)
	if(!istext(raw) || !length(raw) || length(raw) > 64 || !GLOB.ui_action_raw_regex.Find(raw))
		return null
	var/out = GLOB.ui_action_camel_regex.Replace(raw, "$1_$2")
	out = replacetext(lowertext(out), "-", "_")
	return out

/// Raw action names and keys: letters, digits, underscores and hyphens.
GLOBAL_DATUM_INIT(ui_action_raw_regex, /regex, regex(@"^[A-Za-z0-9_-]+$"))
/// camelCase boundaries (a lowercase letter or digit followed by an uppercase letter).
GLOBAL_DATUM_INIT(ui_action_camel_regex, /regex, regex(@"([a-z0-9])([A-Z])", "g"))
/// Argument names a client may never supply (the dispatcher sets or forbids them).
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state", "holder"))

// ---- validators: null when the value is not acceptable ----

/// TRUE for true/1/"1"/"true"/"yes", FALSE for false/0/"0"/"false"/"no"/"", null for anything else.
/proc/ui_bool(value)
	if(isnum(value))
		return value ? TRUE : FALSE
	if(istext(value))
		switch(lowertext(value))
			if("1", "true", "yes", "on")
				return TRUE
			if("0", "false", "no", "off", "")
				return FALSE
	return null

/// A number (or numeric text) clamped to [min_value, max_value]; null if it isn't one.
/proc/ui_number(value, min_value = -INFINITY, max_value = INFINITY, round_to = 0)
	READS_FROM()
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
	READS_FROM() // a ref names a thing when a choice is made, never cached
	if(!istext(value))
		return null
	var/datum/D = within ? locate(value) in within : locate(value) // ALLOW(spatial): a ref lookup in a list the caller passes (a UI's own table), not a walk of an atom's contents
	if(!D || (type && !istype(D, type)))
		return null
	return D
