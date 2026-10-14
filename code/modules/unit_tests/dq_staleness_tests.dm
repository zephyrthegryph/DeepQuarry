// The staleness checker (code/engine/change/staleness.dm; doc/rewrite/final_api.html section 7, "The staleness checker"): a cached stat, an applied
// draw, a derive() value or a keyed image is recomputed from scratch and compared. Each test below writes an input RAW (a plain assignment, no
// setter, so nothing publishes) and proves the checker names it. A test that provokes a report on purpose sets GLOB.staleness_expected, so the report
// is recorded but does not fail the test; the flag ends with the test.

/// A stat fixture: stale_low and stale_open follow `gauge` (tracked) through a holder proc. stale_open is a var-backed stat, stale_low is virtual.
/obj/stale_probe
	name = "stale probe"
	var/gauge = 0
	var/stale_open = TRUE

TRACKED(/obj/stale_probe, gauge)

STAT(/obj/stale_probe, stale_low, ALL, virtual = TRUE)
STAT(/obj/stale_probe, stale_open, ALL)

CAPABILITIES(/obj/stale_probe)
	contributes(STAT_STALE_LOW, PROC_REF(level_low))
	contributes(STAT_STALE_OPEN, PROC_REF(level_low))

/obj/stale_probe/proc/level_low(datum/act/A)
	return gauge < 5

/// A raw write: no setter, so no publish.
/obj/stale_probe/proc/raw_gauge(value)
	vars["gauge"] = value

/// A draw fixture: an exact type whose draw reads `glow` and, by a route the read walker does not follow, `noise`.
/obj/stale_lamp
	name = "stale lamp"
	var/glow = 0
	var/noise = 0

TRACKED(/obj/stale_lamp, glow)
TRACKED(/obj/stale_lamp, noise)

/obj/stale_lamp/derived()
	. = ..()
	. += ui_from(nameof(name))

/obj/stale_lamp/draw(datum/look/look)
	. = ..()
	look.state("lamp-[glow]-[vars["noise"]]")

/obj/stale_lamp/proc/raw_glow(value)
	vars["glow"] = value

/// The reports filed after index `since` (the length of GLOB.staleness_reports before the step under test).
/proc/staleness_test_reports_since(since)
	. = list()
	for(var/i in since + 1 to length(GLOB.staleness_reports))
		. += GLOB.staleness_reports[i]

/// A cached stat read after a raw write of its input is reported, and the report names the var that moved.
/datum/unit_test/dq_staleness_stat_read_catches_raw_write
	boot_needs = list()

/datum/unit_test/dq_staleness_stat_read_catches_raw_write/Run()
	GLOB.staleness_expected = TRUE
	var/obj/stale_probe/P = allocate(/obj/stale_probe)
	TEST_ASSERT_EQUAL(stat_value(P, STAT_STALE_LOW), TRUE, "gauge 0 is low")
	var/since = length(GLOB.staleness_reports)
	P.raw_gauge(9)
	stat_value(P, STAT_STALE_LOW)
	var/list/found = staleness_test_reports_since(since)
	TEST_ASSERT_EQUAL(length(found), 1, "one report for the stale read: [json_encode(found)]")
	var/report = found[1]
	TEST_ASSERT(findtext(report, "STALE stat: /obj/stale_probe stale_low"), "the report names the type and the stat: [report]")
	TEST_ASSERT(findtext(report, "gauge (0 -> 9)"), "the report names the var that changed without publishing: [report]")
	TEST_ASSERT(findtext(report, "stat_value"), "the report names the trigger and the read path: [report]")

/// The same write through the setter publishes first: the read is right and nothing is reported.
/datum/unit_test/dq_staleness_setter_write_is_clean
	boot_needs = list()

/datum/unit_test/dq_staleness_setter_write_is_clean/Run()
	var/obj/stale_probe/P = allocate(/obj/stale_probe)
	var/since = length(GLOB.staleness_reports)
	var/checks = GLOB.staleness_checks
	TEST_ASSERT_EQUAL(stat_value(P, STAT_STALE_LOW), TRUE, "gauge 0 is low")
	P.set_gauge(9)
	TEST_ASSERT_EQUAL(stat_value(P, STAT_STALE_LOW), FALSE, "the setter recomputed the stat")
	TEST_ASSERT_EQUAL(P.stale_open, FALSE, "and the var-backed stat")
	P.set_gauge(1)
	TEST_ASSERT_EQUAL(stat_value(P, STAT_STALE_LOW), TRUE, "and back")
	TEST_ASSERT(GLOB.staleness_checks > checks, "the reads were checked")
	TEST_ASSERT_EQUAL(length(staleness_test_reports_since(since)), 0, "no report: [json_encode(staleness_test_reports_since(since))]")
	staleness_check_entity(P, "test")
	TEST_ASSERT_EQUAL(length(staleness_test_reports_since(since)), 0, "and neither does the sweep of it: [json_encode(staleness_test_reports_since(since))]")

/// A stat var read directly (no proc to hook) is found by the sweep.
/datum/unit_test/dq_staleness_sweep_catches_stat_var
	boot_needs = list()

