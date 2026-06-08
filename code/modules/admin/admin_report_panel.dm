// AdminReport — structured TGUI for one-shot admin reports (log dumps,
// crew manifests, qdel logs, airreports, etc.). Each call instantiates
// its own /datum/admin_report so the panel gets per-callsite identity.
//
// Three rendering modes, expressed in typed tgui_data:
//   - lines: one string per row (used for line-oriented logs).
//   - table: typed columns + per-row cell arrays.
//   - body_html: pre-formatted HTML for things that don't fit the above
//     (rendered through HtmlRenderer with forwardTopic so any embedded
//      byond:// links still dispatch through the host's Topic handler).
//
// All three may be combined (intro paragraph + lines, or table + footer)
// so the most common cases stay typed even when there's some chrome HTML.

/datum/admin_report
	var/title = ""
	/// Optional intro/header HTML rendered above lines/table.
	var/intro_html = ""
	/// Line-oriented body — one entry per row.
	var/list/lines
	/// Table header strings (column names).
	var/list/columns
	/// Per-row cell arrays; each inner list aligns with `columns`.
	var/list/rows
	/// Optional fully-formatted HTML body (rendered after lines/table).
	var/body_html = ""
	/// Optional datum receiving forwarded byond:// link clicks. May be null.
	var/datum/forward_host

/datum/admin_report/New(report_title, mob/viewer, datum/host)
	..()
	title = report_title
	forward_host = host

/datum/admin_report/Destroy(force, ...)
	forward_host = null
	return ..()

/datum/admin_report/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_MOD|R_DEBUG|R_SERVER|R_EVENT)

/datum/admin_report/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AdminReport", title)
		ui.open()

/datum/admin_report/tgui_data(mob/user)
	var/list/data = list()
	data["title"] = title
	data["intro_html"] = intro_html
	data["lines"] = lines || list()
	data["columns"] = columns || list()
	data["rows"] = rows || list()
	data["body_html"] = body_html
	data["has_host"] = !!forward_host
	return data

/datum/admin_report/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(action == "forward_topic")
		dispatch_forwarded_topic(ui.user, forward_host, "[params["href"]]")
		SStgui.update_uis(src)
		return TRUE
	if(action == "close")
		SStgui.close_uis(src)
		qdel(src)
		return TRUE

/// Show a report with a list of preformatted lines.
/proc/dq_admin_report_lines(mob/user, title, list/lines, intro_html = "", datum/host = null)
	if(!user?.client)
		return
	var/datum/admin_report/R = new(title, user, host)
	R.lines = lines ? lines.Copy() : list()
	R.intro_html = intro_html
	R.tgui_interact(user)

/// Show a report with a typed table.
/proc/dq_admin_report_table(mob/user, title, list/columns, list/rows, intro_html = "", datum/host = null)
	if(!user?.client)
		return
	var/datum/admin_report/R = new(title, user, host)
	R.columns = columns ? columns.Copy() : list()
	R.rows = rows ? rows.Copy() : list()
	R.intro_html = intro_html
	R.tgui_interact(user)

/// Show a report with a pre-formatted HTML body. The host receives any
/// byond:// link clicks inside the body via forwardTopic.
/proc/dq_admin_report_html(mob/user, title, body_html, datum/host = null)
	if(!user?.client)
		return
	var/datum/admin_report/R = new(title, user, host)
	R.body_html = body_html
	R.tgui_interact(user)

// StockChart — typed line/bar chart panel for stock share-value displays.

/datum/dq_stock_chart_panel
	var/stock_name
	var/list/points

/datum/dq_stock_chart_panel/New(name, list/series)
	..()
	stock_name = name
	points = series ? series.Copy() : list()

/datum/dq_stock_chart_panel/tgui_state(mob/user)
	return GLOB.tgui_default_state

/datum/dq_stock_chart_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "StockChart", "Share Value: [stock_name]")
		ui.open()

/datum/dq_stock_chart_panel/tgui_data(mob/user)
	return list(
		"stock_name" = stock_name,
		"points" = points || list(),
	)

/datum/stock/displayValues(mob/user)
	// structured TGUI StockChart panel; typed value series goes
	// to the React side which renders an SVG chart.
	if(!user?.client)
		return
	var/datum/dq_stock_chart_panel/panel = new(name, values)
	panel.tgui_interact(user)
