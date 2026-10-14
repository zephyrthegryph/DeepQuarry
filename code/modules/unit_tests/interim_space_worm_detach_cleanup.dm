/// Actual short-worm construction supplies the original linked body; Detach rewires its back half and disposes of one segment.
/datum/unit_test/interim_space_worm_detach_cleanup
	var/kill_back_half = FALSE

/datum/unit_test/interim_space_worm_detach_cleanup/dead
	kill_back_half = TRUE

/// A fixture's normal teardown must not itself create additional heads by recursively detaching still-linked bodies.
/datum/unit_test/interim_space_worm_detach_cleanup/proc/cleanup_fixture_worms(turf/T)
	var/list/worms = contents_of(T, /mob/living/simple_mob/animal/space/space_worm)
	for(var/mob/living/simple_mob/animal/space/space_worm/W as anything in worms)
		rel_clear(W, nameof(W.previous))
		rel_clear(W, nameof(W.next))
	for(var/mob/living/simple_mob/animal/space/space_worm/W as anything in worms)
		if(!QDELETED(W))
			qdel(W)

/datum/unit_test/interim_space_worm_detach_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	TEST_ASSERT_EQUAL(length(contents_of(T, /mob/living/simple_mob/animal/space/space_worm)), 0, "the real fixture floor starts without unrelated worms")
	defer_cleanup(src, PROC_REF(cleanup_fixture_worms), T)
	var/mob/living/simple_mob/animal/space/space_worm/head/short/head = allocate(/mob/living/simple_mob/animal/space/space_worm/head/short, T)
	var/list/original_worms = contents_of(T, /mob/living/simple_mob/animal/space/space_worm)
	for(var/mob/living/simple_mob/animal/space/space_worm/W as anything in original_worms)
		own(W)
	TEST_ASSERT_EQUAL(length(original_worms), 4, "the actual short-head constructor creates its three original body segments")
	var/mob/living/simple_mob/animal/space/space_worm/front = head.previous
	TEST_ASSERT_NOTNULL(front, "the actual head links its first original segment")
	var/mob/living/simple_mob/animal/space/space_worm/source = front.previous
	TEST_ASSERT_NOTNULL(source, "the actual constructor links its original middle segment")
	var/mob/living/simple_mob/animal/space/space_worm/back = source.previous
	TEST_ASSERT_NOTNULL(back, "the actual constructor links its original back segment")
	TEST_ASSERT_NULL(back.previous, "the actual third original segment is the tail")
	TEST_ASSERT_EQUAL(front.next, head, "the actual front segment retains its original head link")
	TEST_ASSERT_EQUAL(source.next, front, "the actual middle segment retains its original front link")
	TEST_ASSERT_EQUAL(back.next, source, "the actual back segment retains its original middle link")
	TEST_ASSERT_EQUAL(back.stat, CONSCIOUS, "the original back segment starts conscious")
	var/obj/item/pen/cargo = allocate(/obj/item/pen, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	source.eat_consume(cargo)
	TEST_ASSERT_EQUAL(cargo.loc, source, "the real public eating effect puts the exact original pen inside the middle segment")
	TEST_ASSERT_NULL(source.Detach(kill_back_half), "actual detachment preserves its implicit null return")
	var/list/products = contents_of(T, /mob/living/simple_mob/animal/space/space_worm/head/severed) - original_worms
	for(var/mob/living/simple_mob/animal/space/space_worm/head/severed/P as anything in products)
		own(P)
	TEST_ASSERT(QDELETED(source), "actual detachment consumes the exact original middle segment")
	TEST_ASSERT_EQUAL(length(products), 1, "actual detachment creates exactly one real severed head")
	var/mob/living/simple_mob/animal/space/space_worm/head/severed/product = products[1]
	TEST_ASSERT_EQUAL(product.type, /mob/living/simple_mob/animal/space/space_worm/head/severed, "actual detachment creates the canonical severed-head type")
	TEST_ASSERT_EQUAL(product.previous, back, "the real replacement head links to the exact original back segment")
	TEST_ASSERT_EQUAL(back.next, product, "the exact original back segment links to the real replacement head")
	TEST_ASSERT_NULL(product.next, "the actual replacement head has no forward segment")
	TEST_ASSERT_EQUAL(product.stat, kill_back_half ? DEAD : CONSCIOUS, "the real replacement head has the requested actual survival outcome")
	TEST_ASSERT_EQUAL(back.stat, kill_back_half ? DEAD : CONSCIOUS, "the actual optional death chain preserves the requested original tail outcome")
	TEST_ASSERT(!QDELETED(back), "the original back segment survives as the original live segment or corpse")
	TEST_ASSERT(!QDELETED(product), "the real canonical replacement survives original middle-segment teardown")
	TEST_ASSERT_EQUAL(product.loc, T, "the real canonical replacement stays on the original floor")
	TEST_ASSERT(!QDELETED(head) && !QDELETED(front), "actual detachment preserves the exact original forward head and segment")
	TEST_ASSERT_EQUAL(head.stat, CONSCIOUS, "the exact original forward head remains conscious")
	TEST_ASSERT_EQUAL(front.stat, CONSCIOUS, "the exact original forward segment remains conscious")
	TEST_ASSERT_EQUAL(head.previous, front, "the original forward head retains its original segment")
	TEST_ASSERT_EQUAL(front.next, head, "the original forward segment retains its original head")
	TEST_ASSERT_NULL(front.previous, "real original-source deletion clears the forward segment's deleted middle link")
	TEST_ASSERT(!QDELETED(cargo), "unchanged source teardown preserves the exact original swallowed pen")
	TEST_ASSERT_EQUAL(cargo.loc, T, "unchanged source teardown dumps the exact original pen onto the original floor")
	TEST_ASSERT(!QDELETED(wrench), "actual detachment preserves the exact original unrelated tool")
	TEST_ASSERT_EQUAL(wrench.loc, T, "actual detachment preserves the unrelated tool's original floor")
