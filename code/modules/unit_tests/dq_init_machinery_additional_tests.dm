// Standalone lane: no dependency on the objects initializer branch.
/datum/unit_test/proc/dq_init_machinery_twenty_scope()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)

/datum/unit_test/dq_init_machinery_additional
/datum/unit_test/dq_init_machinery_additional/Run()
	dq_init_machinery_twenty_scope()
	var/turf/T = test_floor()
	var/obj/machinery/computer/cryopod/console = allocate(/obj/machinery/computer/cryopod, get_step(T, EAST))
	var/obj/machinery/cryopod/P = allocate(/obj/machinery/cryopod, T)
	TEST_ASSERT_EQUAL(P.control_computer(), console, "actual cryopod constructor discovers actual same-area controller")
	qdel(console)
	TEST_ASSERT_NULL(P.control_computer(), "deleted control console clears the actual borrowed relation")
	var/obj/machinery/recharge_station/R = allocate(/obj/machinery/recharge_station, T)
	TEST_ASSERT(istype(R.cell, /obj/item/cell/high), "actual recharge buffer is the high cell built by the final transaction")
	TEST_ASSERT(R.cell in R.component_parts, "component_parts retains ownership of the real buffer, not a second synthetic cell")
	var/obj/item/cell/buffer = R.cell
	qdel(R)
	TEST_ASSERT(QDELETED(buffer), "destruction deletes the real owned buffer once")
	var/obj/machinery/porta_turret/rcd/turret = allocate(/obj/machinery/porta_turret/rcd, T)
	TEST_ASSERT_EQUAL(turret.get_integrity(), 5, "RCD turret starts stressed rather than at default maximum20")
	TEST_ASSERT_EQUAL(turret.max_integrity, 20, "stress does not rewrite maximum integrity")

/datum/unit_test/dq_init_machinery_additional/floor_radio
/datum/unit_test/dq_init_machinery_additional/floor_radio/Run()
	dq_init_machinery_twenty_scope()
	var/turf/T = test_floor()
	var/obj/machinery/magnetic_module/M = allocate(/obj/machinery/magnetic_module, T)
	TEST_ASSERT_EQUAL(M.get_center(), T, "real magnet's constructor anchors field center to final turf")
	TEST_ASSERT_EQUAL(!!M.invisibility, !T.is_plating(), "real floor magnet gets final floor's visibility")
	var/datum/radio_frequency/F = SSradio.return_frequency(M.freq)
	TEST_ASSERT(M in F.devices[RADIO_MAGNETS], "real magnet is subscribed to its actual radio filter")
	qdel(M)
	TEST_ASSERT(QDELETED(F) || !(M in F.devices[RADIO_MAGNETS]), "magnet destruction removes real radio subscription")
	var/obj/machinery/navbeacon/patrol/N = allocate(/obj/machinery/navbeacon/patrol, T)
	TEST_ASSERT_EQUAL(N.codes["patrol"], 1, "pre-parent patrol code remains intact")
	TEST_ASSERT_EQUAL(N.codes["next_patrol"], N.next_patrol, "pre-parent next patrol parameter remains intact")
	TEST_ASSERT_EQUAL(!!N.invisibility, !T.is_plating(), "inherited final hide remains after patrol input preparation")
	var/obj/machinery/status_display/D = allocate(/obj/machinery/status_display, T)
	var/datum/radio_frequency/DF = SSradio.return_frequency(D.frequency)
	TEST_ASSERT(D in DF.devices[RADIO_DEFAULT], "actual display constructor joins default radio filter")
	qdel(D)
	TEST_ASSERT(QDELETED(DF) || !(D in DF.devices[RADIO_DEFAULT]), "display deletion removes actual radio membership")

