// The server cost of a message to a window docked in the right-hand column (column_part.dm) against the same message to a native window.
// A column window's message is one `col/msg {wid, type, payload}` envelope with the payload JSON nested, encoded once (encode_message());
// it used to be the native message wrapped as `col/msg {wid, raw}` and encoded again, which the "old column" figure keeps for comparison.
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
	var/datum/tgui_window/native_window = new(null, "dq-cost-native")
	var/datum/tgui_window/column_part/part = new(null, "tgui-window-3")
	var/native
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		var/json = json_encode(payload)
		findtext(json, HREF_TOKEN_PLACEHOLDER)
		native = native_window.encode_message(type, json)
	var/native_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/column
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		var/json = json_encode(payload)
		findtext(json, HREF_TOKEN_PLACEHOLDER)
		column = part.encode_message(type, json)
	var/column_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/old_column
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		var/inner = dq_test_tgui_encode(type, payload)
		old_column = dq_test_tgui_encode("col/msg", list("wid" = "tgui-window-3", "raw" = inner))
	var/old_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	// The envelope is what the page reads: col/msg for the window's id, carrying the message itself.
	var/list/decoded = json_decode(url_decode(column))
	TEST_ASSERT_EQUAL(decoded["type"], "col/msg", "a column message is the panel page's col/msg")
	TEST_ASSERT_EQUAL(decoded["payload"]["wid"], "tgui-window-3", "for its window")
	TEST_ASSERT_EQUAL(decoded["payload"]["type"], type, "with the message's own type")
	TEST_ASSERT_EQUAL(json_encode(decoded["payload"]["payload"]), json_encode(payload), "and its payload, nested, not encoded again")
	TEST_ASSERT(findtext(column, COLUMN_ENVELOPE_HEAD) == 1, "the page-bound string starts with the envelope head deliver() looks for")
	TEST_ASSERT(length(column) < length(old_column), "one envelope is smaller than a wrapped native message")
	TEST_NOTICE(src, "COLUMN_SEND_COST [label]: native window [length(native)] bytes [round(native_ms * 1000, 0.1)] us; docked in the column [length(column)] bytes ([round(length(column) / length(native), 0.01)]x) [round(column_ms * 1000, 0.1)] us ([round(column_ms / max(native_ms, 0.0001), 0.01)]x); old double-encoded column [length(old_column)] bytes [round(old_ms * 1000, 0.1)] us")
	qdel(part)
	qdel(native_window)
