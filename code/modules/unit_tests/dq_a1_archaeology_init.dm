// A1 lifecycle jobs: use real constructors, products and containment.
/datum/unit_test/dq_a1_archaeology_init
	abstract_type = /datum/unit_test/dq_a1_archaeology_init

/datum/unit_test/dq_a1_archaeology_init/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_a1_archaeology_init/proc/adopt_new_items(turf/T, list/before)
	var/list/products
	for(var/obj/item/I as anything in contents_of(T, /obj/item))
		if(I in before)
			continue
		own(I)
		LAZYADD(products, I)
	return products

/datum/unit_test/dq_a1_archaeology_init/replacement/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /obj/item)
	var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find, T, ARCHAEO_BOWL)
	var/list/products = adopt_new_items(T, before)
	TEST_ASSERT(QDELETED(proxy), "A bowl find spends its original proxy")
	TEST_ASSERT_EQUAL(length(products), 1, "Excavating a bowl leaves one replacement, not a proxy plus a bowl")
	var/obj/item/reagent_containers/glass/replenishing/bowl = products[1]
	TEST_ASSERT(istype(bowl), "The selected bowl is the real replenishing container")
	TEST_ASSERT_EQUAL(bowl.loc, T, "The replacement is on the proxy's original turf")
	TEST_ASSERT_EQUAL(bowl.icon_state, "bowl", "The replacement retains its selected bowl look")
	TEST_ASSERT(findtext(bowl.name, "bowl"), "The replacement receives its generated bowl name")
	TEST_ASSERT(findtext(bowl.desc, "stains inside"), "The replacement receives the bowl's generated description")

/datum/unit_test/dq_a1_archaeology_init/retained_proxy/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /obj/item)
	var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find, T, MAX_ARCHAEO + 1)
	var/list/products = adopt_new_items(T, before)
	TEST_ASSERT(!QDELETED(proxy), "A find with no replacement remains alive")
	TEST_ASSERT_EQUAL(proxy.loc, T, "The unreplaced find stays at its original location")
	TEST_ASSERT_EQUAL(length(products), 1, "The unreplaced branch does not spawn an unrelated product")
	TEST_ASSERT_EQUAL(products[1], proxy, "The only new item is the retained original find")
	TEST_ASSERT(findtext(proxy.name, "object"), "The retained find still receives its final generated name")
	TEST_ASSERT(findtext(proxy.icon_state, "unknown") == 1, "The retained find receives its unknown look")

/obj/item/archaeological_find/dq_a1_rejected/proc/keep_find()
	return FALSE

CAPABILITIES(/obj/item/archaeological_find/dq_a1_rejected)
	keeps_if(PROC_REF(keep_find))

/datum/unit_test/dq_a1_archaeology_init/rejected_holder/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /obj/item)
	var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find/dq_a1_rejected, T, ARCHAEO_BOWL)
	var/list/products = adopt_new_items(T, before)
	TEST_ASSERT(QDELETED(proxy), "The real keeps_if rejection discards the holder")
	TEST_ASSERT_EQUAL(length(products), 0, "A rejected holder never runs its excavation setup or creates a replacement")

/datum/unit_test/dq_a1_archaeology_init/rock_contents/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/strangerock/rock = allocate(/obj/item/strangerock, test_floor(), ARCHAEO_BOWL)
	var/list/products = contents_of(rock, /obj/item)
	for(var/obj/item/I as anything in products)
		own(I)
	TEST_ASSERT_EQUAL(length(products), 1, "A configured rock conceals exactly one find or research sample")
	var/obj/item/product = products[1]
	TEST_ASSERT(!QDELETED(product) && product.loc == rock, "The concealed product is alive inside its initialized rock")
	TEST_ASSERT(istype(product, /obj/item/research_sample) || istype(product, /obj/item/reagent_containers/glass/replenishing), "The selected product is a sample or the configured excavated bowl")
	TEST_ASSERT_EQUAL(rock.inside_item_type, ARCHAEO_BOWL, "The constructor's find type survives setup")

/datum/unit_test/dq_a1_archaeology_init/harvester_facing/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/center = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y + 2, run_loc_floor_bottom_left.z)
	var/turf/front = get_step(center, NORTH)
	var/turf/side = get_step(center, WEST)
	TEST_ASSERT(isfloorturf(center) && isfloorturf(front) && isfloorturf(side), "Scanner pairing fixture has three real floors")
	var/obj/machinery/artifact_scanpad/preferred = allocate(/obj/machinery/artifact_scanpad, front)
	var/obj/machinery/artifact_scanpad/fallback = allocate(/obj/machinery/artifact_scanpad, side)
	var/obj/machinery/artifact_harvester/harvester = allocate(/obj/machinery/artifact_harvester, center, NORTH)
	TEST_ASSERT_EQUAL(harvester.dir, NORTH, "The machine's constructor facing is applied before pairing")
	TEST_ASSERT_EQUAL(harvester.owned_scanner(), preferred, "Facing the scanpad outranks another adjacent candidate")
	TEST_ASSERT(!QDELETED(fallback), "Pairing leaves the other scanner alone")

// A fixed, inert primary effect keeps this containment fixture from choosing
// destructive random artifact effects; the production master/holder setup runs.
/datum/artifact_master/dq_a1_fixed
	make_effects = list(/datum/artifact_effect)

/obj/machinery/artifact/dq_a1_fixed
	artifact_master_type = /datum/artifact_master/dq_a1_fixed
	predefined_icon_num = 9

/datum/unit_test/dq_a1_archaeology_init/container/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/obj/machinery/artifact/artifact = allocate(/obj/machinery/artifact/dq_a1_fixed, T)
	var/obj/structure/anomaly_container/container = allocate(/obj/structure/anomaly_container, T)
	TEST_ASSERT_EQUAL(container.contained(), artifact, "The new container captures the already placed real artifact")
	TEST_ASSERT_EQUAL(artifact.loc, container, "Capture puts the real artifact inside the container")
	TEST_ASSERT_EQUAL(length(container.underlays), 1, "Capture adds the contained artifact underlay")
	TEST_ASSERT(findtext(container.desc, "kept inside"), "Capture updates the container description")
	container.release()
	TEST_ASSERT_EQUAL(artifact.loc, T, "The initialized container can release its real occupant again")
	TEST_ASSERT_NULL(container.contained(), "Release clears the captured reference")

/obj/skeleton/dq_a1_preconfigured
	breq = 99
	bnum = 2

/datum/unit_test/dq_a1_archaeology_init/skeleton_roll/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)
	var/obj/skeleton/S = allocate(/obj/skeleton/dq_a1_preconfigured, test_floor())
	TEST_ASSERT(S.breq >= 4 && S.breq <= 9, "The actual constructor retains its original one-to-six plus three bone roll")
	TEST_ASSERT(S.breq != 99, "Construction retains its original overwrite of a preconfigured bone count")
	TEST_ASSERT_EQUAL(S.bnum, 2, "Rolling the missing bones preserves the actual existing bone count")
	TEST_ASSERT_EQUAL(S.desc, "An incomplete skeleton, looks like it could use [S.breq-S.bnum] more bones.", "The completed constructor description uses the same rolled count")