/datum/unit_test/dq_init_machinery_additional/painter_and_door
/datum/unit_test/dq_init_machinery_additional/painter_and_door/Run()
	dq_init_machinery_twenty_scope()
	set_global(nameof(GLOB.gear_distributed_to), GLOB.gear_distributed_to ? GLOB.gear_distributed_to.Copy() : list())
	var/obj/machinery/gear_painter/A = allocate(/obj/machinery/gear_painter, test_floor())
	var/obj/machinery/gear_painter/B = allocate(/obj/machinery/gear_painter, test_floor())
	TEST_ASSERT_EQUAL(length(A.color_matrix_last), 12, "actual editor starts with complete 3x3-plus-offset matrix")
	for(var/i = 1 to 12)
		TEST_ASSERT_EQUAL(A.color_matrix_last[i], i == 1 || i == 5 || i == 9 ? 1 : 0, "actual matrix starts as identity")
	TEST_ASSERT(A.color_matrix_last != B.color_matrix_last, "two editors do not share mutable matrix identity")
	A.set_color_matrix_last_at(1, 0.5)
	TEST_ASSERT_EQUAL(B.color_matrix_last[1], 1, "editing one real painter leaves peer unchanged")
	var/obj/machinery/gear_dispenser/suit_fancy/S = allocate(/obj/machinery/gear_dispenser/suit_fancy, test_floor())
	// own() records only a cleanup reference; SSvis_overlays retains its declared ownership.
	own(S.door)
	TEST_ASSERT(S.door, "actual fancy dispenser mounts real service-owned door overlay")
	TEST_ASSERT_EQUAL(S.door.icon_state, "closed", "actual mounted door starts closed")
	TEST_ASSERT_EQUAL(S.door.layer, 4, "actual mounted door preserves visual service layer")

/datum/unit_test/dq_init_machinery_additional/empty_music
/datum/unit_test/dq_init_machinery_additional/empty_music/Run()
	dq_init_machinery_twenty_scope()
	// Replace the list view temporarily; never delete or mutate the shared track datums.
	set_var(SSmedia_tracks, nameof(SSmedia_tracks.jukebox_tracks), null)
	var/obj/machinery/media/jukebox/J = allocate(/obj/machinery/media/jukebox, test_floor())
	TEST_ASSERT(J.broken_now(), "real jukebox constructor marks missing-library machine broken")

/datum/unit_test/dq_init_machinery_additional/pipe_targets
/datum/unit_test/dq_init_machinery_additional/pipe_targets/Run()
	dq_init_machinery_twenty_scope()
	var/turf/T = test_floor()
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple, T)
	var/obj/machinery/clamp/C = allocate(/obj/machinery/clamp, T)
	TEST_ASSERT_EQUAL(C.target_ref(), P, "actual clamp constructor selects colocated simple pipe")
	TEST_ASSERT_EQUAL(C.dir, P.dir, "attached clamp adopts actual target direction")
	var/obj/machinery/meter/M = allocate(/obj/machinery/meter, T)
	TEST_ASSERT_EQUAL(M.target_ref(), P, "actual meter constructor selects real pipe")
	var/list/previous_meters = list()
	for(var/obj/item/pipe_meter/old_meter in contents_of(T))
		previous_meters += old_meter
	qdel(P)
	var/obj/item/pipe_meter/product
	for(var/obj/item/pipe_meter/made in contents_of(T))
		if(!(made in previous_meters))
			product = made
	// The real handler makes a new pipe-meter item before replace_with deletes M.
	// Register the product before assertions, so a failed assertion cannot leak it.
	own(product)
	TEST_ASSERT(QDELETED(M), "constructor installed actual target-death watch, converting meter when pipe dies")
	TEST_ASSERT(product && product.loc == T, "actual target-death conversion leaves its real pipe-meter product on the turf")

/datum/unit_test/dq_init_machinery_additional/proc/restore_scrubber_gid(obj/machinery/portable_atmospherics/powered/scrubber/huge/S, saved)
	if(QDELETED(S))
		CRASH("scrubber id cleanup anchor deleted prematurely")
	S.gid = saved

/datum/unit_test/dq_init_machinery_additional/area_scrubbers
/datum/unit_test/dq_init_machinery_additional/area_scrubbers/Run()
	dq_init_machinery_twenty_scope()
	var/turf/T = test_floor()
	SSatoms.map_loader_begin("dq_init_scrubber_scan")
	var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S = new(get_step(T, EAST))
	var/obj/machinery/portable_atmospherics/powered/scrubber/huge/anchor = new(get_step(T, NORTH))
	var/before = S.gid
	SSatoms.map_loader_stop("dq_init_scrubber_scan")
	own(S)
	own(anchor)
	// The peer stays alive even when S is explicitly destroyed; teardown runs before allocated deletion.
	defer_cleanup(src, PROC_REF(restore_scrubber_gid), anchor, before)
	SSatoms.InitializeAtoms(list(S, anchor))
	var/obj/machinery/computer/area_atmos/C = allocate(/obj/machinery/computer/area_atmos, T)
	TEST_ASSERT(S in C.connectedscrubbers, "actual console discovers real in-range scrubber during construction")
	qdel(S)
	TEST_ASSERT(!(S in C.connectedscrubbers), "discovery retains a lifetime-safe borrowed view")

