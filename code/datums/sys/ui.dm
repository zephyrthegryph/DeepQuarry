// Declared UI model runtime (doc/rewrite/systems.md section 3; macros in code/__defines/sys_ui.dm).

/// TRUE while an om_act_ask() answer re-runs a UI_ACT row (ui_dispatch_typed()).
GLOBAL_VAR_INIT(ui_rerun, FALSE)

/// host type -> /datum/ui_decl (or FALSE when the type declares nothing). Built once per type.
GLOBAL_LIST_EMPTY(ui_decls)

/// Marker root: every DECLARE_UI / UI_DATA / UI_ACT row is a proc on /datum/ui_declared<host path>.
/datum/ui_declared

/datum/ui_declared/proc/declaration()
	return null

/datum/ui_declared/proc/field_rows()
	return null

/datum/ui_declared/proc/act_rows()
	return null

/datum/ui_declared/proc/watch_mask()
	return 0

/datum/ui_declared/proc/state_row()
	return null

/datum/ui_declared/proc/subact_rows()
	return null

/// The flattened table of one host type.
/datum/ui_decl
	/// Host type this table is for.
	var/host
	/// Marker type the rows came from.
	var/marker
	var/interface
	/// Host var holding the interface name (UI_FROM_VAR), instead of a literal interface.
	var/interface_var
	var/datum/tgui_state/state
	var/title
	var/autoupdate = FALSE
	/// UI_PINNED: the window can't be closed by "close all windows" (closeable = FALSE).
	var/pinned = FALSE
	/// UI_PREINITIALIZED: ui_window() hands an already initialized window; open() skips initialize.
	var/preinitialized = FALSE
	/// list(kind, name, key, ts_type) per exported field.
	var/list/fields
	/// action -> list(proc name, list(specs)).
	var/list/acts
	/// namespace -> (sub-action -> list(proc name, list(specs))): UI_SUBACT rows.
	var/list/subacts
	/// Channels that push a bound window (UI_DATA fields' channels | UI_WATCH).
	var/watch = 0
	/// Fields already checked against a live host instance.
	var/validated = FALSE

// The declared tgui state is a singleton (GLOB.tgui_*_state): a registry type, so `state` is
// implicitly shared (doc/rewrite/ownership.md §2).

// ---------------------------------------------------------------- declaration helpers

/proc/ui_declare(interface, list/opts)
	var/list/out = list("interface" = interface)
	for(var/list/opt as anything in opts)
		out[opt[1]] = opt[2]
	return out

/proc/ui_declare_fields(list/rows, list/fields)
	if(!rows)
		rows = list()
	for(var/field in fields)
		rows += list(ui_parse_field("[field]"))
	return rows

/// One UI_DATA field: list(kind, source name, data key, ts type, merge keys). Forms:
/// "var", "key=var", "proc:getter", "key=proc:getter", "slot:SLOT", each with an optional
/// ":type" suffix, and "merge:getter{key:type,...}" (the getter returns several keys at once;
/// the braces list them for the generated TS).
/proc/ui_parse_field(text)
	var/key
	var/equals = findtext(text, "=")
	if(equals)
		key = copytext(text, 1, equals)
		text = copytext(text, equals + 1)
	var/kind = UI_FIELD_VAR
	var/list/merge_keys
	if(findtext(text, "proc:") == 1)
		kind = UI_FIELD_PROC
		text = copytext(text, 6)
	else if(findtext(text, "slot:") == 1)
		kind = UI_FIELD_SLOT
		text = copytext(text, 6)
	else if(findtext(text, "merge:") == 1)
		kind = UI_FIELD_MERGE
		text = copytext(text, 7)
		var/brace = findtext(text, "{")
		merge_keys = list()
		if(brace)
			for(var/entry in splittext(copytext(text, brace + 1, length(text)), ","))
				var/entry_colon = findtext(entry, ":")
				if(entry_colon)
					merge_keys[copytext(entry, 1, entry_colon)] = copytext(entry, entry_colon + 1)
				else if(length(entry))
					merge_keys[entry] = "unknown"
			text = copytext(text, 1, brace)
	var/ts_type = "unknown"
	var/colon = findtext(text, ":")
	if(colon)
		ts_type = copytext(text, colon + 1)
		text = copytext(text, 1, colon)
	return list(kind, text, key || text, ts_type, merge_keys)

