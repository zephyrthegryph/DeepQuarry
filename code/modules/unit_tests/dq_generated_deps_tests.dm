// Generated dependencies (code/engine/_generated/deps.dm, `analyze gen deps`; doc/rewrite/final_api.html section 5 "Caching" and section 7
// "Generated reads"): what each stat input and draw reads, which of those reads nothing publishes, and what the runtime does with it. A stat whose
// inputs are all tracked caches its value on first read and is rewritten when an input publishes; a stat with an untracked input is composed on
// every read; an exact type's draw follows every var its draw() reads.

/// A stat fixture: gdeps_low reads a tracked var through a holder proc, gdeps_raw names an untracked var as its value.
/obj/gdeps_probe
	name = "generated deps probe"
	var/gauge = 0
	/// Untracked on purpose: break_raw() writes it with no setter, so nothing publishes it.
	var/raw_ok = TRUE


STAT(/obj/gdeps_probe, gdeps_low, ALL, virtual = TRUE)
STAT(/obj/gdeps_probe, gdeps_raw, ALL, virtual = TRUE)

CAPABILITIES(/obj/gdeps_probe)
	contributes(STAT_GDEPS_LOW, PROC_REF(level_low))
	contributes(STAT_GDEPS_RAW, nameof(raw_ok))

/obj/gdeps_probe/proc/level_low(datum/act/A)
	return gauge < 5

/obj/gdeps_probe/proc/break_raw()
	raw_ok = FALSE

/// A draw fixture: an exact type (it declares a derived() entry) whose draw reads a var its derived() does not list.
/obj/gdeps_lamp
	name = "generated deps lamp"
	var/glow_level = 0


/obj/gdeps_lamp/derived()
	. = ..()
	. += ui_from(nameof(name))

/obj/gdeps_lamp/draw(datum/look/look)
	. = ..()
	look.state("lamp-[glow_level]")

/// The generated tables say what the fixtures and a real machine read.
/datum/unit_test/dq_generated_deps_tables

/datum/unit_test/dq_generated_deps_tables/Run()
	var/list/reads = GLOB.generated_reads_table["/obj/gdeps_probe::level_low"]
	TEST_ASSERT(islist(reads), "the reads table has the probe's contribution proc")
	var/list/keys = list()
	for(var/i in 2 to length(reads))
		var/list/read = reads[i]
		keys += GLOB.generated_read_names[read[3]]
	TEST_ASSERT_EQUAL(jointext(keys, ","), "gauge", "level_low reads exactly gauge")
	TEST_ASSERT(!GLOB.generated_untracked_reads["/obj/gdeps_probe::level_low"], "level_low reads only tracked state")
	var/list/leaves = GLOB.generated_untracked_leaves["/obj/gdeps_probe"]
	TEST_ASSERT(islist(leaves) && ("raw_ok" in leaves) && !("gauge" in leaves), "the untracked leaf is raw_ok alone: [json_encode(leaves)]")
	var/list/drawn = GLOB.generated_draw_reads["/obj/gdeps_lamp"]
	TEST_ASSERT(islist(drawn) && ("glow_level" in drawn), "the lamp's draw reads glow_level: [json_encode(drawn)]")
	// A real stat input: the machine's area power read follows its area's channel vars through power_area, all of them published.
	var/list/area_power = GLOB.generated_reads_table["/obj/machinery::area_gives_power"]
	var/list/hops = list()
	for(var/i in 2 to length(area_power))
		var/list/read = area_power[i]
		if(length(read) > 3)
			hops += "[GLOB.generated_read_names[read[4]]].[GLOB.generated_read_names[read[3]]]"
	TEST_ASSERT(("power_area.power_equip" in hops) && ("power_area.requires_power" in hops), "area_gives_power reads the area's channels: [json_encode(hops)]")
	TEST_ASSERT(!GLOB.generated_untracked_reads["/obj/machinery::area_gives_power"], "area_gives_power reads only tracked state")

/// A stat whose inputs are tracked is composed once, then read from its cache until an input publishes.
/datum/unit_test/dq_generated_deps_cache

