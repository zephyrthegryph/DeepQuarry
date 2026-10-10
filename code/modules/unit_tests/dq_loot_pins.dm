/**
 * Loot and map-resolver pins (doc/rewrite/proposals/loot_and_map_resolvers.md, section 4): recorded on the code before the declarations
 * moved into CAPABILITIES entries and kept byte-identical through every wave after it.
 *
 *   dq_loot_roll_pin    every declaration of snapshots/loot/owners.txt x 20 fixed seeds x 50 rolls through loot_spawn(): the sorted
 *                       types each (declaration, seed) made, with counts. Exhaustive tier; /representative is the normal-tier subset.
 *   dq_loot_search_pin  every loot pile and trash pile x seeds x a run of searches through loot_search(): what each search left, said and
 *                       did (a pile gone, a creature out), with the global rng reseeded per run.
 *   dq_resolver_reader_pin  a fixture template holding every map-resolver type, loaded through the map reader: what is left on each tile.
 *
 * The rows are text, one file each under code/modules/unit_tests/snapshots/loot/ (key => value). An empty or missing file is recorded by
 * the next run; `bash tools/dq_focused_test.sh --bless <test>` rewrites it; a mismatch lists every differing key and writes the current
 * rows to data/test-snapshots/loot/. Record on one unsharded world: a sharded run only checks its own slice.
 */
#define DQ_LOOT_PIN_DIR "code/modules/unit_tests/snapshots/loot/"
#define DQ_LOOT_PIN_SEEDS 20
#define DQ_LOOT_PIN_ROLLS 50
#define DQ_LOOT_PIN_SEARCH_SEEDS 6

/// The declarations the roll pin covers, as they are written (owners.txt: one path per line).
/proc/dq_loot_pin_owners()
	return dq_snapshot_file_rows("[DQ_LOOT_PIN_DIR]owners.txt")

/// The seed of the k-th pinned round: spread over the seed space, below LOOT_HASH_MOD.
/proc/dq_loot_pin_seed(k)
	return k * 26107 + 11

/// What loot_spawn() takes for an owner written as text.
/proc/dq_loot_pin_ref(owner)
	return text2path(owner)

/// A pin file's rows as key => value.
/proc/dq_loot_pin_read(name)
	. = list()
	for(var/line in dq_snapshot_file_rows("[DQ_LOOT_PIN_DIR][name].txt"))
		var/at = findtext(line, " => ")
		if(!at)
			continue
		.[copytext(line, 1, at)] = copytext(line, at + 4)

/// Writes key => value rows over a pin file (under `dir`).
/proc/dq_loot_pin_write(dir, name, list/rows)
	var/file_name = "[dir][name].txt"
	fdel(file_name)
	var/list/lines = list()
	for(var/key in rows)
		lines += "[key] => [rows[key]]"
	text2file("[jointext(lines, "\n")]\n", file_name)

/**
 * Compares the rows a run made (key => value) with the recorded file: null when they agree, else the report. Only the keys the run made are
 * checked, so a subset run (the representative, a part, a shard) compares its own rows. A missing or empty file is recorded instead; a part of a sweep
 * (`part`) records into its own data/test-snapshots/loot/<name>.part<k>.txt, and the parts are merged into the pin file by hand (cat | sort).
 */