/datum/unit_test/dq_staleness_sweep_catches_stat_var/Run()
	GLOB.staleness_expected = TRUE
	var/obj/stale_probe/P = allocate(/obj/stale_probe)
	TEST_ASSERT_EQUAL(P.stale_open, TRUE, "stale_open starts true")
	staleness_check_entity(P, "test")
	var/since = length(GLOB.staleness_reports)
	P.raw_gauge(9)
	TEST_ASSERT_EQUAL(P.stale_open, TRUE, "the raw write left the var as it was: that is the staleness")
	staleness_check_entity(P, "test")
	var/list/found = staleness_test_reports_since(since)
	TEST_ASSERT(length(found) >= 1, "the sweep reports the stale var")
	var/report = ""
	for(var/text in found)
		if(findtext(text, "STALE stat: /obj/stale_probe stale_open"))
			report = text
	TEST_ASSERT(length(report), "the var-backed stat is reported: [json_encode(found)]")
	TEST_ASSERT(findtext(report, "gauge (0 -> 9)"), "with the var that moved: [report]")

/// An applied draw checked after a raw write of a var it reads is reported with that var.
/datum/unit_test/dq_staleness_draw_catches_raw_write
	boot_needs = list()

/datum/unit_test/dq_staleness_draw_catches_raw_write/Run()
	GLOB.staleness_expected = TRUE
	var/obj/stale_lamp/L = allocate(/obj/stale_lamp)
	refresh_flush()
	var/since = length(GLOB.staleness_reports)
	staleness_check_draw(L, "test", forced = TRUE)
	TEST_ASSERT_EQUAL(length(staleness_test_reports_since(since)), 0, "an untouched lamp draws what it shows: [json_encode(staleness_test_reports_since(since))]")
	L.raw_glow(3)
	staleness_check_draw(L, "test", forced = TRUE)
	var/list/found = staleness_test_reports_since(since)
	TEST_ASSERT_EQUAL(length(found), 1, "one report: [json_encode(found)]")
	TEST_ASSERT(findtext(found[1], "STALE draw: /obj/stale_lamp"), "the report names the type: [found[1]]")
	TEST_ASSERT(findtext(found[1], "glow (0 -> 3)"), "and the var: [found[1]]")

/// A tracked write the graph says no draw reads serves the cached look; the next sweep draws it dry, finds the difference and names the skipped var.
/datum/unit_test/dq_staleness_draw_served_from_cache
	boot_needs = list()

/datum/unit_test/dq_staleness_draw_served_from_cache/Run()
	GLOB.staleness_expected = TRUE
	var/obj/stale_lamp/L = allocate(/obj/stale_lamp)
	refresh_flush()
	var/since = length(GLOB.staleness_reports)
	L.set_noise(7)
	TEST_ASSERT(length(GLOB.staleness_served[REF(L)]), "the write was noted as served from cache")
	TEST_ASSERT(staleness_sweep("test", old_budget = 0) >= 1, "the sweep found the draw stale")
	var/list/found = staleness_test_reports_since(since)
	TEST_ASSERT(findtext(found[1], "none of: noise"), "the report names the written var the graph skipped: [found[1]]")

/// A keyed shared image whose key does not name what varies it is found on a hit.
/datum/unit_test/dq_staleness_image_key
	boot_needs = list()

/datum/unit_test/dq_staleness_image_key/Run()
	GLOB.staleness_expected = TRUE
	var/since = length(GLOB.staleness_reports)
	var/image/cached = image(null)
	var/image/same = image(null)
	staleness_check_image("same", cached, same)
	TEST_ASSERT_EQUAL(length(staleness_test_reports_since(since)), 0, "equal images are not reported")
	var/image/other = image(null)
	other.color = "#ff0000"
	staleness_check_image("tint", cached, other)
	var/list/found = staleness_test_reports_since(since)
	TEST_ASSERT_EQUAL(length(found), 1, "a different image is: [json_encode(found)]")
	TEST_ASSERT(findtext(found[1], "STALE image"), "the report says what it is: [found[1]]")

/// The sampled live mode only logs: a stale read is reported and the test is not failed.
/datum/unit_test/dq_staleness_sampled_mode_logs_only
	boot_needs = list()

/datum/unit_test/dq_staleness_sampled_mode_logs_only/Run()
	GLOB.staleness_expected = TRUE // the end-of-test sweep runs strict and finds the same stale probe
	var/obj/stale_probe/P = allocate(/obj/stale_probe)
	TEST_ASSERT_EQUAL(stat_value(P, STAT_STALE_LOW), TRUE, "gauge 0 is low")
	var/strict = GLOB.staleness_strict
	var/sample = GLOB.staleness_sample
	var/since = length(GLOB.staleness_reports)
	GLOB.staleness_strict = FALSE
	GLOB.staleness_sample = 1
	P.raw_gauge(9)
	stat_value(P, STAT_STALE_LOW)
	GLOB.staleness_strict = strict
	GLOB.staleness_sample = sample
	var/list/found = staleness_test_reports_since(since)
	TEST_ASSERT_EQUAL(length(found), 1, "one in one is every read: [json_encode(found)]")
	TEST_ASSERT(succeeded, "sampled mode logs; it does not fail the test")
	TEST_ASSERT(!findtext(found[1], "changed with no publish"), "and takes no snapshots, so it names the candidates only: [found[1]]")

/// The sampled mode is off by default: the config entry is 0.
/datum/unit_test/dq_staleness_sample_default_off
	boot_needs = list()

/datum/unit_test/dq_staleness_sample_default_off/Run()
	TEST_ASSERT_EQUAL(/datum/config_entry/number/staleness_sample::default, 0, "STALENESS_SAMPLE defaults to 0")
	TEST_ASSERT_EQUAL(GLOB.staleness_sample, 0, "so no one-in-N sampling runs in a test world")
	TEST_ASSERT(GLOB.staleness_strict, "test builds check everything")