/datum/unit_test/dq_generated_deps_cache/Run()
	var/obj/gdeps_probe/P = allocate(/obj/gdeps_probe)
	var/datum/stat_type_info/I = stat_type_of(P)
	TEST_ASSERT(istype(I), "the probe has stat info")
	TEST_ASSERT(stat_inputs_tracked(I, stat_def_of(STAT_GDEPS_LOW)), "gdeps_low's inputs are tracked: [json_encode(I.untracked)]")
	TEST_ASSERT_EQUAL(stat_value(P, STAT_GDEPS_LOW), TRUE, "gauge 0 is low")
	var/computes = GLOB.stat_read_computes
	for(var/i in 1 to 5)
		TEST_ASSERT_EQUAL(stat_value(P, STAT_GDEPS_LOW), TRUE, "a cached read is right")
	TEST_ASSERT_EQUAL(GLOB.stat_read_computes, computes, "five reads of a cached stat compose nothing")
	P.set_gauge(9)
	TEST_ASSERT_EQUAL(stat_value(P, STAT_GDEPS_LOW), FALSE, "changing the tracked input invalidates the cached value before the next line")
	P.set_gauge(1)
	TEST_ASSERT_EQUAL(stat_value(P, STAT_GDEPS_LOW), TRUE, "and back")
	TEST_ASSERT_EQUAL(GLOB.stat_read_computes, computes, "the input change recomputed it; the reads still compose nothing")

/// A stat with an untracked input is not cached: it is composed on every read, so a write nothing publishes still shows.
/datum/unit_test/dq_generated_deps_untracked_not_cached

/datum/unit_test/dq_generated_deps_untracked_not_cached/Run()
	var/obj/gdeps_probe/P = allocate(/obj/gdeps_probe)
	var/datum/stat_type_info/I = stat_type_of(P)
	TEST_ASSERT(!stat_inputs_tracked(I, stat_def_of(STAT_GDEPS_RAW)), "gdeps_raw reads an untracked var")
	TEST_ASSERT(("raw_ok" in I.untracked?["[STAT_GDEPS_RAW]"]), "the type records what it cannot see: [json_encode(I.untracked)]")
	TEST_ASSERT_EQUAL(stat_value(P, STAT_GDEPS_RAW), TRUE, "raw_ok starts TRUE")
	var/computes = GLOB.stat_read_computes
	stat_value(P, STAT_GDEPS_RAW)
	TEST_ASSERT_EQUAL(GLOB.stat_read_computes, computes + 1, "every read of an untracked stat composes it")
	P.break_raw()
	TEST_ASSERT_EQUAL(stat_value(P, STAT_GDEPS_RAW), FALSE, "a write nothing published still shows: the stat was never cached")

/// An exact type's draw follows every var its generated draw reads name, though derived() lists none of them.
/datum/unit_test/dq_generated_deps_draw

/datum/unit_test/dq_generated_deps_draw/Run()
	var/obj/gdeps_lamp/L = allocate(/obj/gdeps_lamp)
	var/datum/derived_table/T = derived_table_of(L)
	TEST_ASSERT(istype(T), "the lamp is an exact type")
	TEST_ASSERT(T.by_var["glow_level"] & DEP_DRAW, "a write of glow_level redraws the lamp")
	TEST_ASSERT(derived_mask(L, "glow_level") & DEP_DRAW, "derived_mask() says so too")

/// The machines that dominated idle stat reads cache their power and operable stats.
/datum/unit_test/dq_generated_deps_machines

/datum/unit_test/dq_generated_deps_machines/Run()
	for(var/path in list(/obj/machinery/door/airlock/external, /obj/machinery/atmospherics/unary/vent_pump/high_volume, /obj/machinery/alarm))
		var/obj/machinery/M = allocate(path)
		var/datum/stat_type_info/I = stat_type_of(M)
		for(var/id in list(STAT_HAS_POWER, STAT_INTACT, STAT_IN_MAINTENANCE, STAT_OPERABLE))
			var/datum/stat_def/def = stat_def_of(id)
			TEST_ASSERT(stat_inputs_tracked(I, def), "[path] [def.name] has tracked inputs: [json_encode(I?.untracked?[def.skey])]")
			stat_value(M, id)
			var/computes = GLOB.stat_read_computes
			stat_value(M, id)
			TEST_ASSERT_EQUAL(GLOB.stat_read_computes, computes, "[path] [def.name] is read from its cache")