/proc/ui_declare_act(list/rows, action, proc_name, list/specs, list/nested)
	if(!rows)
		rows = list()
	rows[action] = list(proc_name, specs, nested)
	return rows

/proc/ui_declare_subact(list/rows, namespace, action, proc_name, list/specs)
	if(!rows)
		rows = list()
	var/list/space = rows[namespace]
	if(!space)
		space = list()
		rows[namespace] = space
	space[action] = list(proc_name, specs)
	return rows

// ---------------------------------------------------------------- table lookup

/// The marker type holding `host_type`'s rows (its own or its nearest declaring parent's), or null.
/proc/ui_marker_of(host_type)
	for(var/p = host_type; p; p = type2parent(p))
		var/marker = text2path("/datum/ui_declared[p]")
		if(marker)
			return marker
	return null

/// Builds the table for a marker type (used per host type and by the types dump).
/proc/ui_build_decl(marker, host_type)
	var/datum/ui_decl/decl = new
	decl.host = host_type
	decl.marker = marker
	var/datum/ui_declared/M = new marker
	var/list/declared = M.declaration()
	if(declared)
		var/iface = declared["interface"]
		if(islist(iface))
			decl.interface_var = iface[2]
		else
			decl.interface = iface
		decl.state = declared["state"]
		decl.title = declared["title"]
		decl.autoupdate = declared["autoupdate"] ? TRUE : FALSE
		decl.pinned = declared["pinned"] ? TRUE : FALSE
		decl.preinitialized = declared["preinitialized"] ? TRUE : FALSE
	// A DECLARE_UI_STATE row (nearest in the hierarchy) wins over a DECLARE_UI's UI_STATE option.
	decl.state = M.state_row() || decl.state
	decl.fields = M.field_rows() || list()
	decl.acts = M.act_rows() || list()
	decl.subacts = M.subact_rows() || list()
	decl.watch = M.watch_mask()
	// The marker is a stateless row holder: nothing keeps it, so it is simply dropped.
	if(host_type)
		var/list/channels = om_registry().fields_of(host_type)
		for(var/list/field as anything in decl.fields)
			if(field[1] == UI_FIELD_VAR)
				decl.watch |= channels[field[2]] || 0
	return decl

/// The declared UI table of `D`'s type, or null when it declares nothing.
/proc/ui_decl_of(datum/D)
	RETURN_TYPE(/datum/ui_decl)
	if(!D)
		return null
	var/decl = GLOB.ui_decls[D.type]
	if(isnull(decl))
		var/marker = ui_marker_of(D.type)
		decl = marker ? ui_build_decl(marker, D.type) : FALSE
		GLOB.ui_decls[D.type] = decl
	if(!decl)
		return null
	var/datum/ui_decl/table = decl
	if(!table.validated)
		table.validated = TRUE
		ui_validate_decl(table, D)
	return table

/// Checks the fields against a live instance: a missing var or getter is a declaration bug.
/proc/ui_validate_decl(datum/ui_decl/decl, datum/D)
	for(var/list/field as anything in decl.fields)
		switch(field[1])
			if(UI_FIELD_VAR)
				if(!(field[2] in D.vars))
					stack_trace("UI_DATA on [decl.host]: '[field[2]]' is not a var of [D.type]")
			if(UI_FIELD_PROC, UI_FIELD_MERGE)
				if(!hascall(D, field[2]))
					stack_trace("UI_DATA on [decl.host]: 'proc:[field[2]]' is not a proc of [D.type]")

// ---------------------------------------------------------------- hooks (override on the host)

/// Another datum whose UI opens instead of this one's (a console showing its program's UI).
/datum/proc/ui_redirect(mob/user)
	return null

/// Runs before the window opens or refreshes; FALSE refuses (and closes an open window).
/// Guards (power, locks, access, "must be secured") and lazy setup go here.
/datum/proc/ui_prepare(mob/user, datum/tgui/ui)
	return TRUE

