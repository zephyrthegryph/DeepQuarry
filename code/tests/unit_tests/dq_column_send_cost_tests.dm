// The server cost of a message to a window docked in the right-hand column (column_part.dm) against the same message to a native window.
// A column window's message is the native one (JSON, url-encoded) wrapped as `col/msg {wid, raw}` and encoded again for the panel's page.
// COLUMN_SEND_COST lines are the measurement: the stat panel's Status update (every 0.8 s to every player on the Status tab) and a verb list.

/// One send's encoding as tgui_window/send_message does it: the message string that leaves.
/proc/dq_test_tgui_encode(type, payload)
	var/payload_json = json_encode(payload)
	findtext(payload_json, HREF_TOKEN_PLACEHOLDER)
	return "%7b%22type%22%3a%22[type]%22%2c%22payload%22%3a[url_encode(payload_json)]%7d"

/datum/unit_test/dq_column_send_cost

/datum/unit_test/dq_column_send_cost/Run()
	var/list/status = list(
		"global_data" = list("Map: Southern Cross", "Round ID: 12345", "Server Time: 2026-11-08 13:00:00", "Round Time: 01:23:45",
			"Station Date: 2566-11-08, Autumn", "Station Time: 13:00", "Time Dilation: 3% AVG:(2%, 3%, 4%)"),
		"ping_str" = "Ping: 42ms (Average: 40ms)",
		"other_str" = list("Intent: Help", "Move Mode: Walk", "Internals: off", "Nutrition: 300/450", "Charge: 100%"),
	)
	var/list/verbs = list()
	for(var/i in 1 to 150)
		verbs += list(list("Category [i % 8]", "Verb number [i]"))
	measure("status update", "update_stat", status)
	measure("verb list", "update_verbs", list("verbs" = verbs))

/datum/unit_test/dq_column_send_cost/proc/measure(label, type, payload)
	var/n = 200
	var/native
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		native = dq_test_tgui_encode(type, payload)
	var/native_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/column
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		var/inner = dq_test_tgui_encode(type, payload)
		column = dq_test_tgui_encode("col/msg", list("wid" = "tgui-window-3", "raw" = inner))
	var/column_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_ASSERT(length(column) > length(native), "the column message wraps the native one")
	TEST_NOTICE(src, "COLUMN_SEND_COST [label]: native window [length(native)] bytes [round(native_ms * 1000, 0.1)] us; docked in the column [length(column)] bytes ([round(length(column) / length(native), 0.01)]x) [round(column_ms * 1000, 0.1)] us ([round(column_ms / max(native_ms, 0.0001), 0.01)]x)")
