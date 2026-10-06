// OWNER in starts_args and make_args(), initial_contents(type, slot =, count =), owns_many(count =) and knows(LANGUAGE)
// (code/engine/lifeforms/contents.dm).

/obj/item/dq_contents_part
	name = "contents part"
	var/datum/given_owner = null

/obj/item/dq_contents_part/Initialize(mapload, datum/owner_arg)
	. = ..()
	given_owner = owner_arg

/obj/item/dq_contents_box
	name = "contents box"
	var/stocked = TRUE
	var/obj/item/dq_contents_part/keeper = null
	var/list/spares = null

CAPABILITIES(/obj/item/dq_contents_box)
	initial_contents(/obj/item/dq_contents_part, count = 3)
	initial_contents(/obj/item/dq_contents_part, args = list(OWNER), when = nameof(stocked))
	owns_one(nameof(keeper), /obj/item/dq_contents_part, starts = /obj/item/dq_contents_part, starts_args = list(OWNER))
	owns_many(nameof(spares), /obj/item/dq_contents_part, count = 2)

/obj/item/dq_contents_box/empty
	stocked = FALSE

/mob/living/simple_mob/dq_contents_speaker
	name = "speaker"

CAPABILITIES(/mob/living/simple_mob/dq_contents_speaker)
	knows(LANGUAGE_GALCOM)

/datum/unit_test/dq_lifeform_contents

/datum/unit_test/dq_lifeform_contents/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_contents_box/box = allocate(/obj/item/dq_contents_box, T)
	var/list/parts = list()
	for(var/obj/item/dq_contents_part/part in box)
		if(part != box.keeper && !(part in box.spares))
			parts += part
	TEST_ASSERT_EQUAL(length(parts), 4, "initial_contents(count = 3) and a gated initial_contents() made four plain contents")
	var/owned_by_box = 0
	for(var/obj/item/dq_contents_part/part as anything in parts)
		if(part.given_owner == box)
			owned_by_box++
	TEST_ASSERT_EQUAL(owned_by_box, 1, "OWNER in initial_contents(args =) is the holder")
	TEST_ASSERT_NOTNULL(box.keeper, "owns_one() made its starting occupant")
	TEST_ASSERT_EQUAL(box.keeper.given_owner, box, "OWNER in starts_args is the holder")
	TEST_ASSERT_EQUAL(length(box.spares), 2, "owns_many(count = 2) made two")

	var/obj/item/dq_contents_box/empty/bare = allocate(/obj/item/dq_contents_box/empty, T)
	var/plain = 0
	for(var/obj/item/dq_contents_part/part in bare)
		if(part != bare.keeper && !(part in bare.spares))
			plain++
	TEST_ASSERT_EQUAL(plain, 3, "a when = that is false skips its initial_contents()")

	var/mob/living/simple_mob/dq_contents_speaker/speaker = allocate(/mob/living/simple_mob/dq_contents_speaker, T)
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_GALCOM] in speaker.languages, "knows() gives the mob the language at init")
