#define DQ_NATIVE_NUMERIC_VALUE "dq_native_numeric_value"

/obj/item/dq_native_numeric_source
	var/value = 2
TRACKED(/obj/item/dq_native_numeric_source, value)

/datum/property_def/dq_native_numeric
	id = DQ_NATIVE_NUMERIC_VALUE
	name = "Mass"
	unit = PROP_UNIT_KILOGRAMS
	aggregator = PROP_AGG_SUM
	high_word = "heavy"
	low_word = "light"
	test_only = TRUE

/datum/property_provider/dq_native_numeric
	property = DQ_NATIVE_NUMERIC_VALUE
	source = PROP_SOURCE_DOMAIN
	applies_to = /obj/item/dq_native_numeric_source
	unit = PROP_UNIT_KILOGRAMS
	test_only = TRUE
/datum/property_provider/dq_native_numeric/instance_value(datum/D)
	var/obj/item/dq_native_numeric_source/S = D
	return S.value
/datum/property_provider/dq_native_numeric/requirement_read_keys(datum/D)
	var/obj/item/dq_native_numeric_source/S = D
	return list(list(S, nameof(S.value)))

/datum/unit_test/dq_native_numeric_roles/Run()
	var/datum/property_def/D = allocate(/datum/property_def/dq_native_numeric)
	var/datum/property_provider/P = allocate(/datum/property_provider/dq_native_numeric)
	var/datum/property_registry/R = allocate(/datum/property_registry, list(D), list(P))
	TEST_ASSERT(!length(R.errors), "private numeric registry is valid")
	var/obj/item/dq_native_numeric_source/left = allocate(/obj/item/dq_native_numeric_source)
	var/obj/item/dq_native_numeric_source/right = allocate(/obj/item/dq_native_numeric_source)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.target = left
	A.holder = right
	right.set_value(3)
	var/datum/entry/part/req/N = req_property_compare(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_LT, DQ_NATIVE_NUMERIC_VALUE, ON_TARGET, ON_HOLDER, registry = R)
	TEST_ASSERT(isnull(op_req_check(A, N)), "2 kg target is below 3 kg holder")
	var/list/keys = N.read_keys(A)
	TEST_ASSERT_EQUAL(length(keys), 3, "registry link and both dynamic sides have real dependencies")
	TEST_ASSERT_EQUAL(keys[2][1], left, "left dependency selects target")
	TEST_ASSERT_EQUAL(keys[3][1], right, "right dependency selects holder")
	right.set_value(1)
	TEST_ASSERT(!isnull(op_req_check(A, N)), "changing right source refuses")
	var/datum/entry/part/req/B = req_band(DQ_NATIVE_NUMERIC_VALUE, 2, PROP_UNIT_KILOGRAMS, 3, PROP_UNIT_KILOGRAMS, registry = R)
	TEST_ASSERT(isnull(op_req_check(A, B)), "lower band bound is inclusive")
	left.set_value(3)
	TEST_ASSERT(isnull(op_req_check(A, B)), "upper band bound is inclusive")
	left.set_value(4)
	TEST_ASSERT(!isnull(op_req_check(A, B)), "outside band refuses")
	left.set_value(null)
	var/datum/entry/part/req/negative = req_measure_not(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_GT, 2, PROP_UNIT_KILOGRAMS, registry = R)
	TEST_ASSERT_EQUAL(op_req_check(A, negative), "mass unknown", "inverted comparison retains missing-value refusal")
	var/datum/entry/part/req/override = req_measure(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_GT, 2, PROP_UNIT_KILOGRAMS, because = "numeric unavailable", registry = R)
	TEST_ASSERT_EQUAL(op_req_check(A, override), "numeric unavailable", "because overrides missing-value reason")
	qdel(R)
	TEST_ASSERT_EQUAL(op_req_check(A, N), "numeric requirement registry unavailable", "deleted borrowed registry refuses safely")

