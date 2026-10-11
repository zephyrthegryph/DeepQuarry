// Private fixture symbols precede every use in this test translation unit.
#define DQ_RULE_LEFT "dq-rule-left"
#define DQ_RULE_RIGHT "dq-rule-right"
#define DQ_RULE_LEFT_KEY "dq-rule-left-key"
#define DQ_RULE_RIGHT_KEY "dq-rule-right-key"

// Native simulation condition compiler and lifetime tests.
/datum/unit_test/dq_simulation_condition_native/proc/compiled(spec)
	var/datum/simulation_condition_compiler/C = new
	var/datum/simulation_condition/N = C.compile(spec)
	TEST_ASSERT(!length(C.errors), "Native spec compiles: [jointext(C.errors, "; ")]")
	qdel(C)
	return N

/datum/unit_test/dq_simulation_condition_native/proc/rejected(spec, text)
	var/datum/simulation_condition_compiler/C = new
	var/datum/simulation_condition/N = C.compile(spec)
	TEST_ASSERT(length(C.errors), "Malformed spec rejects")
	TEST_ASSERT(findtext(jointext(C.errors, "; "), text), "Expected diagnostic [text]")
	qdel(N)
	qdel(C)

/datum/unit_test/dq_simulation_condition_native/Run()
	var/obj/item/dq_rule_test/I = allocate(/obj/item/dq_rule_test)
	var/datum/simulation_condition/N = compiled(cond_measure(PROP_SIZE_CLASS, SIM_COMPARE_GTE, SIZE_CLASS(ITEMSIZE_SMALL)))
	TEST_ASSERT(N.holds(I), "Inclusive equal-size boundary allows")
	qdel(N)
	N = compiled(cond_measure(PROP_SIZE_CLASS, SIM_COMPARE_GT, SIZE_CLASS(ITEMSIZE_SMALL)))
	TEST_ASSERT(!N.holds(I), "Strict equal-size boundary refuses")
	qdel(N)
	N = compiled(cond_band(PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_SMALL), SIZE_CLASS(ITEMSIZE_SMALL)))
	TEST_ASSERT(N.holds(I), "Band endpoints are inclusive")
	qdel(N)
	N = compiled(cond_not(cond_measure(PROP_TEMPERATURE, SIM_COMPARE_GTE, KELVIN(300))))
	var/datum/no_properties = new
	TEST_ASSERT_NULL(dq_property(no_properties, PROP_TEMPERATURE), "Missing-value fixture really has no measurement")
	TEST_ASSERT(!N.holds(no_properties), "Negated missing comparison remains false, matching old operator negation")
	qdel(no_properties)
	qdel(N)
	N = compiled(cond_all(cond_measure(PROP_SIZE_CLASS, SIM_COMPARE_GTE, SIZE_CLASS(0)), cond_any(cond_measure(PROP_MASS, SIM_COMPARE_GT, KG(0)), cond_not(cond_measure(PROP_TEMPERATURE, SIM_COMPARE_LT, KELVIN(300))))))
	TEST_ASSERT_EQUAL(length(N.leaves()), 3, "Metadata visits every branch independently of short-circuit truth")
	var/list/leaves = N.leaves()
	var/datum/simulation_condition/first = leaves[1]
	var/datum/simulation_condition/second = leaves[2]
	var/datum/simulation_condition/third = leaves[3]
	TEST_ASSERT_EQUAL(first.property, PROP_SIZE_CLASS, "First declaration order retained")
	TEST_ASSERT_EQUAL(second.property, PROP_MASS, "Second declaration order retained")
	TEST_ASSERT_EQUAL(third.compare, SIM_COMPARE_GTE, "NOT inverts operator structurally")
	qdel(N)
	rejected(cond_measure("fixture-unknown-property", SIM_COMPARE_GT, KG(1)), "unknown property")
	rejected(cond_measure(PROP_TEMPERATURE, SIM_COMPARE_GT, KG(1)), "compares")
	rejected(cond_compare(PROP_TEMPERATURE, SIM_COMPARE_GT, PROP_MASS), "compares")
	rejected(cond_measure(PROP_TEMPERATURE, "invalid-op", KELVIN(300)), "unknown comparison")
	rejected(cond_band(PROP_TEMPERATURE, KELVIN(400), KELVIN(300)), "reversed")
	rejected(cond_measure(PROP_TEMPERATURE, SIM_COMPARE_GT, KELVIN(300), subject = "actor"), "no actor")
