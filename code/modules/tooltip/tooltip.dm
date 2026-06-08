// Tooltip system rewritten to TGUI.
//
// The legacy version loaded tooltip.html + jQuery into the hidden
// `mainwindow.tooltip` BROWSER skin element, then drove it via
// `output("...", "mainwindow.tooltip:tooltip.update")` JS-interop
// calls. The HTML/JS measured the actual map pixel size via
// `winget(mapwindow.map, size,view-size)` and absolute-positioned
// itself via `winset` calls.
//
// We host the same skin element as a /datum/tgui_window. Tooltip.tsx
// queries the map size with Byond.winget, runs the same positioning
// math, and renders a small absolute-positioned tooltip <div>. The
// outer BROWSER element stays 999x999 covering the whole window; the
// React tree uses pointer-events: none so it doesn't eat map clicks.
// Show/hide toggles the skin element's is-visible.


/datum/tooltip
	var/client/owner
	var/control = "mainwindow.tooltip"
	var/showing = 0
	var/queueHide = 0
	var/atom/last_target
	var/datum/tgui_window/tooltip_window
	// State that gets pushed to the React side. When `_visible` is
	// FALSE the React component renders nothing; otherwise it
	// reads these fields, runs the positioning math via Byond.winget,
	// and renders an absolute-positioned tooltip <div>.
	var/_visible = FALSE
	var/_title = ""
	var/_theme = ""
	var/_cursor_params = ""
	var/_screen_loc = ""
	var/_view_w = 0
	var/_view_h = 0


/datum/tooltip/New(client/C)
	if(!C)
		return
	owner = C
	tooltip_window = new(C, control)
	tooltip_window.initialize(
		assets = list(get_asset_datum(/datum/asset/simple/tgui)),
	)
	winset(C, control, "is-disabled=false;is-visible=false")
	// Spin up a TGUI on the window so the React side is mounted and
	// ready to receive show() calls. The state datum is the always
	// state since this is a per-client overlay; tgui_act has no
	// privileged operations.
	var/datum/tgui/ui = SStgui.try_update_ui(C.mob, src, null)
	if(!ui)
		ui = new(C.mob, src, "Tooltip", window = tooltip_window)
		ui.closeable = FALSE
		ui.open(preinitialized = TRUE)
	..()


/datum/tooltip/Destroy(force)
	if(tooltip_window)
		tooltip_window.close()
		tooltip_window = null
	last_target = null
	owner = null
	return ..()


/datum/tooltip/tgui_state(mob/user)
	return GLOB.tgui_always_state


/datum/tooltip/tgui_data(mob/user)
	return list(
		"visible" = _visible,
		"title" = _title,
		"theme" = _theme,
		"cursor_params" = _cursor_params,
		"screen_loc" = _screen_loc,
		"view_w" = _view_w,
		"view_h" = _view_h,
		// Native BYOND tile size; the legacy JS hard-coded 32 unless
		// world.icon_size was overridden, so we ship it directly.
		"tile_size" = isnum(world.icon_size) ? world.icon_size : 32,
	)


/datum/tooltip/proc/show(atom/movable/thing, params = null, title = null, content = null, theme = "default", special = "none")
	if(!thing || !params || (!title && !content) || !owner)
		return FALSE
	if(!isnum(world.icon_size))
		return FALSE

	if(!isnull(last_target))
		UnregisterSignal(last_target, COMSIG_QDELETING)
	RegisterSignal(thing, COMSIG_QDELETING, PROC_REF(on_target_qdel))
	last_target = thing

	showing = 1

	if(title && content)
		title = "<h1>[title]</h1>"
		content = "<p>[content]</p>"
	else if(title && !content)
		title = "<p>[title]</p>"
	else if(!title && content)
		content = "<p>[content]</p>"
	title = strip_improper(title)

	var/view_size = getviewsize(owner.view)
	_visible = TRUE
	_title = "[title][content]"
	_theme = theme
	_cursor_params = "[params]"
	_screen_loc = "[thing.screen_loc]"
	_view_w = view_size[1]
	_view_h = view_size[2]

	winset(owner, control, "is-visible=true")
	SStgui.update_uis(src)

	showing = 0
	if(queueHide)
		hide()
	return TRUE


/datum/tooltip/proc/hide()
	queueHide = showing ? TRUE : FALSE
	if(queueHide)
		addtimer(CALLBACK(src, PROC_REF(do_hide)), 0.1 SECONDS)
	else
		do_hide()
	return TRUE


/datum/tooltip/proc/on_target_qdel()
	SIGNAL_HANDLER
	INVOKE_ASYNC(src, PROC_REF(hide))
	last_target = null


/datum/tooltip/proc/do_hide()
	queueHide = FALSE
	if(!owner)
		return
	_visible = FALSE
	SStgui.update_uis(src)
	winset(owner, control, "is-visible=false")


//Open a tooltip for user, at a location based on params
//Theme is a CSS class in Tooltip.tsx, by default this wrapper chooses a CSS class based on the user's UI_style (Midnight, Plasmafire, Retro, etc)
//Includes sanity checks
/proc/openToolTip(mob/user = null, atom/movable/tip_src = null, params = null, title = "", content = "", theme = "")
	if(!istype(user) || !user.client?.tooltips)
		return
	var/ui_style = user.read_preference(/datum/preference/choiced/tooltip_style)
	if(!theme && ui_style)
		theme = lowertext(ui_style)
	if(!theme)
		theme = "midnight"
	user.client.tooltips.show(tip_src, params, title, content, theme)


//Arbitrarily close a user's tooltip
//Includes sanity checks.
/proc/closeToolTip(mob/user)
	if(!istype(user) || !user.client?.tooltips)
		return
	user.client.tooltips.hide()
