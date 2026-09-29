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
	var/tmp/datum/forward_host

/datum/admin_report/New(report_title, mob/viewer, datum/host)
	..()
	title = report_title
	rel_set(src, nameof(forward_host), host)

DECLARE_UI_STATE(/datum/admin_report, ADMIN_STATE(R_ADMIN|R_MOD|R_DEBUG|R_SERVER|R_EVENT))

DECLARE_UI(/datum/admin_report, "AdminReport")

/datum/admin_report/ui_title(mob/user)
	return title

UI_DATA_REPLACE(/datum/admin_report, "title:text", "intro_html:text", "body_html:text", "merge:ui_data_datum_admin_report{lines:bool,columns:bool,rows:bool,has_host:bool}")

/// The computed part of /datum/admin_report's window data (declared on its UI_DATA row).
/datum/admin_report/proc/ui_data_datum_admin_report(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["lines"] = lines || list()
	data["columns"] = columns || list()
	data["rows"] = rows || list()
	data["has_host"] = !!forward_host()
	return data

UI_ACT(/datum/admin_report, "forward_topic", ui_act_forward_topic, UI_ARG_TEXT("href"))
UI_ACT_PROC(/datum/admin_report, ui_act_forward_topic)
	dispatch_forwarded_topic(ui.user, forward_host(), "[params["href"]]")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/admin_report, "close", ui_act_close)
UI_ACT_PROC(/datum/admin_report, ui_act_close)
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

DECLARE_UI_STATE(/datum/dq_stock_chart_panel, GLOB.tgui_default_state)

DECLARE_UI(/datum/dq_stock_chart_panel, "StockChart")

/datum/dq_stock_chart_panel/ui_title(mob/user)
	return "Share Value: [stock_name]"

UI_DATA_REPLACE(/datum/dq_stock_chart_panel, "merge:ui_data_datum_dq_stock_chart_panel{stock_name:unknown,points:bool}")

/// The computed part of /datum/dq_stock_chart_panel's window data (declared on its UI_DATA row).
/datum/dq_stock_chart_panel/proc/ui_data_datum_dq_stock_chart_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/// The forward_host this refers to (a relation view: null once that is deleted).
/datum/admin_report/proc/forward_host() as /datum
	return forward_host
