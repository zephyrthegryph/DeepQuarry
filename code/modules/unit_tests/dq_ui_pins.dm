/**
 * Window-data pins: a generated snapshot of what a window host shows (its ui_data output) after a scripted set of state changes,
 * recorded on the code as it is before a host's window conversion (hand update_uis() calls and changed() marks deleted, the state
 * it shows tracked) and checked after it. Guide: doc/rewrite/snapshot_pins.md ("Window data pins").
 *
 *   bash tools/dq_pin.sh --ui /datum/newscaster_panel      # before converting: make the empty pin file and record it
 *   ...convert...
 *   bash tools/dq_focused_test.sh dq_ui_data_pin            # after: what changed, row by row
 *
 * A pin is a /datum/ui_pin subtype in a dq_ui_pins_*.dm file: host_type names the host (its snapshot file is
 * snapshots/ui_pins/<type with / as .>.txt) and script() builds the host, then alternates mutations (the way the window's own buttons and
 * the world change what it shows) with snap("label") calls. Every snap() writes one row per top-level key of the host's tgui_data():
 *
 *   <label> | <key>: <json of the value>
 *
 * Refs ([0x...]) are written as [ref], keys are sorted, and a driver keeps clock readings, random values and anything else that
 * differs between runs out of the data it snaps (or out of the host it builds). script() must work with no client: the data is read
 * through tgui_data(user, null, state), the way the window reads it, and state changes go through the host's own handlers.
 */
#define DQ_UI_PIN_DIR "code/modules/unit_tests/snapshots/ui_pins/"

/// A window stand-in for the pins and the push tests: counts the pushes the framework delivers to it (no client, no browser).
/datum/tgui/dq_ui_probe
	var/pushes = 0

/datum/tgui/dq_ui_probe/New()
	return

/datum/tgui/dq_ui_probe/push_coalesced()
	pushes++
	return TRUE

/// One scripted host. Abstract; the subtypes live in dq_ui_pins_*.dm.
/datum/ui_pin
	/// The host's type: the pin's snapshot file.
	var/host_type
	var/datum/unit_test/test
	var/mob/living/carbon/human/user
	var/datum/host
	/// Window stand-in listening to the host (open_tguis), so a driver can count the pushes a step caused.
	var/datum/tgui/dq_ui_probe/probe
	var/list/rows = list()
	/// label -> the data of the step before it, to know whether a step changed what the window shows.
	var/list/last_data
	var/list/changed_steps = list()
	var/list/pushes_by_step = list()

/// Builds the host and drives it. `T` is a clean floor tile; `test` allocates what the driver makes.
/datum/ui_pin/proc/script(turf/T)
	return

/// Attaches the probe window to the host: from here on every snap() records the pushes the step before it caused.
/datum/ui_pin/proc/watch_host()
	probe = new
	LAZYADD(host.open_tguis, probe)

/// Writes the rows of the host's window data under `label`.
/datum/ui_pin/proc/snap(label)
	var/datum/tgui_state/state = GLOB.tgui_always_state
	var/list/data = host.tgui_data(user, null, state)
	if(!islist(data))
		rows += "[label] | <no data>"
		return
	var/list/keys = list()
	for(var/key in data)
		keys += "[key]"
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	var/list/now = list()
	for(var/key in keys)
		var/text = dq_ui_pin_text(data[key])
		rows += "[label] | [key]: [text]"
		now[key] = text
	var/changed = !isnull(last_data) && !dq_ui_pin_same(last_data, now)
	changed_steps[label] = changed
	pushes_by_step[label] = probe ? probe.pushes : null
	last_data = now

/// The text of one value of window data: JSON with refs and clock readings made stable.
/proc/dq_ui_pin_text(value)
	var/static/regex/ref_text = regex(@"\[0x[0-9a-fA-F]+\]", "g")
	var/text = json_encode(value)
	return ref_text.Replace(text, "\[ref\]")

/proc/dq_ui_pin_same(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/key in a)
		if(a[key] != b[key])
			return FALSE
	return TRUE

/// Makes the human who reads the window.
/datum/ui_pin/proc/make_user(turf/T)
	user = test.allocate(/mob/living/carbon/human, T)
	return user

/// The pin of `host_type`, or null.
/proc/dq_ui_pin_for(host_type)
	for(var/path in subtypesof(/datum/ui_pin))
		var/datum/ui_pin/P = path
		if(initial(P.host_type) == host_type)
			return path
	return null

/// Runs the driver of `host_type` and returns its pin (rows, per-step push counts), or null when no driver exists.
/datum/unit_test/proc/dq_ui_pin_run(host_type)
	var/path = dq_ui_pin_for(host_type)
	if(!path)
		return null
	var/datum/ui_pin/P = new path
	P.test = src
	rand_seed(dq_test_seed_for("[host_type]"))
	try
		P.script(test_floor())
	catch(var/exception/e)
		var/static/regex/where = regex(@"^\S+\.dm:\d+:")
		P.rows += "runtime: [where.Replace(e.name, "")]" // without the file and line, which move with unrelated edits
	return P

/datum/unit_test/dq_ui_data_pin

/datum/unit_test/dq_ui_data_pin/Run()
	var/list/bad = list()
	var/list/expected_by_type = dq_snapshot_read_dir(DQ_UI_PIN_DIR, bad)
	if(!length(expected_by_type) && !length(bad))
		return // no pins recorded
	var/list/actual_by_type = list()
	for(var/type in expected_by_type)
		var/datum/ui_pin/P = dq_ui_pin_run(type)
		if(!P)
			bad += "[replacetext(copytext("[type]", 2), "/", ".")].txt"
			continue
		actual_by_type[type] = P.rows
	var/report = dq_snapshot_compare(DQ_UI_PIN_DIR, "ui_pins", actual_by_type, expected_by_type, bad)
	TEST_ASSERT(isnull(report), report)

#undef DQ_UI_PIN_DIR
