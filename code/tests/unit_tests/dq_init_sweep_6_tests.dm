/// Init sweep 6: the setup()/rolls() forms that replaced these types' Initialize() overrides keep what the overrides did.
/datum/unit_test/dq_init_sweep_6
	abstract_type = /datum/unit_test/dq_init_sweep_6

/datum/unit_test/dq_init_sweep_6/fuel_merges_and_spreads/Run()
	var/turf/T = test_floor()
	var/obj/effect/decal/cleanable/liquid_fuel/first = allocate(/obj/effect/decal/cleanable/liquid_fuel, T, 4)
	TEST_ASSERT_EQUAL(first.amount, 4, "a lone spill keeps its amount")
	var/obj/effect/decal/cleanable/liquid_fuel/second = new /obj/effect/decal/cleanable/liquid_fuel(T, 3)
	TEST_ASSERT_EQUAL(first.amount, 7, "a second spill on the tile is absorbed into the first")
	TEST_ASSERT(second, "the absorbed spill still finishes its own init")
	qdel(second)
	qdel(first)

/datum/unit_test/dq_init_sweep_6/fuel_off_turf_is_discarded/Run()
	var/obj/structure/closet/box = allocate(/obj/structure/closet, test_floor())
	var/obj/effect/decal/cleanable/liquid_fuel/fuel = new /obj/effect/decal/cleanable/liquid_fuel(box, 4)
	TEST_ASSERT(QDELETED(fuel), "spilled fuel that is not on a turf is discarded")

/datum/unit_test/dq_init_sweep_6/zip_gun_is_chambered_for_its_casing/Run()
	var/obj/item/gun/projectile/pirate/gun = allocate(/obj/item/gun/projectile/pirate, test_floor())
	TEST_ASSERT(gun.ammo_type in GLOB.global_ammo_types, "a zip gun is chambered for a known casing")
	var/obj/item/ammo_casing/casing = gun.ammo_type
	TEST_ASSERT_EQUAL(gun.caliber, initial(casing.caliber), "its caliber is its casing's")
	TEST_ASSERT(findtext(gun.desc, "Uses [GLOB.global_ammo_types[gun.ammo_type]] rounds."), "its description names the rounds")

/datum/unit_test/dq_init_sweep_6/ai_human_gender_is_rolled/Run()
	var/mob/living/carbon/human/ai_controlled/replicant/joe = allocate(/mob/living/carbon/human/ai_controlled/replicant, test_floor())
	TEST_ASSERT(joe.gender in list(MALE, FEMALE, PLURAL, NEUTER), "a human that generates its gender has one")

/datum/unit_test/dq_init_sweep_6/crystal_glows/Run()
	var/obj/machinery/crystal/crystal = allocate(/obj/machinery/crystal, test_floor())
	TEST_ASSERT(crystal.icon_state in list("crystal", "crystal2"), "a crystal shows one of its two looks")