/obj/item/dq_native_numeric_source
	var/datum/property_registry/private_registry
	var/completed = 0
CAPABILITIES(/obj/item/dq_native_numeric_source)
	ref_one(nameof(private_registry), /datum/property_registry)
	op("numeric_wait", menu(), needs(part_make(/datum/entry/part/req/dq_native_numeric_wait)), wait(10 SECONDS), then(PROC_REF(finish_numeric)))
/obj/item/dq_native_numeric_source/proc/finish_numeric(datum/act/op/A)
	completed++
	return OP_OK
/datum/entry/part/req/dq_native_numeric_wait/proc/leaf(datum/act/op/A)
	var/obj/item/dq_native_numeric_source/F = A.holder
	return req_property_compare(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_LT, DQ_NATIVE_NUMERIC_VALUE, ON_HOLDER, ON_HELD, because = "numeric budget exceeded", registry = F.private_registry)
/datum/entry/part/req/dq_native_numeric_wait/check(datum/act/op/A)
	var/obj/item/dq_native_numeric_source/F = A.holder
	if(!F.private_registry || QDELETED(F.private_registry))
		return "numeric registry deleted"
	var/datum/entry/part/req/N = leaf(A)
	return N.check(A)
/datum/entry/part/req/dq_native_numeric_wait/read_keys(datum/act/op/A)
	var/obj/item/dq_native_numeric_source/F = A.holder
	. = list()
	if(!F.private_registry || QDELETED(F.private_registry))
		return
	var/datum/entry/part/req/N = leaf(A)
	. += N.read_keys(A)

/datum/unit_test/dq_native_numeric_pending_wakes/Run()
	test_driver_begin()
	var/datum/property_def/D = allocate(/datum/property_def/dq_native_numeric)
	var/datum/property_provider/P = allocate(/datum/property_provider/dq_native_numeric)
	var/datum/property_registry/registry = allocate(/datum/property_registry, list(D), list(P))
	TEST_ASSERT(!length(registry.errors), "actual private registry validates")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/dq_native_numeric_source/left = allocate(/obj/item/dq_native_numeric_source, get_turf(H))
	var/obj/item/dq_native_numeric_source/right = allocate(/obj/item/dq_native_numeric_source, get_turf(H))
	rel_set(left, nameof(left.private_registry), registry)
	right.set_value(3)
	H.put_in_active_hand(right)
	TEST_ASSERT_EQUAL(H.get_active_hand(), right, "actual held operand is equipped")
	var/datum/op_result/result = test_menu(H, left, "numeric_wait")
	var/datum/pending_op/pending = op_pending_for(H, "numeric_wait")
	TEST_ASSERT(pending?.active && isnull(result.outcome), "real declared numeric op waits")
	TEST_ASSERT((left.rx?.observed?[nameof(left.value)] || 0) > 0, "left property has actual pending subscription")
	TEST_ASSERT((right.rx?.observed?[nameof(right.value)] || 0) > 0, "dynamic RHS property has actual pending subscription")
	right.set_value(1)
	test_time(1 TICK)
	TEST_ASSERT_EQUAL(result.outcome, ACT_REFUSED, "actual RHS setter wake cancels wait")
	TEST_ASSERT_EQUAL(reason_text(result.reason), "numeric budget exceeded", "RHS wake preserves exact refusal")
	TEST_ASSERT_EQUAL(left.completed, 0, "refused wait never applies effect")
	right.set_value(3)
	result = test_menu(H, left, "numeric_wait")
	TEST_ASSERT(op_pending_for(H, "numeric_wait")?.active, "recovery starts second real pending")
	left.set_value(4)
	test_time(1 TICK)
	TEST_ASSERT_EQUAL(result.outcome, ACT_REFUSED, "actual left setter wake cancels wait")
	TEST_ASSERT_NULL(op_pending_for(H, "numeric_wait"), "no orphan pending after either wake")
	TEST_ASSERT_EQUAL(left.rx?.observed?[nameof(left.value)] || 0, 0, "left reader released")
	TEST_ASSERT_EQUAL(right.rx?.observed?[nameof(right.value)] || 0, 0, "right reader released")
	left.set_value(2)
	result = test_menu(H, left, "numeric_wait")
	TEST_ASSERT(op_pending_for(H, "numeric_wait")?.active, "registry deletion proof begins real wait")
	var/datum/entry/part/req/numeric/native_leaf = req_property_compare(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_LT, DQ_NATIVE_NUMERIC_VALUE, ON_HOLDER, ON_HELD, because = "numeric budget exceeded", registry = registry)
	TEST_ASSERT((native_leaf.rx?.observed?[nameof(native_leaf.registry_static)] || 0) > 0, "pending actually subscribes numeric registry reference")
	qdel(registry)
	test_time(1 TICK)
	TEST_ASSERT_NULL(native_leaf.registry_static, "borrowed numeric registry relation clears on death")
	TEST_ASSERT_EQUAL(result.outcome, ACT_REFUSED, "registry reference deletion wakes and refuses pending op")
	TEST_ASSERT_EQUAL(reason_text(result.reason), "numeric registry deleted", "registry deletion refusal retained")
	TEST_ASSERT_NULL(op_pending_for(H, "numeric_wait"), "registry deletion leaves no pending operation")
	TEST_ASSERT_EQUAL(native_leaf.rx?.observed?[nameof(native_leaf.registry_static)] || 0, 0, "registry reference reader released after cancellation")
	test_driver_end()

