/// Init wave 4: the setup()/rolls()/initial_contents() forms that replaced these types' Initialize() code keep what that code did.
/datum/unit_test/dq_init_wave_4
	abstract_type = /datum/unit_test/dq_init_wave_4

/datum/unit_test/dq_init_wave_4/shadekin_prototype_is_replaced/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/shadekin/proto = new /mob/living/simple_mob/shadekin(T)
	TEST_ASSERT(QDELETED(proto), "the prototype shadekin is discarded")
	var/found = FALSE
	for(var/mob/living/simple_mob/shadekin/kin in T)
		if(kin.type != /mob/living/simple_mob/shadekin)
			found = TRUE
			qdel(kin)
	TEST_ASSERT(found, "a real kind of shadekin stands in its place")

/datum/unit_test/dq_init_wave_4/shadekin_kind_is_kept/Run()
	var/mob/living/simple_mob/shadekin/red/kin = allocate(/mob/living/simple_mob/shadekin/red, test_floor())
	TEST_ASSERT(!QDELETED(kin), "a specific kind of shadekin stays")
	TEST_ASSERT(istype(kin.shadekin, /datum/shadekin), "and has its shadekin state")

/datum/unit_test/dq_init_wave_4/fluff_box_holds_its_items/Run()
	var/obj/item/storage/box/fluff/cassandra/box = allocate(/obj/item/storage/box/fluff/cassandra, test_floor())
	TEST_ASSERT_EQUAL(length(box.contents), length(box.has_items), "the kit holds each item it lists")
	TEST_ASSERT_EQUAL(box.storage_slots, length(box.has_items), "and has a slot for each")

/datum/unit_test/dq_init_wave_4/cameras_share_a_network_list/Run()
	var/turf/T = test_floor()
	var/obj/machinery/camera/first = allocate(/obj/machinery/camera, T)
	var/obj/machinery/camera/second = allocate(/obj/machinery/camera, T)
	TEST_ASSERT(first.network == second.network, "cameras of one network set share one list")
	TEST_ASSERT(length(first.network) > 0, "and it is not empty")

/datum/unit_test/dq_init_wave_4/area_luminosity_follows_lighting/Run()
	var/area/A = get_area(test_floor())
	TEST_ASSERT_EQUAL(A.luminosity, !(A.dynamic_lighting), "an area is lit of its own only when it has no dynamic lighting")