/datum/unit_test/dq_init_machinery_additional/survival_pod
/datum/unit_test/dq_init_machinery_additional/survival_pod/Run()
	dq_init_machinery_twenty_scope()
	var/obj/machinery/sleeper/survival_pod/S = allocate(/obj/machinery/sleeper/survival_pod, test_floor())
	TEST_ASSERT_EQUAL(length(S.available_chemicals), length(S.base_chemicals), "actual survival pod contains only base chemical catalog")
	for(var/id in S.base_chemicals)
		TEST_ASSERT_EQUAL(S.available_chemicals[id], S.base_chemicals[id], "survival pod preserves exact base reagent labels")
	TEST_ASSERT_EQUAL(S.stasis_rate, 0.01, "domain parts policy retains survival stasis factor")

/datum/unit_test/dq_init_machinery_additional/fire_level
/datum/unit_test/dq_init_machinery_additional/fire_level/Run()
	dq_init_machinery_twenty_scope()
	// Existing contact-level policy is shared config: scope it, do not edit the map datum.
	set_var(using_map, nameof(using_map.contact_levels), list(test_floor().z))
	var/expected = GLOB.security_level ? get_security_level() : "green"
	SSatoms.map_loader_begin("dq_init_fire_level")
	var/obj/machinery/firealarm/F = new(test_floor())
	// This real local API changes only the alarm's presentation, never global security.
	F.set_security_level(expected == "green" ? "red" : "green")
	SSatoms.map_loader_stop("dq_init_fire_level")
	own(F)
	TEST_ASSERT(F.seclevel != expected, "queued mapped alarm actually has the opposite security presentation before initialization")
	SSatoms.InitializeAtoms(list(F))
	TEST_ASSERT_EQUAL(F.seclevel, expected, "actual contact-level firealarm replaces staged opposite level after parent")

/datum/unit_test/dq_init_machinery_additional/proc/restore_camera_numbers(obj/machinery/camera/autoname/C, list/original)
	if(QDELETED(C))
		CRASH("camera numbering cleanup anchor deleted prematurely")
	C.by_area = original

/datum/unit_test/dq_init_machinery_additional/camera_numbers
/datum/unit_test/dq_init_machinery_additional/camera_numbers/Run()
	dq_init_machinery_twenty_scope()
	SSatoms.map_loader_begin("dq_init_area_camera")
	var/obj/machinery/camera/autoname/A = new(test_floor())
	var/obj/machinery/camera/autoname/B = new(test_floor())
	var/list/saved = A.by_area
	var/list/isolated = saved ? saved.Copy() : list()
	A.by_area = isolated
	var/area/zone = get_area(A)
	var/before = isolated[zone.name]
	SSatoms.map_loader_stop("dq_init_area_camera")
	own(A)
	own(B)
	defer_cleanup(src, PROC_REF(restore_camera_numbers), A, saved)
	SSatoms.InitializeAtoms(list(A, B))
	TEST_ASSERT_EQUAL(A.c_tag, "[zone.name] #[before + 1]", "first queued real camera receives next area-local sequence")
	TEST_ASSERT_EQUAL(B.c_tag, "[zone.name] #[before + 2]", "second queued camera receives following sequence")
	TEST_ASSERT(length(A.network), "actual parent camera network normalization still completed")

/datum/unit_test/dq_init_machinery_additional/multi_tile_geometry
/datum/unit_test/dq_init_machinery_additional/multi_tile_geometry/Run()
	dq_init_machinery_twenty_scope()
	var/turf/T = test_floor()
	for(var/turf/floor in range(2, T))
		set_var(floor, nameof(floor.opacity), floor.opacity)
	var/list/types = list(/obj/machinery/door/airlock/angled_bay/double, /obj/machinery/door/airlock/angled_tgmc/wide, /obj/machinery/door/airlock/multi_tile)
	for(var/path in types)
		var/obj/machinery/door/D = allocate(path, T, NORTH)
		var/bay_orientation = istype(D, /obj/machinery/door/airlock/angled_bay/double)
		TEST_ASSERT_EQUAL(D.bound_width, bay_orientation ? D.width * world.icon_size : world.icon_size, "real constructor applies exact directional multi-tile width")
		TEST_ASSERT_EQUAL(D.bound_height, bay_orientation ? world.icon_size : D.width * world.icon_size, "real constructor applies exact directional multi-tile height")
		for(var/turf/covered in D.locs)
			TEST_ASSERT_EQUAL(!!covered.opacity, !!D.opacity, "all actual covered turfs receive final parent opacity")
		qdel(D)