/datum/unit_test/dq_native_numeric_acceptance_roles/Run()
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/dq_native_numeric_source/candidate = allocate(/obj/item/dq_native_numeric_source)
	var/obj/item/dq_native_numeric_source/destination = allocate(/obj/item/dq_native_numeric_source)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.actor = actor
	A.wearer = wearer
	A.mover = mover
	A.destination = destination
	A.target = candidate
	TEST_ASSERT_EQUAL(op_subject(A, ON_ACTOR), actor, "actor is distinct")
	TEST_ASSERT_EQUAL(op_subject(A, ON_WEARER), wearer, "wearer never falls back to mover or actor")
	TEST_ASSERT_EQUAL(op_subject(A, ON_MOVER), mover, "mover never falls back to wearer or actor")
	TEST_ASSERT_EQUAL(op_subject(A, ON_DESTINATION), destination, "physical holder selector is distinct from candidate")
	var/datum/property_def/D = allocate(/datum/property_def/dq_native_numeric)
	var/datum/property_provider/P = allocate(/datum/property_provider/dq_native_numeric)
	var/datum/property_registry/R = allocate(/datum/property_registry, list(D), list(P))
	var/datum/entry/part/req/N = req_measure(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_EQ, 2, PROP_UNIT_KILOGRAMS, of = ON_DESTINATION, registry = R)
	TEST_ASSERT(isnull(op_req_check(A, N)), "destination numeric role reads actual source")
	var/list/keys = N.read_keys(A)
	TEST_ASSERT_EQUAL(keys[2][1], destination, "destination metadata selects physical holder")
	destination.set_value(3)
	TEST_ASSERT(!isnull(op_req_check(A, N)), "destination setter changes actual admission result")
	A.wearer = null
	N = req_measure(DQ_NATIVE_NUMERIC_VALUE, SIM_COMPARE_EQ, 2, PROP_UNIT_KILOGRAMS, of = ON_WEARER, registry = R)
	TEST_ASSERT_EQUAL(op_req_check(A, N), "needs a wearer", "missing explicit role refuses rather than substituting actor")
	TEST_ASSERT_NULL(op_subject(A, ON_WEARER), "missing wearer stays absent")

#undef DQ_NATIVE_NUMERIC_VALUE
