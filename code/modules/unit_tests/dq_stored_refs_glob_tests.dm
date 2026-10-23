// stored_refs conversions of the globals (doc/rewrite/proposals/reference_storage.md): the references GLOB holds are declared relations of
// /datum/controller/global_vars, so a deleted target leaves its global by itself and every write goes through rel_set()/rel_add().

/// The single-reference globals: set through the relation, cleared when the target dies, replaced without keeping the old one.
/datum/unit_test/stored_refs_glob_single

/datum/unit_test/stored_refs_glob_single/Run()
	TEST_ASSERT_EQUAL(rel_kind(GLOB, nameof(GLOB.ore_silo_default)), OWNK_REL, "the default silo is a declared relation")
	TEST_ASSERT_EQUAL(rel_kind(GLOB, nameof(GLOB.blackbox)), OWNK_REL, "the blackbox is a declared relation")
	TEST_ASSERT_EQUAL(rel_kind(GLOB, nameof(GLOB.sleevemate_mob)), OWNK_REL, "the sleevemate mob is a declared relation")
	TEST_ASSERT_EQUAL(rel_kind(GLOB, nameof(GLOB.station_account)), OWNK_REL, "the station account is a declared relation")
	var/saved_landmark = GLOB.ai_camera_room_landmark
	var/obj/effect/landmark/ai_multicam_room/first = allocate(/obj/effect/landmark/ai_multicam_room)
	rel_set(GLOB, nameof(GLOB.ai_camera_room_landmark), first)
	TEST_ASSERT_EQUAL(GLOB.ai_camera_room_landmark, first, "the landmark is held")
	qdel(first, TRUE)
	TEST_ASSERT_NULL(GLOB.ai_camera_room_landmark, "a deleted landmark leaves the global")
	var/obj/effect/landmark/ai_multicam_room/second = allocate(/obj/effect/landmark/ai_multicam_room)
	var/obj/effect/landmark/ai_multicam_room/third = allocate(/obj/effect/landmark/ai_multicam_room)
	rel_set(GLOB, nameof(GLOB.ai_camera_room_landmark), second)
	rel_set(GLOB, nameof(GLOB.ai_camera_room_landmark), third)
	TEST_ASSERT_EQUAL(GLOB.ai_camera_room_landmark, third, "a new landmark replaces the old one")
	qdel(second, TRUE)
	TEST_ASSERT_EQUAL(GLOB.ai_camera_room_landmark, third, "a deleted replaced landmark leaves the current one alone")
	rel_set(GLOB, nameof(GLOB.ai_camera_room_landmark), saved_landmark)

	var/saved_vendor = GLOB.vendor_account
	var/datum/money_account/account = create_account("Stored Refs Test", 5)
	rel_set(GLOB, nameof(GLOB.vendor_account), account)
	TEST_ASSERT_EQUAL(GLOB.vendor_account, account, "the account is held")
	qdel(account)
	TEST_ASSERT_NULL(GLOB.vendor_account, "a deleted account leaves the vendor global")
	rel_set(GLOB, nameof(GLOB.vendor_account), saved_vendor)

/// The silo's own lifecycle path still clears the default silo it was.
/datum/unit_test/stored_refs_glob_silo_default

/datum/unit_test/stored_refs_glob_silo_default/Run()
	var/saved = GLOB.ore_silo_default
	var/obj/machinery/ore_silo/silo = allocate(/obj/machinery/ore_silo)
	rel_set(GLOB, nameof(GLOB.ore_silo_default), silo)
	TEST_ASSERT_EQUAL(GLOB.ore_silo_default, silo, "the silo is the default")
	qdel(silo)
	TEST_ASSERT_NULL(GLOB.ore_silo_default, "a deleted default silo leaves the global")
	rel_set(GLOB, nameof(GLOB.ore_silo_default), saved)

/// The admin fax cache and the admin rank lists are many relations: a deleted member leaves, an emptied list stays a list.
/datum/unit_test/stored_refs_glob_lists

