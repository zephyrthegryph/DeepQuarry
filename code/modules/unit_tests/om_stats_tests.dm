/datum/object_model/stat_block/test_minimum

/datum/object_model/stat_block/test_minimum/definitions()
	var/static/list/defs = list(list(10, OM_STAT_MIN, 0, 100))
	return defs

/datum/unit_test/om_stat_minimum_rule
	needs_test_block = FALSE

/datum/unit_test/om_stat_minimum_rule/Run()
	var/datum/object_model/stat_block/test_minimum/block = new
	var/datum/source = new
	var/datum/object_model/stat_draft/draft = new /datum/object_model/stat_draft(/datum/object_model/stat_block/test_minimum, 1)
	TEST_ASSERT_EQUAL(block.get_stat(1), 10, "minimum stat begins at baseline")
	draft.contribute(1, 7, OM_STAT_MIN)
	TEST_ASSERT(block.set_source(source, draft), "minimum contribution is accepted")
	TEST_ASSERT_EQUAL(block.get_stat(1), 7, "minimum rule chooses the lower contribution")
	TEST_ASSERT(block.set_base_stat(1, -5), "base stat accepts a lower value")
	TEST_ASSERT_EQUAL(block.get_stat(1), 0, "minimum result is clamped to its declared floor")
	qdel(block)
	qdel(draft)
	qdel(source)

/datum/unit_test/om_generated_stats
	needs_test_block = FALSE

/datum/unit_test/om_generated_stats/Run()
	var/datum/object_model/stat_block/example/B = new
	TEST_ASSERT_EQUAL(B.get_accuracy(), 0, "baseline accuracy")
	TEST_ASSERT_EQUAL(B.get_attack_speed(), 1, "baseline speed")
	TEST_ASSERT(B.set_base_accuracy(20), "changed base accepted")
	TEST_ASSERT(!B.set_base_accuracy(20), "equal base ignored")
	var/datum/source_a = new
	var/datum/source_b = new
	var/datum/object_model/stat_draft/example/A = new
	A.add_accuracy(-15)
	A.add_accuracy(-5)
	A.multiply_attack_speed(0.5)
	A.grant_sight_flags(1)
	TEST_ASSERT(B.set_source(source_a, A), "first source installed")
	TEST_ASSERT_EQUAL(B.get_accuracy(), 0, "source addition and baseline combine")
	TEST_ASSERT_EQUAL(B.get_attack_speed(), 0.5, "multiplication combines")
	TEST_ASSERT_EQUAL(B.get_sight_flags(), 1, "flags combine")
	var/datum/object_model/stat_draft/example/C = new
	C.add_accuracy(-200)
	C.multiply_attack_speed(2)
	C.grant_sight_flags(2)
	TEST_ASSERT(B.set_source(source_b, C), "second source installed")
	TEST_ASSERT_EQUAL(B.get_accuracy(), -100, "bounded additive value")
	TEST_ASSERT_EQUAL(B.get_attack_speed(), 1, "source multipliers combine")
	TEST_ASSERT_EQUAL(B.get_sight_flags(), 3, "flags OR")
	TEST_ASSERT(B.remove_source(source_b), "source removed")
	TEST_ASSERT_EQUAL(B.get_accuracy(), 0, "source removal refreshes")
	TEST_ASSERT(!B.remove_source(source_b), "missing source ignored")
	qdel(source_a)
	TEST_ASSERT_EQUAL(B.get_accuracy(), 20, "deleted source removes contribution")
	var/datum/owned = new
	var/datum/object_model/stat_block/example/O = new(owned)
	TEST_ASSERT_EQUAL(O.get_accuracy(), 0, "owned block is usable")
	qdel(owned)
	TEST_ASSERT(QDELETED(O), "owner deletion deletes stat block")
	qdel(B)
	qdel(A)
	qdel(C)
	qdel(source_b)