/datum/unit_test/dq_init_machinery_additional/alarm_radio
/datum/unit_test/dq_init_machinery_additional/alarm_radio/Run()
	dq_init_machinery_twenty_scope()
	var/obj/machinery/door/airlock/alarmlock/D = allocate(/obj/machinery/door/airlock/alarmlock, test_floor())
	var/datum/radio_frequency/F = D.air_connection()
	TEST_ASSERT(F, "actual alarm door binds its borrowed radio connection")
	TEST_ASSERT(D in F.devices[RADIO_TO_AIRALARM], "actual alarm door subscribes with correct filter")
	qdel(D)
	TEST_ASSERT(QDELETED(F) || !(D in F.devices[RADIO_TO_AIRALARM]), "door deletion removes real frequency membership")

/datum/unit_test/dq_init_machinery_additional/retention_air
/datum/unit_test/dq_init_machinery_additional/retention_air/Run()
	dq_init_machinery_twenty_scope()
	var/turf/T = test_floor()
	TEST_ASSERT(SSair.initialized, "real atmos arena initialized for mask assertion")
	var/obj/structure/atmospheric_retention_field/F = allocate(/obj/structure/atmospheric_retention_field, T)
	TEST_ASSERT_EQUAL(vg_atmos_open_dirs(T), 0, "actual field constructor republishes closed native air adjacency on its turf")
	qdel(F)

/obj/machinery/button/doorbell/dq_init_placement
	id = "dq_init_preassigned_doorbell"

/obj/machinery/pointdefense_control/dq_init_parts
	id_tag = "dq_init_pointdefense_unique"
	var/part_setup_calls = 0

/obj/machinery/pointdefense_control/dq_init_parts/default_apply_parts()
	part_setup_calls++
	return ..()

/datum/unit_test/dq_init_machinery_next_tails
/datum/unit_test/dq_init_machinery_next_tails/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
	var/turf/T = test_floor()
	for(var/direction in GLOB.cardinal)
		var/obj/machinery/button/doorbell/B = allocate(/obj/machinery/button/doorbell, T, direction, TRUE)
		TEST_ASSERT_EQUAL(B.dir, direction, "the actual constructor facing is applied before placement")
		TEST_ASSERT_EQUAL(B.pixel_x, (direction & 3) ? 0 : (direction == 4 ? -32 : 32), "a real built switch keeps its wall-side horizontal offset")
		TEST_ASSERT_EQUAL(B.pixel_y, (direction & 3) ? (direction == 1 ? -27 : 27) : 0, "a real built switch keeps its wall-side vertical offset")
		TEST_ASSERT_EQUAL(B.id, num2text(B.uid), "a previously unnamed real switch gets its actual UID")
	var/obj/machinery/button/doorbell/dq_init_placement/mapped = allocate(/obj/machinery/button/doorbell/dq_init_placement, T)
	TEST_ASSERT_EQUAL(mapped.id, "dq_init_preassigned_doorbell", "preassigned IDs are not replaced by constructor setup")
	TEST_ASSERT_EQUAL(mapped.pixel_x, initial(mapped.pixel_x), "an unbuilt switch keeps its mapped horizontal offset")
	TEST_ASSERT_EQUAL(mapped.pixel_y, initial(mapped.pixel_y), "an unbuilt switch keeps its mapped vertical offset")
	var/obj/machinery/pointdefense_control/dq_init_parts/P = allocate(/obj/machinery/pointdefense_control/dq_init_parts, T)
	TEST_ASSERT_EQUAL(P.id_tag, "dq_init_pointdefense_unique", "a real unique controller keeps its network ID")
	TEST_ASSERT_EQUAL(P.part_setup_calls, 1, "the actual inherited parts transaction runs once during construction")
	TEST_ASSERT(P in REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_CONTROLLERS), "constructor setup sees its real declared registry membership")
	qdel(P)
	TEST_ASSERT(!(P in REGISTRY_MEMBERS(REGISTRY_POINTDEFENSE_CONTROLLERS)), "actual controller deletion removes registry membership")
	var/obj/machinery/pointdefense_control/dq_init_parts/replacement = allocate(/obj/machinery/pointdefense_control/dq_init_parts, T)
	TEST_ASSERT_EQUAL(replacement.id_tag, "dq_init_pointdefense_unique", "a deleted controller cannot invalidate its replacement's ID")
	TEST_ASSERT_EQUAL(replacement.part_setup_calls, 1, "replacement construction also runs the real parts transaction once")