/datum/unit_test/dq_simulation_condition_native/empty_groups/Run()
	var/datum/simulation_condition/N = compiled(cond_all())
	var/obj/item/dq_rule_test/I = allocate(/obj/item/dq_rule_test)
	TEST_ASSERT(N.holds(I), "Empty AND is true")
	TEST_ASSERT_EQUAL(length(N.leaves()), 0, "Empty group has no property leaves")
	TEST_ASSERT_NULL(N.children, "Empty group needs no allocated ownership list")
	qdel(N)
	N = compiled(cond_any())
	TEST_ASSERT(!N.holds(I), "Empty OR is false")
	qdel(N)
	N = compiled(cond_not(cond_all()))
	TEST_ASSERT(!N.holds(I), "NOT empty AND is false")
	qdel(N)
	N = compiled(cond_not(cond_any()))
	TEST_ASSERT(N.holds(I), "NOT empty OR is true")
	qdel(N)
	var/datum/simulation_condition_compiler/C = new
	N = C.compile(cond_all(cond_measure(PROP_SIZE_CLASS, SIM_COMPARE_GTE, SIZE_CLASS(0)), cond_measure("unknown-property-second-child", SIM_COMPARE_GT, KG(1))))
	TEST_ASSERT_NULL(N, "Invalid child rejects entire compiled group rather than returning a partial allow")
	TEST_ASSERT(length(C.errors), "Child diagnostic retained")
	qdel(C)

/datum/unit_test/dq_rule_native_private_registry_deleted/Run()
	var/datum/property_def/L = new /datum/property_def/dq_rule_left
	var/datum/property_def/R = new /datum/property_def/dq_rule_right
	var/datum/property_provider/LP = new /datum/property_provider/dq_rule_left
	var/datum/property_provider/RP = new /datum/property_provider/dq_rule_right
	var/datum/property_registry/registry = new(list(L, R), list(LP, RP))
	var/datum/simulation_condition_compiler/C = new(registry)
	var/datum/simulation_condition/N = C.compile(cond_measure(DQ_RULE_LEFT, SIM_COMPARE_GTE, RATIO(0)))
	TEST_ASSERT(!length(C.errors), "Private registry compiles a real numeric condition")
	var/obj/item/dq_rule_private/I = allocate(/obj/item/dq_rule_private)
	TEST_ASSERT(N.holds(I), "Condition permits while borrowed registry is alive")
	var/datum/rule_trigger/T = new
	rel_set(T, nameof(T.registry_static), registry)
	T.value_property = DQ_RULE_RIGHT
	TEST_ASSERT_EQUAL(T.level_for(I), 1, "Dynamic threshold reads actual private registry before deletion")
	qdel(registry)
	TEST_ASSERT_NULL(N.registry_static, "Registry deletion clears compiled borrowed reference")
	TEST_ASSERT(!N.holds(I), "Unavailable registry fails closed instead of crashing")
	TEST_ASSERT_NULL(T.level_for(I), "Unavailable dynamic threshold is absent")
	TEST_ASSERT_NULL(C.measure(DQ_RULE_LEFT), "Compiler with deleted borrowed registry rejects further measurement")
	TEST_ASSERT(findtext(jointext(C.errors, "; "), "registry is unavailable"), "Unavailable-registry diagnostic is precise")
	qdel(T)
	qdel(N)
	qdel(C)
	qdel(L)
	qdel(R)
	qdel(LP)
	qdel(RP)

// Private property-registry fixtures exercise dependency wakes and cumulative holds.

/obj/item/dq_rule_private
	var/left = 0
	var/right = 1
	var/fires = 0
	var/exits = 0
