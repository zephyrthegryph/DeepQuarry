// mapload_init: what Initialize() costs per atom on the map-load path, per representative type, without booting the full map.
//
// Each type is created with the atoms system in its queueing state (INITIALIZATION_INSSATOMS, what map load runs in), then initialized
// through InitializeAtoms() with the list (the same CreateAtoms/InitAtom path as boot, mapload TRUE). The first atom of a type is timed alone
// ("first": the type's one-time table builds when the type is cold) and the rest as one batch ("each": the steady per-atom cost).
// Boot cost scales with atoms x each + types x first, so a framework fix shows here in seconds instead of an 8 minute boot.
//
//   tools/build/build.sh bench --scenario=mapload_init [--arg count=200]

/// Representative map-load types: turfs, machinery, structures, items with contents, the heavy ones the Southern Cross profile named.
GLOBAL_LIST_INIT(mapload_init_bench_types, list(
	/turf/space,
	/turf/simulated/floor/tiled,
	/turf/simulated/floor/reinforced/airless,
	/turf/simulated/wall/r_wall,
	/obj/structure/window/reinforced,
	/obj/structure/disposalpipe/segment,
	/obj/structure/closet/secure_closet/security,
	/obj/machinery/atmospherics/pipe/simple/hidden/supply,
	/obj/machinery/atmospherics/pipe/simple/hidden/scrubbers,
	/obj/machinery/door/firedoor/border_only,
	/obj/machinery/door/firedoor/glass,
	/obj/machinery/light,
	/obj/machinery/power/apc,
	/obj/machinery/alarm,
	/obj/item/storage/mre/random,
))

/datum/benchmark/mapload_init
	id = "mapload_init"
	description = "Per-atom Initialize() cost on the map-load path for representative types: first instance and steady state"

/datum/benchmark/mapload_init/Run()
	var/count = param("count", 100)
	var/x = round(world.maxx / 2)
	var/y = round(world.maxy / 2)
	var/list/table = list()
	if(profiling)
		world.Profile(PROFILE_CLEAR)
	var/total_atoms = 0
	var/total_us = 0
	for(var/type in GLOB.mapload_init_bench_types)
		var/list/atoms = list()
		SSatoms.set_tracked_initalized(INITIALIZATION_INSSATOMS, "mapload_init bench")
		for(var/i in 1 to count)
			atoms += new type(locate(x + (i % 10), y + round(i / 10), 1))
		SSatoms.clear_tracked_initalize("mapload_init bench")
		var/list/first = list(atoms[1])
		var/list/rest = atoms.Copy(2)
		rustg_time_reset("mapload_init")
		SSatoms.InitializeAtoms(first)
		var/first_us = rustg_time_microseconds("mapload_init")
		// The rest as boot runs it: the batch is opened, the atoms initialized, the batch closed (deferred work, binds, late loaders);
		// the closing is a fixed cost of the run, so it is reported apart from the per-atom Initialize.
		var/list/run = SSatoms.initialize_atoms_begin(null)
		rustg_time_reset("mapload_init")
		SSatoms.CreateAtoms(run[ATOM_RUN_BATCH], rest)
		var/rest_us = rustg_time_microseconds("mapload_init")
		rustg_time_reset("mapload_init")
		SSatoms.initialize_atoms_finish(run, null)
		var/finish_us = rustg_time_microseconds("mapload_init")
		var/each_us = length(rest) ? rest_us / length(rest) : 0
		var/name = replacetext("[type]", "/", "_")
		metric("first_ms[name]", first_us / 1000, "ms")
		metric("each_us[name]", each_us, "us")
		metric("finish_ms[name]", finish_us / 1000, "ms")
		table["[type]"] = list("first_ms" = round(first_us / 1000, 0.01), "each_us" = round(each_us, 0.1), "finish_ms" = round(finish_us / 1000, 0.01), "count" = count)
		total_atoms += count
		total_us += first_us + rest_us + finish_us
		for(var/atom/A as anything in atoms)
			if(!QDELETED(A) && !isturf(A))
				qdel(A)
		refresh_flush()
	detail("mapload_init_by_type", table)
	if(profiling)
		// Procs of the whole run: the shared per-instance framework shows by count (calls / atoms) next to the type-specific ones.
		detail("mapload_init_proc_profile", benchmark_profile_summary(benchmark_proc_profile(), 120))
		detail("mapload_init_atoms", total_atoms)
	metric("mapload_init_total_ms", total_us / 1000, "ms")
	metric("mapload_init_ms_per_atom", total_us / 1000 / max(total_atoms, 1), "ms")

/// Where a space turf's map-load cost goes, in microseconds per turf: the dust appearance assignment, the declaration and capability
/// steps of table_initialize(), and the whole init (space is 310 k of Southern Cross's 466 k atoms, so its per-turf cost is the boot).
/datum/benchmark/mapload_init_space
	id = "mapload_init_space"
	description = "A space turf's map-load init split into its steps"

/datum/benchmark/mapload_init_space/Run()
	var/count = min(param("count", 3000), world.maxx * world.maxy)
	var/list/turfs = list()
	SSatoms.set_tracked_initalized(INITIALIZATION_INSSATOMS, "mapload_init bench")
	for(var/i in 1 to count)
		turfs += new /turf/space(locate(1 + ((i - 1) % world.maxx), 1 + round((i - 1) / world.maxx), 1))
	SSatoms.clear_tracked_initalize("mapload_init bench")
	rustg_time_reset("mapload_init_space")
	var/list/run = SSatoms.initialize_atoms_begin(null)
	SSatoms.CreateAtoms(run[ATOM_RUN_BATCH], turfs)
	var/whole_us = rustg_time_microseconds("mapload_init_space")
	SSatoms.initialize_atoms_finish(run, null)
	var/datum/system/skybox/sky = SSskybox.ready()
	var/list/dust = sky.dust_appearance_index()
	rustg_time_reset("mapload_init_space")
	for(var/turf/space/T as anything in turfs)
		T.appearance = dust[1 + (T.x % length(dust))]
	var/appearance_us = rustg_time_microseconds("mapload_init_space")
	rustg_time_reset("mapload_init_space")
	for(var/turf/space/T as anything in turfs)
		lifecycle_decls_init(T, TRUE)
	var/decls_us = rustg_time_microseconds("mapload_init_space")
	rustg_time_reset("mapload_init_space")
	for(var/turf/space/T as anything in turfs)
		caps_init(T, TRUE)
	var/caps_us = rustg_time_microseconds("mapload_init_space")
	rustg_time_reset("mapload_init_space")
	for(var/turf/space/T as anything in turfs)
		T.set_luminosity(!(T.dynamic_lighting))
	var/light_us = rustg_time_microseconds("mapload_init_space")
	metric("space_whole_us_each", whole_us / count, "us")
	metric("space_appearance_us_each", appearance_us / count, "us")
	metric("space_decls_us_each", decls_us / count, "us")
	metric("space_caps_us_each", caps_us / count, "us")
	metric("space_luminosity_us_each", light_us / count, "us")
