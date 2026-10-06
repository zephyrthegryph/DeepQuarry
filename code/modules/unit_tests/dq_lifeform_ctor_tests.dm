// Constructor arguments as params (code/engine/lifeforms/params.dm): param(pos =), the setter a param applies at init (apply =), keep = FALSE,
// and the subtypes whose overrides only passed constants up (now var defaults). Each case is a positional `new T(loc, ...)` the old
// Initialize(mapload, ...) override took.

/datum/unit_test/dq_lifeform_ctor_params

/datum/unit_test/dq_lifeform_ctor_params/Run()
	var/turf/T = dq_containment_floor()

	var/obj/item/paper/P = allocate(/obj/item/paper, T, "Hello", "A note")
	TEST_ASSERT(findtext(P.info, "Hello"), "a paper's text is its first argument")
	TEST_ASSERT_EQUAL(P.name, "A note", "and its title the second")

	var/obj/item/stack/S = allocate(/obj/item/stack/material/steel/hull, T, 5)
	TEST_ASSERT_EQUAL(S.get_amount(), 5, "a stack's amount is its first argument")

	var/obj/effect/resonance/R = allocate(/obj/effect/resonance, T, null, 3 SECONDS)
	TEST_ASSERT_EQUAL(R.timetoburst, 3 SECONDS, "a resonance field's burst delay is its second argument")

	var/obj/structure/simple_door/iron/door = allocate(/obj/structure/simple_door/iron, T)
	TEST_ASSERT_EQUAL(door.material?.name, MAT_IRON, "a subtype that passed its material up has it as its param's default")
	var/obj/structure/simple_door/gold = allocate(/obj/structure/simple_door, T, MAT_GOLD)
	TEST_ASSERT_EQUAL(gold.material?.name, MAT_GOLD, "a door's material is its first argument, applied by its setter")

	var/obj/structure/bed/chair/comfy/brown/chair = allocate(/obj/structure/bed/chair/comfy/brown, T)
	TEST_ASSERT_EQUAL(chair.padding_material?.name, MAT_CLOTH_BROWN, "a chair subtype's padding is its param's default")

	var/obj/machinery/conveyor/belt = allocate(/obj/machinery/conveyor, T, EAST, TRUE)
	TEST_ASSERT_EQUAL(belt.dir, EAST, "a conveyor faces its first argument")
	TEST_ASSERT(belt.operating, "and runs when its second argument says so")

	var/obj/effect/decal/cleanable/crayon/C = allocate(/obj/effect/decal/cleanable/crayon, T, "#FF0000", "#00FF00", "graffiti")
	TEST_ASSERT_EQUAL(C.art_color, "#FF0000", "a crayon drawing's colour is its first argument")
	TEST_ASSERT_EQUAL(C.name, "graffiti", "and its kind the third, named by its setter")

	var/obj/item/sample/sample = allocate(/obj/item/sample, T, door)
	TEST_ASSERT_NULL(sample.taken_from, "a keep = FALSE param is dropped once Initialize() returned")