/proc/dq_loot_pin_compare(name, list/rows, part = null)
	var/list/expected = dq_loot_pin_read(name)
	if(!length(expected) && part)
		dq_loot_pin_write("data/test-snapshots/loot/", "[name].part[part]", rows)
		log_test("loot pin [name]: part [part] wrote [length(rows)] row(s) to data/test-snapshots/loot/[name].part[part].txt")
		return null
	if(dq_snapshot_blessing() || !length(expected))
		var/list/merged = dq_snapshot_blessing() ? expected : list()
		for(var/key in rows)
			merged[key] = rows[key]
		var/list/ordered = list()
		for(var/key in merged)
			ordered += key
		sortTim(ordered, GLOBAL_PROC_REF(cmp_text_asc))
		var/list/sorted = list()
		for(var/key in ordered)
			sorted[key] = merged[key]
		dq_loot_pin_write(DQ_LOOT_PIN_DIR, name, sorted)
		log_test("loot pin [name]: recorded [length(rows)] row(s)")
		return null
	var/list/problems = list()
	for(var/key in rows)
		if(isnull(expected[key]))
			problems += "new: [key] => [copytext(rows[key], 1, 300)]"
		else if(expected[key] != rows[key])
			problems += "changed: [key]\n   was: [copytext(expected[key], 1, 300)]\n   now: [copytext(rows[key], 1, 300)]"
	if(!length(problems))
		return null
	dq_loot_pin_write("data/test-snapshots/loot/", name, rows)
	var/report = "[length(problems)] loot pin row(s) of [name] differ (current rows in data/test-snapshots/loot/[name].txt):"
	var/shown = 0
	for(var/problem in problems)
		report += "\n[problem]"
		if(++shown >= 40)
			report += "\n... and [length(problems) - shown] more"
			break
	return report

// ---- the roll pin ----

/datum/unit_test/dq_loot_roll_pin
	tier = TEST_TIER_EXHAUSTIVE
	is_sweep_test = TRUE
	/// 1 to 4: this run rolls every fourth declaration (the four parts run in four worlds at once); 0: all of them.
	var/part = 0

/// The declarations this run rolls.
/datum/unit_test/dq_loot_roll_pin/proc/pin_owners()
	if(part)
		return dq_loot_pin_part(part)
	return sweep_types(dq_loot_pin_owners())

/// Every fourth declaration, starting at the part's own: the parts cost about the same.
/proc/dq_loot_pin_part(part)
	. = list()
	var/list/owners = dq_loot_pin_owners()
	for(var/i in 1 to length(owners))
		if(((i - 1) % 4) == part - 1)
			. += owners[i]

/// How many of the pinned seeds this run rolls.
/datum/unit_test/dq_loot_roll_pin/proc/pin_seed_count()
	return DQ_LOOT_PIN_SEEDS

/// The tile the rolls are made on: inside the test room, away from the corners the test block remembers (a turf-changing table swaps it).
/datum/unit_test/dq_loot_roll_pin/proc/pin_turf()
	var/turf/corner = test_floor()
	return locate(corner.x + 2, corner.y + 2, corner.z)

/datum/unit_test/dq_loot_roll_pin/Run()
	var/turf/T = pin_turf()
	var/turf_type = T.type
	var/list/rows = list()
	var/saved_seed = GLOB.loot_seed
	var/saved_serial = GLOB.loot_roll_serial
	var/list/owners = pin_owners()
	var/started = REALTIMEOFDAY
	var/done = 0
	for(var/owner in owners)
		var/ref = dq_loot_pin_ref(owner)
		if(!ref)
			TEST_FAIL("[owner] names no type")
			continue
		log_test("loot roll pin: [++done]/[length(owners)] [owner] ([round((REALTIMEOFDAY - started) / 10)] s)")
		for(var/k in 1 to pin_seed_count())
			var/seed_started = REALTIMEOFDAY
			var/seed = dq_loot_pin_seed(k)
			rand_seed(dq_test_seed_for("[owner][seed]"))
			GLOB.loot_seed = seed
			GLOB.loot_roll_serial = 0
			var/datum/loot_decl/decl = loot_decl_for(ref)
			if(decl)
				decl.round_picks = null
			var/list/counts = list()
			var/nothing = 0
			for(var/roll in 1 to DQ_LOOT_PIN_ROLLS)
				var/list/before = contents_of(T).Copy()
				var/list/made = loot_spawn(ref, T)
				var/made_any = FALSE
				for(var/atom/A in made)
					made_any = TRUE
					counts["[A.type]"]++
				if(!made_any)
					nothing++
				for(var/atom/movable/AM as anything in contents_of(T))
					if(!(AM in before) && !QDELETED(AM))
						qdel(AM)
				for(var/atom/A in made)
					if(!isturf(A) && !QDELETED(A))
						qdel(A)
				if(T.type != turf_type)
					T = T.ChangeTurf(turf_type, 1, 1, FALSE)
			var/list/types = list()
			for(var/type in counts)
				types += type
			sortTim(types, GLOBAL_PROC_REF(cmp_text_asc))
			var/list/parts = list()
			if(nothing)
				parts += "nothing x[nothing]"
			for(var/type in types)
				parts += "[type] x[counts[type]]"
			rows["[owner] | seed [seed]"] = jointext(parts, ", ")
			if(REALTIMEOFDAY - seed_started > 10 SECONDS)
				log_test("loot roll pin: [owner] seed [k] took [round((REALTIMEOFDAY - seed_started) / 10)] s")
			CHECK_TICK
	GLOB.loot_seed = saved_seed
	GLOB.loot_roll_serial = saved_serial
	own_turf_contents(T)
	for(var/obj/effect/decal/cleanable/mess in range(4, T))
		qdel(mess) // footprints and the like the rolled things left on the room's floor
	var/report = dq_loot_pin_compare("rolls", rows, part)
	TEST_ASSERT(isnull(report), report)

