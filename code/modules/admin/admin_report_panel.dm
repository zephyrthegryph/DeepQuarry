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

CAPABILITIES(/datum/admin_report)
	interface("AdminReport", rights = R_ADMIN|R_MOD|R_DEBUG|R_SERVER|R_EVENT)
	op("forward_topic", ui_act("forward_topic", arg("href", schema_text(4096))), then(PROC_REF(ui_act_forward_topic)))
	op("close", ui_act("close"), then(PROC_REF(ui_act_close)))

/datum/admin_report/ui_title(mob/user)
	return title

/datum/admin_report/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["title"] = title
	data["intro_html"] = intro_html
	data["body_html"] = body_html
	var/list/merged_1 = ui_data_datum_admin_report(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/admin_report's window data.
/datum/admin_report/proc/ui_data_datum_admin_report(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["lines"] = lines || list()
	data["columns"] = columns || list()
	data["rows"] = rows || list()
	data["has_host"] = !!forward_host()
	return data

/datum/admin_report/proc/ui_act_forward_topic(datum/act/op/A, href)
	var/mob/user = A.actor
	dispatch_forwarded_topic(user, forward_host(), "[href]")
	SStgui.update_uis(src)
	return TRUE

/datum/admin_report/proc/ui_act_close(datum/act/op/A)
	SStgui.close_uis(src)
	spent(src)
	return OP_OK

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

CAPABILITIES(/datum/dq_stock_chart_panel)
	interface("StockChart", state = nameof(GLOB.tgui_default_state))
	ui_shape(stock_name = any, points = bool())

/datum/dq_stock_chart_panel/ui_title(mob/user)
	return "Share Value: [stock_name]"

/// /datum/dq_stock_chart_panel's window data.
/datum/dq_stock_chart_panel/ui_data(datum/act/eval/A)
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