/// The interface to open (the DECLARE_UI one unless this picks by state).
/datum/proc/ui_interface(mob/user)
	var/datum/ui_decl/decl = ui_decl_of(src)
	if(decl?.interface_var)
		return vars[decl.interface_var]
	return decl?.interface || present_interface(src)?.args["window"] || tgui_id

/// The answer to a question one of `host`'s window buttons asked still counts: the window the answerer works it through is still open and
/// interactive. A window host with no reach rule of its own says `request_usable(R)` as `return window_request_usable(src, R)`.
/proc/window_request_usable(datum/host, datum/request/R)
	var/mob/user = R.answerer
	if(QDELETED(host) || !istype(user))
		return FALSE
	var/datum/tgui/ui = SStgui.get_open_ui(user, host)
	return !!ui && ui.status == STATUS_INTERACTIVE

/// The tgui interface this type opens (a type var, dx_conventions.md §5), e.g. "SupplyConsole".
/datum/var/tgui_id
/// The tgui state its window uses, or null for the default.
/datum/var/datum/tgui_state/tgui_window_state
/**
 * The admin rights (R_* flags, at least ONE of them) its window needs: `ui_rights = R_ADMIN | R_SERVER` on an admin
 * panel. The window opens and stays interactive only for an admin holding one (ADMIN_STATE(ui_rights), unless a
 * DECLARE_UI_STATE / tgui_window_state says otherwise), and every act_<x>() / UI_ACT from anyone else is refused and
 * audited (admin_require()). Per-action narrowing stays inside the handler: `admin_require(user.client, R_X, entry)`.
 * A type var: nothing per instance.
 */
/datum/var/ui_rights

/// The window title: UI_TITLE, else the host's name.
/datum/proc/ui_title(mob/user)
	var/datum/ui_decl/decl = ui_decl_of(src)
	if(decl?.title)
		return decl.title
	var/datum/entry/declared = present_interface(src)
	if(declared?.args["title"])
		return declared.args["title"]
	if("name" in vars)
		return vars["name"]
	return decl?.interface

/// The /datum/tgui_window to render in (a dedicated skin element: lobby, tooltip, media panel),
/// or null for a pooled popup window.
/datum/proc/ui_window(mob/user)
	return null

/// Called on a new window after it is configured and before it opens.
/datum/proc/ui_opening(mob/user, datum/tgui/ui)
	return

/// Called after a new window opened (it has its tgui_window now: map views attach here).
/datum/proc/ui_opened(mob/user, datum/tgui/ui)
	return

/// Runs before every UI_ACT row; FALSE refuses the message (the handler is not called).
/// Type-wide action guards (access, lock, "is the panel open") go here.
/datum/proc/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	return TRUE

/// Whether `user` may run sub-action `action` of a UI_ACT_NESTED namespace (FALSE refuses).
/datum/proc/ui_nested_allowed(namespace, action, mob/user)
	return TRUE

/// After a UI_ACT_NESTED sub-action ran; returns the action's result (TRUE updates the window).
/datum/proc/ui_nested_done(namespace, action, result, mob/user)
	return result

/// The data fragment of slot `slot` ("slot:X" fields). The slot system (#4) implements it.
/datum/proc/ui_slot_fragment(slot, mob/user)
	return null

// ---------------------------------------------------------------- generic interact / data / act

