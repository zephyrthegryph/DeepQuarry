// Exercise the real excavation constructor, its replacement and the retained
// proxy. The generator's draws must stay interleaved with child constructors.
/datum/unit_test/dq_decl_archaeological_find
	abstract_type = /datum/unit_test/dq_decl_archaeological_find

/datum/unit_test/dq_decl_archaeological_find/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_decl_archaeological_find/proc/adopt_products(turf/T, list/before)
	var/list/products
	for(var/atom/movable/product as anything in contents_of(T, /atom/movable))
		if(product in before)
			continue
		own(product)
		LAZYADD(products, product)
	return products

/datum/unit_test/dq_decl_archaeological_find/bowl
/datum/unit_test/dq_decl_archaeological_find/bowl/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /atom/movable)
	var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find, T, ARCHAEO_BOWL)
	var/list/products = adopt_products(T, before)
	TEST_ASSERT(QDELETED(proxy), "Excavation spends the proxy after creating its replacement")
	TEST_ASSERT_EQUAL(length(products), 1, "One bowl is created, with no surviving proxy")
	var/obj/item/reagent_containers/glass/replenishing/bowl = products[1]
	TEST_ASSERT(istype(bowl), "The product is a real replenishing bowl")
	TEST_ASSERT_EQUAL(bowl.loc, T, "The product remains at the excavation turf")
	TEST_ASSERT_EQUAL(bowl.icon_state, "bowl", "The replacement receives the bowl look")
	TEST_ASSERT(findtext(bowl.name, "bowl"), "The replacement receives its generated name")
	TEST_ASSERT(findtext(bowl.desc, "stains inside"), "The generated description reaches the replacement")

/datum/unit_test/dq_decl_archaeological_find/retained
/datum/unit_test/dq_decl_archaeological_find/retained/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /atom/movable)
	var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find, T, MAX_ARCHAEO + 1)
	var/list/products = adopt_products(T, before)
	TEST_ASSERT(!QDELETED(proxy), "An unrecognized find type keeps its original proxy")
	TEST_ASSERT_EQUAL(length(products), 1, "An unrecognized find does not create another object")
	TEST_ASSERT_EQUAL(products[1], proxy, "The original proxy is the only new object")
	TEST_ASSERT(proxy.icon_state in list("unknown1", "unknown2", "unknown3", "unknown4"), "The retained proxy receives one of its four real looks")
	TEST_ASSERT(findtext(proxy.name, "object"), "The retained proxy still receives a generated name")

/datum/unit_test/dq_decl_archaeological_find/variants
/datum/unit_test/dq_decl_archaeological_find/variants/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/expected_types = list(
		"[ARCHAEO_STATUETTE]" = /obj/item/vampiric,
		"[ARCHAEO_INSTRUMENT]" = /obj/item/instrument,
		"[ARCHAEO_GASTANK]" = /obj/item/tank,
		"[ARCHAEO_PEN]" = /obj/item/pen,
		"[ARCHAEO_REMAINS_HUMANOID]" = /obj/item/organ/internal,
		"[ARCHAEO_REMAINS_ROBOT]" = /obj/structure/ghost_pod/manual/lost_drone/dogborg,
		"[ARCHAEO_SYRINGE]" = /obj/item/reagent_containers/syringe,
	)
	for(var/find_id in expected_types)
		var/list/before = contents_of(T, /atom/movable)
		var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find, T, text2num(find_id))
		var/list/products = adopt_products(T, before)
		TEST_ASSERT(QDELETED(proxy), "Find [find_id] spends its proxy")
		TEST_ASSERT_EQUAL(length(products), 1, "Find [find_id] produces exactly one real replacement")
		var/atom/movable/product = products[1]
		TEST_ASSERT(istype(product, expected_types[find_id]), "Find [find_id] creates its selected product family")
		TEST_ASSERT_EQUAL(product.loc, T, "Find [find_id] leaves its product on the excavation turf")
		if(text2num(find_id) == ARCHAEO_STATUETTE)
			TEST_ASSERT(proxy.icon_state in list("statuette1", "statuette2", "statuette3"), "Statuette construction selects its real proxy visual")
		if(text2num(find_id) == ARCHAEO_INSTRUMENT)
			TEST_ASSERT_EQUAL(proxy.icon_state, "instrument", "Instrument construction selects its proxy visual")
		if(text2num(find_id) == ARCHAEO_GASTANK)
			TEST_ASSERT(proxy.icon_state in list("oxygen", "oxygen_fr", "oxygen_f", "phoron", "anesthetic"), "Gas-tank construction selects its actual tank visual")
		if(text2num(find_id) == ARCHAEO_REMAINS_HUMANOID)
			TEST_ASSERT_EQUAL(proxy.icon, 'icons/effects/blood.dmi', "Organic remains select the blood icon sheet")
			TEST_ASSERT_EQUAL(proxy.icon_state, "remains", "Organic remains select their real visual")
			var/obj/item/organ/internal/organ = product
			TEST_ASSERT(!organ.can_reject, "An excavated organ retains its rejection exemption")
		if(text2num(find_id) == ARCHAEO_REMAINS_ROBOT)
			TEST_ASSERT_EQUAL(proxy.icon, 'icons/mob/robots.dmi', "Robotic remains select the robot icon sheet")
			TEST_ASSERT_EQUAL(proxy.icon_state, "remainsrobot", "Robotic remains select their real visual")
		if(text2num(find_id) == ARCHAEO_SYRINGE)
			var/obj/item/reagent_containers/syringe/syringe = product
			TEST_ASSERT_EQUAL(syringe.volume, 15, "The excavated syringe retains its real capacity")
			TEST_ASSERT(syringe.reagents.total_volume <= syringe.volume, "The five three-unit reagent attempts cannot overfill the syringe")
		qdel(product)

/datum/unit_test/dq_decl_archaeological_find/crystal
/datum/unit_test/dq_decl_archaeological_find/crystal/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /atom/movable)
	var/obj/item/archaeological_find/proxy = allocate(/obj/item/archaeological_find, T, ARCHAEO_CRYSTAL)
	var/list/products = adopt_products(T, before)
	TEST_ASSERT(proxy.icon_state in list("Green lump", "Phazon", "changerock"), "The crystal selects one of its three real appearances")
	TEST_ASSERT_EQUAL(proxy.icon, 'icons/obj/xenoarchaeology.dmi', "The crystal uses its excavation icon sheet")
	TEST_ASSERT_EQUAL(length(products), 1, "The crystal branch leaves one crystal or one replacement stone")
	var/atom/movable/product = products[1]
	if(QDELETED(proxy))
		TEST_ASSERT(istype(product, /obj/item/soulstone), "The replacement branch creates a real soulstone")
		TEST_ASSERT_EQUAL(product.icon_state, proxy.icon_state, "The replacement inherits the selected crystal visual")
	else
		TEST_ASSERT_EQUAL(product, proxy, "The other crystal branch retains the excavated proxy")
	TEST_ASSERT_EQUAL(product.loc, T, "The crystal stays at the excavation turf")
