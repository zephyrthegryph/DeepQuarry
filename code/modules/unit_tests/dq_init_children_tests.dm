// What types whose Initialize() only made children or only started a timer start with (they move to starts = / starts_with and
// after_init()). Written against the Initialize() form first; each holds under both.

/datum/unit_test/dq_init_children
	abstract_type = /datum/unit_test/dq_init_children

/// How many of `holder`'s internal devices are of each type, as "type=count" text, sorted.
/datum/unit_test/dq_init_children/proc/device_counts(obj/item/commcard/card)
	var/list/counts = list()
	for(var/obj/item/I as anything in card.internal_devices)
		counts["[I.type]"] = (counts["[I.type]"] || 0) + 1
	var/list/out = list()
	for(var/key in counts)
		out += "[key]=[counts[key]]"
	return jointext(sortList(out), ",")

/// A captain's cartridge carries its five devices; a chemistry cartridge its own and its medical parent's.
/datum/unit_test/dq_init_children/commcard_devices

/datum/unit_test/dq_init_children/commcard_devices/Run()
	var/obj/item/commcard/head/captain/captain = allocate(/obj/item/commcard/head/captain, dq_containment_floor())
	TEST_ASSERT_EQUAL(device_counts(captain), "/obj/item/analyzer=1,/obj/item/assembly/signaler=1,/obj/item/halogen_counter=1,/obj/item/healthanalyzer=1,/obj/item/reagent_scanner=1", "the captain's devices")
	var/obj/item/commcard/medical/chemistry/chem = allocate(/obj/item/commcard/medical/chemistry, dq_containment_floor())
	TEST_ASSERT_EQUAL(device_counts(chem), "/obj/item/halogen_counter=1,/obj/item/healthanalyzer=1,/obj/item/reagent_scanner=1", "chemistry adds its scanner to the medical devices")
	for(var/obj/item/I as anything in chem.internal_devices)
		TEST_ASSERT_EQUAL(I.loc, chem, "a device is inside its cartridge")

/// A storage box made with its contents holds them, counted.
/datum/unit_test/dq_init_children/storage_contents

/datum/unit_test/dq_init_children/storage_contents/Run()
	var/obj/item/storage/box/dosimeter/box = allocate(/obj/item/storage/box/dosimeter, dq_containment_floor())
	box.make_contents_real()
	var/films = 0
	for(var/obj/item/dosimeter_film/F in box.contents)
		films++
	TEST_ASSERT_EQUAL(films, 3, "the dosimeter box holds three films")
	TEST_ASSERT(locate(/obj/item/clothing/accessory/dosimeter) in box.contents, "and the dosimeter")
	var/obj/item/storage/excavation/picks = allocate(/obj/item/storage/excavation, dq_containment_floor())
	picks.make_contents_real()
	TEST_ASSERT_EQUAL(length(picks.contents), 7, "the excavation set holds its seven picks")

/// Firefighting foam dissolves on its own after its lifetime.
/datum/unit_test/dq_init_children/firefighting_foam_dissolves

/datum/unit_test/dq_init_children/firefighting_foam_dissolves/Run()
	scheduler_test_begin()
	var/obj/effect/effect/foam/firefighting/foam = new(dq_containment_floor())
	TEST_ASSERT(!QDELETED(foam), "the foam is there")
	scheduler_advance(10)
	TEST_ASSERT(QDELETED(foam), "it dissolved after its lifetime")
	scheduler_test_end()