TRACKED(/obj/item/dq_rule_private, left)
TRACKED(/obj/item/dq_rule_private, right)
CAPABILITIES(/obj/item/dq_rule_private)
	on_change(nameof(left), ANY, then(PROC_REF(left_changed)))
	on_change(nameof(right), ANY, then(PROC_REF(right_changed)))
/obj/item/dq_rule_private/proc/left_changed(datum/act/A)
	dq_rule_binding_of(src)?.key_published(DQ_RULE_LEFT_KEY)
/obj/item/dq_rule_private/proc/right_changed(datum/act/A)
	dq_rule_binding_of(src)?.key_published(DQ_RULE_RIGHT_KEY)
/obj/item/dq_rule_private/proc/fired_rule(datum/rule/R)
	fires++
/obj/item/dq_rule_private/proc/exited_rule(datum/rule/R)
	exits++

/datum/property_def/dq_rule_left
	id = DQ_RULE_LEFT
	unit = PROP_UNIT_RATIO
	dm_key_kind = DQ_RULE_LEFT_KEY
	test_only = TRUE
/datum/property_def/dq_rule_right
	id = DQ_RULE_RIGHT
	unit = PROP_UNIT_RATIO
	dm_key_kind = DQ_RULE_RIGHT_KEY
	test_only = TRUE
/datum/property_provider/dq_rule_left
	property = DQ_RULE_LEFT
	source = PROP_SOURCE_TYPE
	unit = PROP_UNIT_RATIO
	applies_to = /obj/item/dq_rule_private
	test_only = TRUE
/datum/property_provider/dq_rule_left/instance_value(datum/D)
	var/obj/item/dq_rule_private/I = D
	return I.left
/datum/property_provider/dq_rule_right
	property = DQ_RULE_RIGHT
	source = PROP_SOURCE_TYPE
	unit = PROP_UNIT_RATIO
	applies_to = /obj/item/dq_rule_private
	test_only = TRUE
/datum/property_provider/dq_rule_right/instance_value(datum/D)
	var/obj/item/dq_rule_private/I = D
	return I.right

/datum/rule/dq_private_difference
	test_only = TRUE
	once = FALSE
	effect_proc = /obj/item/dq_rule_private/proc/fired_rule
	exit_proc = /obj/item/dq_rule_private/proc/exited_rule
/datum/rule/dq_private_difference/rule_condition()
	return cond_compare(DQ_RULE_LEFT, SIM_COMPARE_GT, DQ_RULE_RIGHT)
/datum/rule/dq_private_difference/hold
	hold_for = 2 SECONDS

/datum/unit_test/dq_rule_native_private_wakes/Run()
	var/datum/property_def/L = new /datum/property_def/dq_rule_left
	var/datum/property_def/R = new /datum/property_def/dq_rule_right
	var/datum/property_provider/LP = new /datum/property_provider/dq_rule_left
	var/datum/property_provider/RP = new /datum/property_provider/dq_rule_right
	var/datum/property_registry/registry = new(list(L, R), list(LP, RP))
	TEST_ASSERT(!length(registry.errors), "Private registry is genuinely valid")
	var/datum/rule/rule = new /datum/rule/dq_private_difference
	TEST_ASSERT(rule.compile(registry), "Native dynamic comparison compiles with private registry")
	TEST_ASSERT_EQUAL(length(rule.triggers), 2, "Both dynamic dependencies receive real key subscriptions")
	var/datum/rule_trigger/first = rule.triggers[1]
	var/datum/rule_trigger/second = rule.triggers[2]
	TEST_ASSERT_EQUAL(first.property, DQ_RULE_LEFT, "Left metadata preserves declaration order")
	TEST_ASSERT_EQUAL(second.property, DQ_RULE_RIGHT, "Dynamic RHS has separate dependency")
	var/obj/item/dq_rule_private/I = allocate(/obj/item/dq_rule_private)
	var/datum/rule_binding/B = new(I, list(rule))
	I.set_left(2)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	TEST_ASSERT_EQUAL(I.fires, 1, "Changing tracked left fires false-to-true")
	I.set_right(3)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	TEST_ASSERT_EQUAL(I.exits, 1, "Changing tracked dynamic RHS produces exit")
	I.set_right(1)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	TEST_ASSERT_EQUAL(I.fires, 2, "RHS recovery re-arms and fires again")
	qdel(B)
	TEST_ASSERT_NULL(dq_rule_binding_of(I), "Deleting binding releases owner relation")
	TEST_ASSERT_NULL(B.key_subs, "No orphan key subscriptions")
	TEST_ASSERT_NULL(B.world_watches, "No orphan native watches")
	qdel(rule)
	qdel(registry)
	qdel(L)
	qdel(R)
	qdel(LP)
	qdel(RP)

