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

// Rolled contents (init-objects lane): initial_contents(nameof(type_var)), pick_one(), PROC_REF() answering types, counts or instances, chance =.
/obj/item/dq_contents_part/other
	name = "other part"

/obj/item/dq_rolled_box
	name = "rolled box"
	var/part_type = /obj/item/dq_contents_part/other
	var/list/rolled_types = list(/obj/item/dq_contents_part = 2)

CAPABILITIES(/obj/item/dq_rolled_box)
	initial_contents(nameof(part_type))
	initial_contents(nameof(rolled_types))
	initial_contents(pick_one(list(/obj/item/dq_contents_part/other = 1, /obj/item/dq_contents_part = 0)))
	initial_contents(PROC_REF(roll_instances))
	initial_contents(/obj/item/dq_contents_part, chance = 0)
	initial_contents(/obj/item/dq_contents_part/other, chance = 100)

/obj/item/dq_rolled_box/proc/roll_instances(datum/roller/R)
	var/obj/item/dq_contents_part/made = new
	made.name = "made part"
	return list(made, /obj/item/dq_contents_part/other)

/datum/unit_test/dq_lifeform_rolled_contents

/datum/unit_test/dq_lifeform_rolled_contents/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_rolled_box/box = allocate(/obj/item/dq_rolled_box, T)
	var/plain = 0
	var/other = 0
	var/made = 0
	for(var/obj/item/dq_contents_part/part in box)
		if(part.name == "made part")
			made++
		else if(istype(part, /obj/item/dq_contents_part/other))
			other++
		else
			plain++
	TEST_ASSERT_EQUAL(made, 1, "a roll proc's instance is placed in the holder")
	TEST_ASSERT_EQUAL(other, 4, "nameof(type_var), a weighted pick_one(), a roll proc's type and chance = 100 each made an other part")
	TEST_ASSERT_EQUAL(plain, 2, "nameof(list var) made its type = count, and chance = 0 made nothing")

// lives_for(nameof(var)) (code/engine/lifeforms/lifetimes.dm): the holder lapses that long after its init; a var of 0 never lapses.
/obj/effect/dq_lives_for
	name = "short-lived"
	var/ttl = 2 SECONDS

CAPABILITIES(/obj/effect/dq_lives_for)
	lives_for(nameof(ttl))

/obj/effect/dq_lives_for/forever
	ttl = 0

/datum/unit_test/dq_lifeform_lives_for

/datum/unit_test/dq_lifeform_lives_for/Run()
	scheduler_test_begin()
	var/obj/effect/dq_lives_for/brief = new(dq_containment_floor())
	var/obj/effect/dq_lives_for/forever/lasting = new(dq_containment_floor())
	scheduler_advance(1)
	TEST_ASSERT(!QDELETED(brief), "it lives until its time is up")
	scheduler_advance(2)
	TEST_ASSERT(QDELETED(brief), "it lapsed after its ttl")
	TEST_ASSERT(!QDELETED(lasting), "a ttl of 0 never lapses")
	qdel(lasting)
	scheduler_test_end()