/datum/unit_test/dq_loot_roll_pin/part_1
	part = 1
	is_sweep_test = FALSE

/datum/unit_test/dq_loot_roll_pin/part_2
	part = 2
	is_sweep_test = FALSE

/datum/unit_test/dq_loot_roll_pin/part_3
	part = 3
	is_sweep_test = FALSE

/datum/unit_test/dq_loot_roll_pin/part_4
	part = 4
	is_sweep_test = FALSE

/// The declarations a wave touched, listed one per line in data/loot_pin_subset.txt (`python tools/codemods/declare_loot.py --wave-owners` writes it): a
/// wave is proven on the rows of its own declarations and of the ones that nest them; the whole sweep (the four parts) on the last wave and at the lane's end.
/datum/unit_test/dq_loot_roll_pin/subset
	is_sweep_test = FALSE

/datum/unit_test/dq_loot_roll_pin/subset/pin_owners()
	. = list()
	for(var/line in dq_snapshot_file_rows("data/loot_pin_subset.txt"))
		. += line
	if(!length(.))
		TEST_FAIL("data/loot_pin_subset.txt names no declaration")

/// Normal tier: a spread of declarations (a spawner, a themed per-round one, a hooked one, a landmark, a pure table, a turf table) on three seeds.
/datum/unit_test/dq_loot_roll_pin/representative
	tier = TEST_TIER_NORMAL
	is_sweep_test = FALSE

/datum/unit_test/dq_loot_roll_pin/representative/pin_owners()
	var/list/wanted = list("/obj/random/toolbox", "/obj/random/mob", "/obj/random/mob/semirandom_mob_spawner/animal", "/obj/random/junk",
		"/obj/random/turf", "/obj/effect/landmark/costume/scratch", "/loot/maint/junk", "/loot/mecha/ripley", "/obj/random/maintenance")
	var/list/kept = list()
	for(var/owner in dq_loot_pin_owners())
		if(owner in wanted)
			kept += owner
	return kept

/datum/unit_test/dq_loot_roll_pin/representative/pin_seed_count()
	return 3

// ---- the search pin ----

/datum/unit_test/dq_loot_search_pin
	tier = TEST_TIER_EXHAUSTIVE

/// The pile types the pin searches: every loot pile and trash pile that names a table.
/proc/dq_loot_pin_piles()
	. = list()
	for(var/type in typesof(/obj/structure/loot_pile) | typesof(/obj/structure/trash_pile))
		if(loot_search_table(type))
			. += "[type]"
	sortTim(., GLOBAL_PROC_REF(cmp_text_asc))