/datum/unit_test/stored_refs_glob_lists/Run()
	TEST_ASSERT_EQUAL(rel_kind(GLOB, nameof(GLOB.adminfaxes)), OWNK_REL, "the fax cache is a declared relation")
	var/obj/item/paper/copy = allocate(/obj/item/paper)
	admin_fax_keep(copy)
	TEST_ASSERT(copy in GLOB.adminfaxes, "the fax joined the cache")
	var/count = length(GLOB.adminfaxes)
	qdel(copy)
	TEST_ASSERT(!(copy in GLOB.adminfaxes), "a deleted fax left the cache")
	TEST_ASSERT_EQUAL(length(GLOB.adminfaxes), count - 1, "only that fax left")

	var/datum/admin_rank/rank = new("stored_refs_glob_rank", RANK_SOURCE_TEMPORARY)
	rel_add(GLOB, nameof(GLOB.admin_ranks), rank)
	rel_add(GLOB, nameof(GLOB.protected_ranks), rank)
	TEST_ASSERT(rank in GLOB.admin_ranks, "the rank joined the rank list")
	rel_remove(GLOB, nameof(GLOB.admin_ranks), rank)
	TEST_ASSERT(!(rank in GLOB.admin_ranks), "a removed rank left the rank list")
	TEST_ASSERT(rank in GLOB.protected_ranks, "and stays in the other list")
	qdel(rank, TRUE)
	TEST_ASSERT(!(rank in GLOB.protected_ranks), "a deleted rank left the protected list")

/// Mannequins are a keyed many by ckey; map sectors one keyed by level text. A deleted member takes its keys; a key can be emptied by name.
/datum/unit_test/stored_refs_glob_keyed

/datum/unit_test/stored_refs_glob_keyed/Run()
	var/key = "stored_refs_glob_test"
	var/mob/living/carbon/human/dummy/mannequin/first = get_mannequin(key)
	TEST_ASSERT(istype(first), "a mannequin is made for the key")
	TEST_ASSERT_EQUAL(get_mannequin(key), first, "the same mannequin comes back")
	qdel(first, TRUE)
	TEST_ASSERT_NULL(GLOB.mannequins[key], "a deleted mannequin leaves the global")
	var/mob/living/carbon/human/dummy/mannequin/second = get_mannequin(key)
	TEST_ASSERT(istype(second) && second != first, "a new mannequin is made after the old one went")
	del_mannequin(key)
	TEST_ASSERT(!(key in GLOB.mannequins), "del_mannequin() takes the key out")
	TEST_ASSERT(!QDELETED(second), "and leaves the mannequin itself alone")
	qdel(second, TRUE)

	var/obj/effect/overmap/visitable/sector = new /obj/effect/overmap/visitable(null)
	sector.map_z = list(903, 904)
	sector.register_z_levels()
	TEST_ASSERT_EQUAL(GLOB.map_sectors["903"], sector, "registered under the level text")
	qdel(sector, TRUE)
	TEST_ASSERT_NULL(GLOB.map_sectors["903"], "a deleted sector leaves its first level")
	TEST_ASSERT_NULL(GLOB.map_sectors["904"], "and its second level")

/// A camera's viewer huds are a many relation of shared global screens; a communicator camera adds the dark mask element by element, in order.
/datum/unit_test/stored_refs_camera_huds

/datum/unit_test/stored_refs_camera_huds/Run()
	var/obj/machinery/camera/cam = allocate(/obj/machinery/camera, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(rel_kind(cam, nameof(cam.client_huds)), OWNK_REL, "a camera's huds are a declared relation")
	TEST_ASSERT_EQUAL(length(cam.client_huds), 1, "a camera shows the one viewer hud")
	TEST_ASSERT_EQUAL(cam.client_huds[1], GLOB.global_hud.whitense, "the static screen")
	var/obj/machinery/camera/communicator/comm = allocate(/obj/machinery/camera/communicator, run_loc_floor_bottom_left)
	var/list/expected = list(GLOB.global_hud.whitense) | GLOB.global_hud.darkMask
	TEST_ASSERT_EQUAL(length(comm.client_huds), length(expected), "a communicator camera adds the dark mask")
	for(var/i in 1 to length(expected))
		TEST_ASSERT_EQUAL(comm.client_huds[i], expected[i], "the huds keep their order")