/datum/unit_test/dq_rule_native_repeatable_hold/Run()
	var/datum/property_def/L = new /datum/property_def/dq_rule_left
	var/datum/property_def/R = new /datum/property_def/dq_rule_right
	var/datum/property_provider/LP = new /datum/property_provider/dq_rule_left
	var/datum/property_provider/RP = new /datum/property_provider/dq_rule_right
	var/datum/property_registry/registry = new(list(L, R), list(LP, RP))
	TEST_ASSERT(!length(registry.errors), "Private registry is genuinely valid")
	var/datum/rule/rule = new /datum/rule/dq_private_difference/hold
	TEST_ASSERT(rule.compile(registry), "Native dynamic comparison compiles with private registry")
	TEST_ASSERT_EQUAL(length(rule.triggers), 2, "Both dynamic dependencies receive real key subscriptions")
	var/datum/rule_trigger/first = rule.triggers[1]
	var/datum/rule_trigger/second = rule.triggers[2]
	TEST_ASSERT_EQUAL(first.property, DQ_RULE_LEFT, "Left metadata preserves declaration order")
	TEST_ASSERT_EQUAL(second.property, DQ_RULE_RIGHT, "Dynamic RHS has separate dependency")
	var/obj/item/dq_rule_private/I = allocate(/obj/item/dq_rule_private)
	var/datum/rule_binding/B = new(I, list(rule))
	I.set_left(2)
	act_drain_point()
	dq_rx_test_advance(0.8 SECONDS)
	TEST_ASSERT_EQUAL(I.fires, 0, "Short first hot segment does not fire")
	I.set_right(3)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	TEST_ASSERT(!after_pending(B, "hold:1"), "False condition cancels counting timer")
	var/remaining = B.hold_left[1]
	TEST_ASSERT(remaining > 0 && remaining < 2 SECONDS, "Elapsed true time is preserved as a paused remainder")
	dq_rx_test_advance(1.5 SECONDS)
	TEST_ASSERT_EQUAL(I.fires, 0, "Cold time does not count")
	I.set_right(1)
	act_drain_point()
	dq_rx_test_advance(remaining + 3 TICKS)
	TEST_ASSERT_EQUAL(I.fires, 1, "Remaining true duration completes first fire")
	TEST_ASSERT_EQUAL(B.hold_left[1], RULE_HOLD_SPENT, "Repeatable hold is spent for current true spell")
	I.set_right(3)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	TEST_ASSERT_EQUAL(I.exits, 1, "False transition exits exactly once")
	TEST_ASSERT_NULL(B.hold_left[1], "False transition re-arms next full hold")
	I.set_right(1)
	act_drain_point()
	dq_rx_test_advance(2 SECONDS + 3 TICKS)
	TEST_ASSERT_EQUAL(I.fires, 2, "Second true spell fires after full duration")
	I.set_right(3)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	I.set_right(1)
	act_drain_point()
	dq_rx_test_advance(2 TICKS)
	TEST_ASSERT(after_pending(B, "hold:1"), "Mid-count destruction fixture has a live keyed timer")
	qdel(B)
	TEST_ASSERT(!after_pending(B, "hold:1"), "Deletion leaves no hold timer")
	TEST_ASSERT_NULL(dq_rule_binding_of(I), "Deleting binding releases owner relation")
	TEST_ASSERT_NULL(B.key_subs, "No orphan key subscriptions")
	TEST_ASSERT_NULL(B.world_watches, "No orphan native watches")
	qdel(rule)
	qdel(registry)
	qdel(L)
	qdel(R)
	qdel(LP)
	qdel(RP)