/// One search of `pile` by `searcher` under the pin's rules; the row text of what it did.
/datum/unit_test/dq_loot_search_pin/proc/pin_search(obj/structure/pile, mob/living/carbon/human/searcher, turf/T)
	test_chat_clear()
	var/list/before = contents_of(T).Copy()
	// The op's requirements refuse before the wait (dq_loot_search_op tests drive the op); here the refusal is the same message the requirement gives.
	var/refusal = loot_search_refusal(pile, searcher)
	if(refusal)
		act_message_t(searcher, pile, refusal)
	else
		loot_search_roll(pile, searcher)
	var/list/gained = list()
	for(var/atom/movable/AM as anything in contents_of(T))
		if(AM in before)
			continue
		gained += "[AM.type]"
		if(!QDELETED(AM))
			qdel(AM)
	sortTim(gained, GLOBAL_PROC_REF(cmp_text_asc))
	var/list/said = test_chat_of(searcher).Copy()
	return "[length(gained) ? jointext(gained, ",") : "nothing"] | said: [jointext(said, " / ")][QDELETED(pile) ? " | pile gone" : ""]"

/datum/unit_test/dq_loot_search_pin/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/list/rows = list()
	var/saved_seed = GLOB.loot_seed
	var/saved_serial = GLOB.loot_roll_serial
	var/list/saved_pool = GLOB.unique_gamma_loot
	GLOB.unique_gamma_loot = list() // the pool's unique items are world state: the gamma tier falls through to the rare one with it empty
	var/mob/living/carbon/human/searcher = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/unlucky = allocate(/mob/living/carbon/human, T)
	add_trait(unlucky, TRAIT_UNLUCKY, "loot_pin")
	for(var/pile_text in dq_loot_pin_piles())
		var/pile_type = text2path(pile_text)
		for(var/k in 1 to DQ_LOOT_PIN_SEARCH_SEEDS)
			var/seed = dq_loot_pin_seed(k)
			rand_seed(dq_test_seed_for("[pile_text][seed]"))
			GLOB.loot_seed = seed
			GLOB.loot_roll_serial = 0
			var/list/steps = list()
			var/obj/structure/pile = new pile_type(T)
			var/total = 8
			for(var/i in 1 to total)
				if(QDELETED(pile))
					break
				searcher.ckey = "pinsearcher[i]"
				steps += "search [i]: [pin_search(pile, searcher, T)]"
			if(!QDELETED(pile))
				searcher.ckey = "pinsearcher1"
				steps += "again by 1: [pin_search(pile, searcher, T)]"
				unlucky.ckey = "pinunlucky"
				steps += "unlucky: [pin_search(pile, unlucky, T)]"
				qdel(pile)
			rows["[pile_text] | seed [seed]"] = jointext(steps, " || ")
			CHECK_TICK
	searcher.ckey = null
	unlucky.ckey = null
	GLOB.unique_gamma_loot = saved_pool
	GLOB.loot_seed = saved_seed
	GLOB.loot_roll_serial = saved_serial
	own_turf_contents(T)
	test_driver_end()
	var/report = dq_loot_pin_compare("search", rows)
	TEST_ASSERT(isnull(report), report)

// ---- the map-resolver pins ----

/// The resolver proc of an atom type, as text ("" when it has none). The one place the pin reads how a type names its resolver.
/proc/dq_resolver_pin_proc(type)
	return "[map_resolver_proc(type)]"

/// The vars its resolver reads besides the common ones, ";"-joined, in the order they were written.
/proc/dq_resolver_pin_vars(type)
	return jointext(map_resolver_vars_of(type), ";")

/// Every atom type that resolves at map time: its resolver and the vars it reads. Inheritance is resolved for every subtype of every resolver type.
/datum/unit_test/dq_resolver_table_pin

/datum/unit_test/dq_resolver_table_pin/Run()
	var/list/rows = list()
	for(var/type in typesof(/atom))
		var/resolver = dq_resolver_pin_proc(type)
		if(!resolver)
			continue
		rows["[type]"] = "[resolver] | vars: [dq_resolver_pin_vars(type)]"
	TEST_ASSERT(length(rows) > 100, "the resolvers were found")
	var/report = dq_loot_pin_compare("resolver_table", rows)
	TEST_ASSERT(isnull(report), report)

