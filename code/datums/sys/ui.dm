// The window runtime: a host's interface() (code/engine/parts/part.dm) opens here; its buttons are ops (code/engine/parts/inputs.dm).

// ---------------------------------------------------------------- hooks (override on the host)

/// Another datum whose UI opens instead of this one's (a console showing its program's UI).
/datum/proc/ui_redirect(mob/user)
	return null

/// Runs before the window opens or refreshes; FALSE refuses (and closes an open window).
/// Guards (power, locks, access, "must be secured") and lazy setup go here.
/datum/proc/ui_prepare(mob/user, datum/tgui/ui)
	return TRUE

/// The interface to open: interface()'s window, the host var its `window_var` names, else the type's tgui_id.
/datum/proc/ui_interface(mob/user)
	var/datum/entry/declared = present_interface(src)
	var/window_var = declared?.args["window_var"]
	return declared?.args["window"] || (istext(window_var) && (window_var in vars) ? vars[window_var] : null) || tgui_id

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
 * interface(state =) / tgui_window_state says otherwise), and every act_<x>() from anyone else is refused and
 * audited (admin_require()). Per-action narrowing stays inside the handler: `admin_require(user.client, R_X, entry)`.
 * A type var: nothing per instance.
 */
/datum/var/ui_rights

/// The window title: interface(title =), else the host's name.
/datum/proc/ui_title(mob/user)
	var/datum/entry/declared = present_interface(src)
	if(declared?.args["title"])
		return declared.args["title"]
	if("name" in vars)
		return vars["name"]
	return declared?.args["window"]

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

// ---------------------------------------------------------------- open

/// The generated tgui_interact(): open, reuse and bind the declared window.
/proc/ui_open(datum/host, mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	var/datum/redirect = host.ui_redirect(user)
	if(redirect && redirect != host)
		// A window the host itself had open (a program that just went inactive) closes.
		if(ui && ui.src_object() == host)
			ui.close()
			ui = null
		return redirect.tgui_interact(user, ui, parent_ui, custom_state)
	var/datum/entry/declared = present_interface(host)
	if(!host.tgui_id && !declared)
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
	var/datum/tgui_state/state = custom_state || interface_state(host) || host.tgui_window_state || (host.ui_rights ? ADMIN_STATE(host.ui_rights) : null)
	if(state)
		ui.set_state(state)
	if(declared?.args["autoupdate"])
		ui.set_autoupdate(TRUE)
	if(declared?.args["pinned"])
		ui.closeable = FALSE
	host.ui_opening(user, ui)
	ui.open(declared?.args["preinitialized"])
	if(!QDELETED(ui))
		host.ui_opened(user, ui)
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