/// The generated tgui_interact(): open, reuse and bind the declared window.
/proc/ui_open(datum/host, mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	var/datum/redirect = host.ui_redirect(user)
	if(redirect && redirect != host)
		// A window the host itself had open (a program that just went inactive) closes.
		if(ui && ui.src_object() == host)
			ui.close()
			ui = null
		return redirect.tgui_interact(user, ui, parent_ui, custom_state)
	var/datum/ui_decl/decl = ui_decl_of(host)
	if(!decl?.interface && !decl?.interface_var && !host.tgui_id && !present_interface(host))
		return FALSE
	if(!host.ui_prepare(user, ui))
		ui?.close()
		return FALSE
	ui = SStgui.try_update_ui(user, host, ui)
	if(ui)
		if(custom_state)
			ui.set_state(custom_state)
		return ui
	var/interface = host.ui_interface(user)
	if(!interface)
		return FALSE
	ui = new(user, host, interface, host.ui_title(user), parent_ui, null, null, host.ui_window(user))
	var/datum/tgui_state/state = custom_state || decl?.state || interface_state(host) || host.tgui_window_state || (host.ui_rights ? ADMIN_STATE(host.ui_rights) : null)
	if(state)
		ui.set_state(state)
	if(decl?.autoupdate)
		ui.set_autoupdate(TRUE)
	if(decl?.pinned)
		ui.closeable = FALSE
	host.ui_opening(user, ui)
	ui.open(decl?.preinitialized)
	if(!QDELETED(ui))
		host.ui_opened(user, ui)
	if(decl?.watch && !QDELETED(ui))
		om_ui_bind(ui, host, decl.watch)
		rel_set(ui, nameof(ui.om_bound), host)
	return ui

/// The tgui state the host's interface() declares: its `state` (a state global's name, or a state), else ADMIN_STATE of its `rights`, else null.
/proc/interface_state(datum/host)
	RETURN_TYPE(/datum/tgui_state)
	var/datum/entry/declared = present_interface(host)
	if(!declared)
		return null
	var/state = declared.args["state"]
	if(istext(state))
		var/found = GLOB.vars[state]
		if(!istype(found, /datum/tgui_state))
			stack_trace("interface([declared.args["window"]]) on [host.type]: state \"[state]\" is not a tgui state global")
			return null
		return found
	if(istype(state, /datum/tgui_state))
		return state
	var/rights = declared.args["rights"]
	if(isnum(rights) && rights)
		return ADMIN_STATE(rights)
	return null

/// A window's periodic refresh (autoupdate, forced): the host's ui_prepare() runs as it does on a
/// reopen, then the window updates. Never opens a window, so it never sleeps; a host that now
/// shows another datum's UI, or refuses, closes the window.
/proc/ui_refresh(datum/host, mob/user, datum/tgui/ui)
	var/datum/redirect = host.ui_redirect(user)
	if((redirect && redirect != host) || !host.ui_prepare(user, ui))
		ui.close()
		return
	SStgui.try_update_ui(user, host, ui)

/// The declared data of `host` for `user` (getters take (user, ui, state)).
/proc/ui_declared_data(datum/host, mob/user, datum/tgui/ui, datum/tgui_state/state)
	. = list()
	var/datum/ui_decl/decl = ui_decl_of(host)
	if(!decl)
		return
	for(var/list/field as anything in decl.fields)
		switch(field[1])
			if(UI_FIELD_VAR)
				.[field[3]] = host.vars[field[2]]
			if(UI_FIELD_PROC)
				.[field[3]] = call(host, field[2])(user, ui, state)
			if(UI_FIELD_SLOT)
				.[field[3]] = host.ui_slot_fragment(field[2], user)
			if(UI_FIELD_MERGE)
				var/list/part = call(host, field[2])(user, ui, state)
				if(islist(part))
					for(var/key in part)
						.[key] = part[key]

/// Finds `action`'s row, parses its args and runs the handler. Returns the handler's result
/// (TRUE updates the window), or null when no row matched or validation failed.
/proc/ui_dispatch(datum/host, action, list/params, datum/tgui/ui, datum/tgui_state/state)
	var/datum/ui_decl/decl = ui_decl_of(host)
	var/list/row = decl?.acts[action] || decl?.acts[UI_ACT_ANY]
	if(!row && !decl?.acts[UI_ACT_FORWARD_KEY])
		return null
	var/mob/user = ui?.user
	GLOB.ui_rerun = FALSE // a click is never a re-run (also clears a re-run that runtimed)
	if(host.ui_rights && !admin_require(user?.client, host.ui_rights, "[host.type]:[action]"))
		return FALSE
	if(!host.ui_act_allowed(user, action, ui, state))
		return FALSE
	if(!row)
		return ui_forward(host, decl, action, params, ui, state)
	if(row[3])
		return ui_dispatch_nested(host, decl, row[3], params, user, ui, state)
	var/list/typed = ui_parse_args(host, row[2], params, user, action)
	if(!typed)
		return FALSE
	return call(host, row[1])(user, typed, ui, state, action)

/// A UI_ACT_NESTED row: the sub-action named by params[subkey] runs its UI_SUBACT row, parsed
/// from the same message.
/proc/ui_dispatch_nested(datum/host, datum/ui_decl/decl, list/nested, list/params, mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/namespace = nested[1]
	var/sub_action = params?[nested[2]]
	var/list/row = istext(sub_action) ? decl.subacts[namespace]?[sub_action] : null
	if(!row)
		log_tgui(user, "UI_ACT_NESTED rejected: [host.type] [namespace] has no sub-action [json_encode(sub_action)]", "ui_dispatch_nested", src_object = host)
		return FALSE
	if(!host.ui_nested_allowed(namespace, sub_action, user))
		return FALSE
	var/list/typed = ui_parse_args(host, row[2], params, user, "[namespace]:[sub_action]")
	if(!typed)
		return FALSE
	var/result = call(host, row[1])(user, typed, ui, state, sub_action, null)
	return host.ui_nested_done(namespace, sub_action, result, user)

/// Runs the UI_SUBACT row (namespace, action) of `host` with `params` parsed by its specs.
/// Returns the handler's result, null when no row matches, FALSE when an arg is invalid.
/proc/ui_subdispatch(datum/host, namespace, action, list/params, mob/user, datum/tgui/ui, datum/tgui_state/state, extra)
	var/datum/ui_decl/decl = ui_decl_of(host)
	var/list/space = decl?.subacts[namespace]
	var/list/row = space?[action]
	if(!row)
		return null
	var/list/typed = ui_parse_args(host, row[2], params, user, "[namespace]:[action]")
	if(!typed)
		return FALSE
	return call(host, row[1])(user, typed, ui, state, action, extra)

/// Hands an action no row names to the datums the host's UI_ACT_FORWARD row returns; their own
/// rows parse it. Returns the first truthy result.
/proc/ui_forward(datum/host, datum/ui_decl/decl, action, list/params, datum/tgui/ui, datum/tgui_state/state)
	var/list/row = decl?.acts[UI_ACT_FORWARD_KEY]
	if(!row)
		return null
	var/targets = call(host, row[1])(ui?.user, action)
	if(!islist(targets))
		targets = targets ? list(targets) : null
	for(var/datum/target as anything in targets)
		if(QDELETED(target) || target == host)
			continue
		. = target.tgui_act(action, params, ui, state)
		if(.)
			return

/// Re-runs `action` with params that are already typed (an om_act_ask() answer re-run): the same
/// gates as a click (interactive window, ui_act_allowed()), no re-parse.
/proc/ui_dispatch_typed(datum/host, action, list/typed, datum/tgui/ui, datum/tgui_state/state)
	if(QDELETED(host) || !ui || ui.status != STATUS_INTERACTIVE)
		return FALSE
	var/datum/ui_decl/decl = ui_decl_of(host)
	var/list/row = decl?.acts[action] || decl?.acts[UI_ACT_ANY]
	if(!row)
		return FALSE
	if(row[3])
		// A nested sub-action re-runs its own handler with rerun_ask(), not act_ask().
		stack_trace("[host.type] re-ran UI_ACT_NESTED action '[action]' through act_ask(); use rerun_ask() in UI_SUBACT handlers")
		return FALSE
	GLOB.ui_rerun = TRUE
	. = FALSE
	if(host.ui_act_allowed(ui.user, action, ui, state))
		. = call(host, row[1])(ui.user, typed, ui, state, action)
	GLOB.ui_rerun = FALSE

/// The typed args of one message, or null (logged) when a present arg fails its spec.
/proc/ui_parse_args(datum/host, list/specs, list/params, mob/user, action)
	var/list/typed = list()
	for(var/list/spec as anything in specs)
		var/name = spec[2]
		var/raw = params?[name]
		if(isnull(raw))
			typed[name] = null
			continue
		var/value = ui_parse_arg(host, spec, raw)
		if(isnull(value))
			log_tgui(user, "UI_ACT rejected: [host.type] action '[action]' arg [name]=[json_encode(raw)]", "ui_parse_args", src_object = host)
			return null
		typed[name] = value
	return typed

/// One arg by its spec; null when invalid.
/proc/ui_parse_arg(datum/host, list/spec, raw)
	switch(spec[1])
		if(UI_ARGK_NUM, UI_ARGK_INT)
			var/num = isnum(raw) ? raw : (istext(raw) ? text2num(raw) : null)
			if(!isnum(num) || num != num) // NaN
				return null
			if(spec[1] == UI_ARGK_INT)
				num = round(num, 1)
			if(length(spec) >= 4)
				num = clamp(num, spec[3], spec[4])
			return num
		if(UI_ARGK_TEXT)
			var/text
			if(istext(raw))
				text = raw
			else if(isnum(raw))
				text = "[raw]"
			else
				return null
			var/maxlen = length(spec) >= 3 && spec[3] ? spec[3] : UI_TEXT_MAXLEN
			if(length(text) > maxlen)
				text = copytext(text, 1, maxlen + 1)
			return text
		if(UI_ARGK_BOOL)
			if(isnum(raw))
				return raw ? TRUE : FALSE
			if(istext(raw))
				return (raw == "" || raw == "0" || raw == "false") ? FALSE : TRUE
			return null
		if(UI_ARGK_CHOICE)
			var/list/pool = ui_arg_source(host, spec[3])
			if(!islist(pool))
				return null
			if(raw in pool)
				return raw
			if(isnum(raw) && ("[raw]" in pool))
				return "[raw]"
			if(istext(raw))
				var/num = text2num(raw)
				if(!isnull(num) && (num in pool))
					return num
			return null
		if(UI_ARGK_REF)
			return ui_resolve_ref(host, raw, spec[3], length(spec) >= 4 ? spec.Copy(4) : null)
		if(UI_ARGK_PATH)
			var/path = ispath(raw) ? raw : (istext(raw) ? text2path(raw) : null)
			if(!ispath(path, spec[3]))
				return null
			return path
		if(UI_ARGK_LIST)
			if(islist(raw))
				return raw
			if(istext(raw) && length(raw) <= UI_TEXT_MAXLEN * 16)
				var/first = copytext(raw, 1, 2)
				if(first == "\[" || first == "{")
					var/list/decoded
					try
						decoded = json_decode(raw)
					// ALLOW(silent_catch): malformed JSON from the client is a rejected arg; ui_parse_args() logs the rejection.
					catch
						return null
					return islist(decoded) ? decoded : null
			return null
		if(UI_ARGK_VALUE)
			if(isnum(raw))
				return raw == raw ? raw : null // NaN
			if(!istext(raw))
				return null
			var/maxlen = length(spec) >= 3 && spec[3] ? spec[3] : UI_TEXT_MAXLEN
			return length(raw) > maxlen ? copytext(raw, 1, maxlen + 1) : raw
	return null

/// Resolves a choice/ref source on `host`: a list; "glob:x" (GLOB.x); "proc:x" (host.x());
/// "x" (host var x).
/proc/ui_arg_source(datum/host, source)
	if(islist(source))
		return source
	if(!istext(source))
		return null
	if(findtext(source, "glob:") == 1)
		return GLOB.vars[copytext(source, 6)]
	if(findtext(source, "proc:") == 1)
		return call(host, copytext(source, 6))()
	if(source in host.vars)
		return host.vars[source]
	stack_trace("UI arg source '[source]' does not exist on [host.type]")
	return null

/// `locate(raw) in <source>` (anywhere when source is null), then istype any of `types`.
/proc/ui_resolve_ref(datum/host, raw, source, list/types)
	if(!istext(raw))
		return null
	var/found
	if(isnull(source))
		found = locate(raw)
	else
		var/list/pool = ui_arg_source(host, source)
		if(!islist(pool))
			return null
		found = locate_in_list(pool, raw)
	if(isnull(found))
		return null
	if(length(types))
		var/matched = FALSE
		for(var/wanted in types)
			if(istype(found, wanted))
				matched = TRUE
				break
		if(!matched)
			return null
	if(isdatum(found))
		var/datum/FD = found
		if(QDELETED(FD))
			return null
	return found

// ---------------------------------------------------------------- the one base action

UI_ACT(/datum, "change_ui_state", ui_act_change_ui_state, UI_ARG_TEXT("new_state", 64))

UI_ACT_PROC(/datum, ui_act_change_ui_state)
	var/mob/living/living_user = user
	//write_preferences will make sure it's valid for href exploits.
	living_user?.client?.prefs.write_preference(GLOB.preference_entries[/datum/preference/choiced/tgui_layout], params["new_state"])
	return FALSE

// ---------------------------------------------------------------- UI_TYPES_DUMP

/// Writes every declared table to `path` (JSON) for tools/build/lib/ui_types.ts, which turns it
/// into tgui/packages/tgui/interfaces/generated/<Interface>.d.ts. A -DUI_TYPES_DUMP boot calls it
/// and exits; it is compiled always (and exercised by dq_sys_ui_tests) so it cannot rot.
/proc/ui_types_dump(path = "data/ui_types.json", resolve_vars = TRUE)
	var/list/out = list()
	for(var/marker in subtypesof(/datum/ui_declared))
		var/host_text = copytext("[marker]", length("/datum/ui_declared") + 1)
		var/host = text2path(host_text)
		if(!host || text2path("/datum/ui_declared[host_text]") != marker)
			continue
		var/datum/ui_decl/decl = ui_build_decl(marker, host)
		var/list/acts = list()
		for(var/action in decl.acts)
			var/list/row = decl.acts[action]
			if(action == UI_ACT_FORWARD_KEY || action == UI_ACT_ANY)
				continue
			if(row[3])
				var/list/nested = row[3]
				for(var/sub_action in decl.subacts[nested[1]])
					var/list/sub_args = ui_types_args(decl.subacts[nested[1]][sub_action][2])
					sub_args.Insert(1, list(list("name" = nested[2], "kind" = UI_ARGK_CHOICE, "choices" = list(sub_action))))
					acts["[action]:[sub_action]"] = list("action" = action, "args" = sub_args)
				continue
			acts["[action]"] = list("action" = action, "args" = ui_types_args(row[2]))
		var/list/fields = list()
		for(var/list/field as anything in decl.fields)
			if(field[1] == UI_FIELD_MERGE)
				var/list/merge_keys = field[5]
				for(var/merge_key in merge_keys)
					fields += list(list("key" = merge_key, "kind" = field[1], "type" = merge_keys[merge_key]))
				continue
			fields += list(list("key" = field[3], "kind" = field[1], "type" = field[4]))
		var/list/interfaces = list()
		if(decl.interface)
			interfaces += decl.interface
		else if(decl.interface_var && resolve_vars)
			interfaces |= ui_types_interfaces_from_var(host, decl.interface_var)
		if(!length(interfaces) && !length(acts))
			continue
		out += list(list("host" = host_text, "interfaces" = interfaces, "fields" = fields, "acts" = acts))
	rustg_file_write(json_encode(out), path)
	return length(out)

/// The args of one row for the dump.
/proc/ui_types_args(list/specs)
	. = list()
	for(var/list/spec as anything in specs)
		var/list/arg = list("name" = spec[2], "kind" = spec[1])
		if(spec[1] == UI_ARGK_CHOICE && islist(spec[3]))
			arg["choices"] = spec[3]
		. += list(arg)

/// The interfaces a UI_FROM_VAR host's concrete types name (plain datums only: they are made and
/// dropped without an Initialize; atoms keep the var's name as their only entry).
/proc/ui_types_interfaces_from_var(host, var_name)
	. = list()
	if(ispath(host, /atom))
		return
	for(var/path in typesof(host))
		var/datum/D
		try
			D = new path
		catch(var/exception/e)
			log_world("ui_types_dump: [path] could not be made to read [var_name]: [e]")
			continue
		var/value = D.vars[var_name]
		if(istext(value) && length(value))
			. |= value
		try
			spent(D)
		catch(var/exception/e2)
			log_world("ui_types_dump: [path] could not be deleted: [e2]")

// Marker parents for DM's implicit parents, so rows inherit along the real host hierarchy.
/datum/ui_declared/atom
	parent_type = /datum/ui_declared/datum
/datum/ui_declared/atom/movable
/datum/ui_declared/obj
	parent_type = /datum/ui_declared/atom/movable
/datum/ui_declared/mob
	parent_type = /datum/ui_declared/atom/movable
/datum/ui_declared/turf
	parent_type = /datum/ui_declared/atom
/datum/ui_declared/area
	parent_type = /datum/ui_declared/atom