/// A fixture template holding the resolver types (resolver_fixture.dmm; the tile of each is resolver_fixture_tiles.txt), loaded through the map
/// reader on a z-level of its own: what is left on and around each tile, and what the resolvers registered. Not in the fixture: the stairs spawner
/// (it needs a level above) and the turbolift holder (it needs a list var edit); the table pin above covers them.
/datum/unit_test/dq_resolver_reader_pin

/datum/unit_test/dq_resolver_reader_pin/Run()
	var/saved_seed = GLOB.loot_seed
	var/saved_serial = GLOB.loot_roll_serial
	GLOB.loot_seed = dq_loot_pin_seed(7) // a map-time roll depends on the round seed, the position and the type: pin the seed
	GLOB.loot_roll_serial = 0 // a roll made after the world's own map load also depends on how many rolls came before it: start the count at zero
	rand_seed(dq_test_seed_for("resolver reader pin")) // gibs and the like draw from the world's generator: whatever ran before must not matter
	var/z = world.increment_max_z()
	var/datum/map_template/template = new("[DQ_LOOT_PIN_DIR]resolver_fixture.dmm")
	TEST_ASSERT(template.load(locate(1, 1, z)), "the fixture loads")
	var/list/rows = list()
	for(var/line in dq_snapshot_file_rows("[DQ_LOOT_PIN_DIR]resolver_fixture_tiles.txt"))
		var/list/parts = splittext(line, " ")
		var/x = text2num(parts[1])
		var/y = text2num(parts[2])
		var/type = parts[3]
		var/edits = length(parts) > 3 ? jointext(parts.Copy(4), " ") : ""
		var/turf/center = locate(x, y, z)
		var/list/found = list()
		for(var/turf/near in range(1, center))
			for(var/atom/movable/AM as anything in contents_of(near))
				found += "[near.x - x],[near.y - y] [AM.type]"
		sortTim(found, GLOBAL_PROC_REF(cmp_text_asc))
		// Rolled outcomes: whether a hole opens and how many gibs land follow the rng, and other work in the world draws from it while the fixture loads, so
		// the row records what can appear, not what this load rolled.
		if(type == "/obj/effect/mouse_hole_spawner")
			found -= "0,0 /obj/structure/micro_tunnel"
		else if(findtext(type, "/obj/effect/gibspawner/") == 1)
			var/list/distinct = list()
			for(var/entry in found)
				distinct |= entry
			found = distinct
		var/decals = 0
		if(istype(center, /turf/simulated/floor))
			var/turf/simulated/floor/F = center
			decals = LAZYLEN(F.decals)
		rows["[type][edits ? " {[edits]}" : ""]"] = "turf [center.type] | decals [decals] | [length(found) ? jointext(found, ", ") : "nothing"]"
	var/blobstart = 0
	for(var/turf/T in GLOB.blobstart)
		if(T.z == z)
			blobstart++
	var/recycler = 0
	for(var/turf/T in GLOB.recycler_locations)
		if(T.z == z)
			recycler++
	rows["registries"] = "blobstart [blobstart] | recycler [recycler] | multi_point dq_pin [length(GLOB.multi_point_spawns["dq_pin"])]"
	// Take everything the fixture left back out.
	for(var/turf/T as anything in block(locate(1, 1, z), locate(width_of_fixture(), height_of_fixture(), z)))
		for(var/atom/movable/AM as anything in contents_of(T))
			if(!QDELETED(AM))
				qdel(AM)
		GLOB.blobstart -= T
		GLOB.recycler_locations -= T
	GLOB.multi_point_spawns -= "dq_pin"
	GLOB.loot_seed = saved_seed
	GLOB.loot_roll_serial = saved_serial
	var/report = dq_loot_pin_compare("resolver_reader", rows)
	TEST_ASSERT(isnull(report), report)

/datum/unit_test/dq_resolver_reader_pin/proc/width_of_fixture()
	return 24

/datum/unit_test/dq_resolver_reader_pin/proc/height_of_fixture()
	return 15
