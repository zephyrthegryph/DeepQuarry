// Transformations (doc/rewrite/proposals/transformations.md): the entry kind, the compile, the index, the conditions, the settle and the outputs, on
// fixture rules of a regime of their own ("dq_fixture") so they never touch a real reagent holder.

#define DQ_XFORM_FIXTURE_REGIME "dq_fixture"

/// A holder that runs the fixture regime.
/datum/reagents/dq_fixture

/datum/reagents/dq_fixture/xform_regime()
	return DQ_XFORM_FIXTURE_REGIME

GLOBAL_LIST_EMPTY(dq_xform_tail_calls)

/transformation/dq_fixture

CAPABILITIES(/transformation/dq_fixture)
	transformation(regime = DQ_XFORM_FIXTURE_REGIME, says = "")

/transformation/dq_fixture/water_to_carbon

CAPABILITIES(/transformation/dq_fixture/water_to_carbon)
	configure(transformation(name = "Fixture water", id = "fixture_water", takes = list(reagent(REAGENT_ID_WATER, 2)), makes = list(reagent(REAGENT_ID_CARBON, 1))))

/transformation/dq_fixture/catalyzed

CAPABILITIES(/transformation/dq_fixture/catalyzed)
	configure(transformation(takes = list(reagent(REAGENT_ID_SUGAR, 1)), catalysts = list(reagent(REAGENT_ID_SILICON, 3)), makes = list(reagent(REAGENT_ID_NUTRIMENT, 2))))

/transformation/dq_fixture/blocked

CAPABILITIES(/transformation/dq_fixture/blocked)
	configure(transformation(takes = list(reagent(REAGENT_ID_OXYGEN, 1)), blocked_by = list(reagent(REAGENT_ID_HYDROGEN, 1)), makes = list(reagent(REAGENT_ID_NITROGEN, 1))))

/// A base that pins the subject to a beaker; its child adds a temperature window: the two conditions are ANDed.
/transformation/dq_fixture/in_beaker

CAPABILITIES(/transformation/dq_fixture/in_beaker)
	configure(transformation(holds = subject_is(/obj/item/reagent_containers/glass/beaker)))

/transformation/dq_fixture/in_beaker/hot_only

CAPABILITIES(/transformation/dq_fixture/in_beaker/hot_only)
	configure(transformation(takes = list(reagent(REAGENT_ID_COPPER, 1)), makes = list(reagent(REAGENT_ID_TIN, 1)), holds = temperature_in(T0C + 100, null)))

/transformation/dq_fixture/in_beaker/mild

CAPABILITIES(/transformation/dq_fixture/in_beaker/mild)
	configure(transformation(takes = list(reagent(REAGENT_ID_LEAD, 1)), makes = list(reagent(REAGENT_ID_TIN, 1)), holds = temperature_in(T0C, T0C + 40)))

/// Two rules that want the same reactant: the second declared has the lower priority number and goes first.
/transformation/dq_fixture/late

CAPABILITIES(/transformation/dq_fixture/late)
	configure(transformation(takes = list(reagent(REAGENT_ID_IRON, 1)), makes = list(reagent(REAGENT_ID_ALUMINIUM, 1)), priority = 5))

/transformation/dq_fixture/early

CAPABILITIES(/transformation/dq_fixture/early)
	configure(transformation(takes = list(reagent(REAGENT_ID_IRON, 1)), makes = list(reagent(REAGENT_ID_LITHIUM, 1)), priority = PRIORITY_DEFAULT))

/// A chain: each product is the next rule's input, so the settle needs several passes.
/transformation/dq_fixture/chain_a

CAPABILITIES(/transformation/dq_fixture/chain_a)
	configure(transformation(takes = list(reagent(REAGENT_ID_POTASSIUM, 1)), makes = list(reagent(REAGENT_ID_SODIUM, 1))))

/transformation/dq_fixture/chain_b

CAPABILITIES(/transformation/dq_fixture/chain_b)
	configure(transformation(takes = list(reagent(REAGENT_ID_SODIUM, 1)), makes = list(reagent(REAGENT_ID_PHOSPHORUS, 1))))

/// A rule with the bespoke parts: data of the product, a tail, a proc condition.
/transformation/dq_fixture/with_tail

CAPABILITIES(/transformation/dq_fixture/with_tail)
	configure(transformation(takes = list(reagent(REAGENT_ID_RADIUM, 1)), makes = list(reagent(REAGENT_ID_URANIUM, 1)), data = TYPE_PROC_REF(/transformation/dq_fixture/with_tail, tail_data), then = TYPE_PROC_REF(/transformation/dq_fixture/with_tail, tail_done), holds = TYPE_PROC_REF(/transformation/dq_fixture/with_tail, tail_allows)))

/transformation/dq_fixture/with_tail/proc/tail_data(datum/reagents/holder, extent)
	return null

/transformation/dq_fixture/with_tail/proc/tail_done(datum/reagents/holder, made)
	GLOB.dq_xform_tail_calls += made

/transformation/dq_fixture/with_tail/proc/tail_allows(datum/reagents/holder)
	return TRUE

/// A made fixture holder inside a beaker, ready to fill.
/datum/unit_test/proc/dq_xform_holder()
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	var/datum/reagents/dq_fixture/H = new(1000, B)
	own(H)
	return H

/datum/unit_test/dq_xform_terms_and_conditions
	boot_needs = list()

/datum/unit_test/dq_xform_terms_and_conditions/Run()
	var/datum/entry/water = reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT_EQUAL(water.kind, ENTRY_XTERM, "a term is an xterm entry")
	TEST_ASSERT_EQUAL(water.args["currency"], XCUR_REAGENT, "reagent() is the reagent currency")
	TEST_ASSERT_EQUAL(water.args["amount"], 5, "the amount is kept")
	TEST_ASSERT_EQUAL(reagent(REAGENT_ID_WATER, 5), water, "the same term is the same entry")
	TEST_ASSERT_EQUAL(gas(GAS_PLASMA, 2).args["currency"], XCUR_GAS, "gas() is the gas currency")
	TEST_ASSERT_EQUAL(item_term(/obj/item/paper, 1, "main").args["into"], "main", "an item term names the slot it goes into")
	var/list/rows = xform_rows(list(reagent(REAGENT_ID_WATER, 5), list(gas(GAS_PLASMA, 2))))
	TEST_ASSERT_EQUAL(length(rows), 2, "nested term lists flatten to rows")
	TEST_ASSERT_EQUAL(rows[2][2], GAS_PLASMA, "a row is currency, key, amount, into")
	var/list/assoc = xform_assoc(rows, XCUR_REAGENT)
	TEST_ASSERT_EQUAL(assoc[REAGENT_ID_WATER], 5, "xform_assoc() is the shape holders are asked in")
	TEST_ASSERT_EQUAL(xform_medium_of(XCUR_GAS), MEDIUM_GAS, "the medium follows the currency")
	// Conditions.
	var/datum/entry/window = temperature_in(T0C + 10, T0C + 30)
	TEST_ASSERT_EQUAL(window.kind, ENTRY_XCOND, "a condition is an xcond entry")
	var/datum/entry/both = xform_all(subject_is(/obj/item), window)
	TEST_ASSERT_EQUAL(xform_cond_subject_type(both), /obj/item, "an all() reports the type its subject_is() pins")
	var/list/bands = xform_cond_bands(xform_all(window, xform_not(temperature_in(null, T0C))))
	TEST_ASSERT_EQUAL(length(bands), 2, "every temperature_in() anywhere in the condition is a watch band")
	TEST_ASSERT_EQUAL(bands[1][1], T0C + 10, "a band is (lo, hi)")
	TEST_ASSERT(xform_cond_calls_proc(xform_all(window, "tail_allows")), "a PROC_REF in the condition makes the rule not plain")
	TEST_ASSERT(!xform_cond_calls_proc(both), "data conditions are plain")
	TEST_ASSERT_EQUAL(xform_cond_and(null, window), window, "ANDing over nothing is the condition itself")

/datum/unit_test/dq_xform_compile
	boot_needs = list()

/datum/unit_test/dq_xform_compile/Run()
	var/datum/xform/W = xform_of(/transformation/dq_fixture/water_to_carbon)
	TEST_ASSERT(W, "a type with takes compiled to a rule")
	TEST_ASSERT_EQUAL(W.medium, MEDIUM_REAGENTS, "the medium is inferred from the first take")
	TEST_ASSERT_EQUAL(W.regime, DQ_XFORM_FIXTURE_REGIME, "the regime is inherited from the base block")
	TEST_ASSERT_EQUAL(W.anchor, REAGENT_ID_WATER, "the first take is the anchor")
	TEST_ASSERT_EQUAL(W.reagent_takes[REAGENT_ID_WATER], 2, "reagent takes are keyed for the holder")
	TEST_ASSERT_EQUAL(W.result, REAGENT_ID_CARBON, "a reagent rule's product is its first reagent term")
	TEST_ASSERT_EQUAL(W.result_amount, 1, "and its amount per reaction unit")
	TEST_ASSERT_EQUAL(W.rate, RATE_INSTANT, "rate defaults to instant")
	TEST_ASSERT_EQUAL(W.name, "Fixture water", "the name is kept for the people who read it")
	TEST_ASSERT(W.plain, "no tail, data or proc condition: plain")
	TEST_ASSERT_NULL(xform_of(/transformation/dq_fixture), "a base is not a rule")
	TEST_ASSERT_NULL(xform_of(/transformation/dq_fixture/in_beaker), "a base with only conditions is not a rule")
	var/datum/xform/C = xform_of(/transformation/dq_fixture/catalyzed)
	TEST_ASSERT_EQUAL(C.reagent_catalysts[REAGENT_ID_SILICON], 3, "catalysts are kept")
	var/datum/xform/H = xform_of(/transformation/dq_fixture/in_beaker/hot_only)
	TEST_ASSERT_EQUAL(H.subject_type, /obj/item/reagent_containers/glass/beaker, "the inherited subject_is() pins the subject type")
	TEST_ASSERT_EQUAL(length(H.bands), 1, "the child's temperature window is a band")
	TEST_ASSERT_EQUAL(H.bands[1][1], T0C + 100, "with its bound")
	var/datum/xform/T = xform_of(/transformation/dq_fixture/with_tail)
	TEST_ASSERT(!T.plain, "a rule with a tail is not plain")
	TEST_ASSERT_EQUAL(T.then_proc, "tail_done", "the tail is the proc's name")
	// Order is the declaration order, stamped.
	var/datum/xform/late = xform_of(/transformation/dq_fixture/late)
	var/datum/xform/early = xform_of(/transformation/dq_fixture/early)
	TEST_ASSERT(late.order < early.order, "late was declared first, so it has the lower stamped order")
	var/list/bucket = xform_candidates(MEDIUM_REAGENTS, DQ_XFORM_FIXTURE_REGIME, REAGENT_ID_IRON)
	TEST_ASSERT_EQUAL(length(bucket), 2, "both are candidates for iron")
	TEST_ASSERT_EQUAL(bucket[1], early, "the lower priority number goes first, whatever the declaration order")
	TEST_ASSERT_EQUAL(bucket[2], late, "then the higher")
	// The reverse index.
	var/list/makers = xform_makers_of(MEDIUM_REAGENTS, DQ_XFORM_FIXTURE_REGIME, REAGENT_ID_CARBON)
	TEST_ASSERT(W in makers, "the product index names the rule that makes carbon")
	TEST_ASSERT_EQUAL(W.owner_of().type, /transformation/dq_fixture/water_to_carbon, "a rule owns one instance of its type for its procs")
	// The rate helpers are chemistry's.
	TEST_ASSERT_EQUAL(half_life(0), 1, "a half-life of nothing is instant")
	TEST_ASSERT(half_life(6) > 0 && half_life(6) < 0.05, "a half-life of six ticks goes a few percent a step")

/datum/unit_test/dq_xform_settle
	boot_needs = list()
	var/list/heard_rules = list()
	var/list/heard_extent = list()
	var/list/heard_made = list()

/datum/unit_test/dq_xform_settle/proc/heard(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/transformed/event = N
	heard_rules += event.rule
	heard_extent += event.extent
	heard_made += event.made

/datum/unit_test/dq_xform_settle/Run()
	// Amounts: water 10 -> carbon 5.
	var/datum/reagents/dq_fixture/H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_WATER, 10, safety = 1)
	var/list/fired = xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(fired), 1, "one rule fired")
	TEST_ASSERT_EQUAL(H.get_reagent_amount(REAGENT_ID_WATER), 0, "the water was taken")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_CARBON) - 5) < 0.001, "the carbon was made")
	// Reagents are continuous: an odd amount goes whole, into a fraction of a reaction unit's product.
	H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_WATER, 5, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(H.get_reagent_amount(REAGENT_ID_WATER), 0, "an instant rule takes all it can")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_CARBON) - 2.5) < 0.001, "and makes the fraction of a unit's product")
	// A catalyst is needed and not used.
	H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_SUGAR, 4, safety = 1)
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(H)), 0, "without the catalyst nothing happens")
	H.add_reagent(REAGENT_ID_SILICON, 3, safety = 1)
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(H)), 1, "with it the rule goes")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_SILICON) - 3) < 0.001, "the catalyst is not consumed")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_NUTRIMENT) - 8) < 0.001, "the product follows the stoichiometry")
	// A blocker stops it.
	H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_HYDROGEN, 2, safety = 1)
	H.add_reagent(REAGENT_ID_OXYGEN, 4, safety = 1)
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(H)), 0, "a blocker present stops the rule")
	// The subject's own type and temperature are conditions; the inherited and the new ones are ANDed.
	H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_LEAD, 4, safety = 1)
	H.add_reagent(REAGENT_ID_COPPER, 4, safety = 1)
	var/list/rules = xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(rules), 1, "at room temperature only the mild rule holds")
	TEST_ASSERT_EQUAL(rules[1], xform_of(/transformation/dq_fixture/in_beaker/mild), "and it is the one fired")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_COPPER) - 4) < 0.001, "the hot rule did not run")
	// A chain settles to its end in one call.
	H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_POTASSIUM, 6, safety = 1)
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(H)), 2, "both links of the chain fired")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_PHOSPHORUS) - 6) < 0.001, "the chain ran to its end")
	TEST_ASSERT_EQUAL(H.get_reagent_amount(REAGENT_ID_POTASSIUM) + H.get_reagent_amount(REAGENT_ID_SODIUM), 0, "nothing of the middle is left")
	// Priority decides who gets a shared reactant.
	H = dq_xform_holder()
	H.add_reagent(REAGENT_ID_IRON, 5, safety = 1)
	var/list/who = xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(who[1], xform_of(/transformation/dq_fixture/early), "the lower priority number took the iron")
	TEST_ASSERT_EQUAL(H.get_reagent_amount(REAGENT_ID_ALUMINIUM), 0, "so the later rule found none")
	// The tail runs with the amount made, and the notice carries the settle.
	H = dq_xform_holder()
	GLOB.dq_xform_tail_calls = list()
	heard_rules = list()
	heard_extent = list()
	heard_made = list()
	observe(H, /datum/notice/transformed, src, then(PROC_REF(heard)))
	H.add_reagent(REAGENT_ID_RADIUM, 3, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(GLOB.dq_xform_tail_calls), 1, "the tail ran once")
	TEST_ASSERT(abs(GLOB.dq_xform_tail_calls[1] - 3) < 0.001, "with the amount made")
	TEST_ASSERT_EQUAL(length(heard_rules), 1, "one notice for the rule")
	TEST_ASSERT_EQUAL(heard_rules[1], xform_of(/transformation/dq_fixture/with_tail), "naming the rule")
	TEST_ASSERT(abs(heard_extent[1] - 3) < 0.001, "its extent in reaction units")
	TEST_ASSERT(abs(heard_made[1] - 3) < 0.001, "and what it made")
	unobserve(H, /datum/notice/transformed, src)

/// A product that does not fit is clamped to the free volume, as chemistry always did (D10): the step still runs, the excess is lost.
/datum/unit_test/dq_xform_truncates_reagent_output
	boot_needs = list()

/datum/unit_test/dq_xform_truncates_reagent_output/Run()
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	var/datum/reagents/dq_fixture/H = new(10, B)
	own(H)
	H.add_reagent(REAGENT_ID_WATER, 10, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(H.get_reagent_amount(REAGENT_ID_WATER), 0, "the water was all taken")
	TEST_ASSERT(abs(H.get_reagent_amount(REAGENT_ID_CARBON) - 5) < 0.001, "the product fits: no loss here")
	H = new(3, B)
	own(H)
	H.add_reagent(REAGENT_ID_WATER, 3, safety = 1)
	xform_settle_reagents(H)
	TEST_ASSERT(H.total_volume <= 3, "the holder never holds more than its volume")

/// Items and stacks do not truncate: a place that refuses a product refuses before anything is spent, and one that takes it takes it through the ledger.
/datum/unit_test/dq_xform_item_output_refuses
	boot_needs = list()

/datum/unit_test/dq_xform_item_output_refuses/Run()
	var/turf/T = dq_containment_floor()
	TEST_ASSERT(T, "clean containment floor exists")
	var/obj/item/dq_containment_box/box = allocate(/obj/item/dq_containment_box, T)
	// The main slot takes sharp things only: a paper is refused, and nothing is left behind.
	var/list/why = list()
	TEST_ASSERT_NULL(xform_prepare_item(box, "main", /obj/item/paper, why = why), "a paper is refused by a slot that wants sharp things")
	TEST_ASSERT(length(why), "the refusal gives its reason")
	// The default slot takes anything.
	var/obj/item/paper/made = xform_prepare_item(box, null, /obj/item/paper)
	TEST_ASSERT(made, "the default slot takes it")
	TEST_ASSERT(xform_commit_item(box, null, made), "committing puts it in")
	TEST_ASSERT_EQUAL(made.loc, box, "the product is in the box")
	dq_verify_ledger(box, "after the product was placed")

/// RES_GAS: the gas of the target's mixture, reserved and committed like any other resource.
/datum/unit_test/dq_xform_gas_resource
	boot_needs = list()

/datum/unit_test/dq_xform_gas_resource/Run()
	var/datum/resource/gas/adapter = resource_of(RES_GAS)
	TEST_ASSERT(adapter, "RES_GAS has an adapter")
	TEST_ASSERT_EQUAL(adapter.res_id, RES_GAS, "and it is the gas one")
	var/obj/distilling_tester/D = allocate(/obj/distilling_tester, test_floor())
	D.GM.adjust_gas(GAS_N2, 10)
	var/datum/act/op/A = new
	A.target = D
	TEST_ASSERT_EQUAL(round(adapter.available(A), 0.01), 10, "available is the moles of the target's mixture")
	var/datum/reservation/R = adapter.reserve(A, 4)
	TEST_ASSERT(R, "four moles can be set aside")
	TEST_ASSERT_NULL(adapter.reserve(A, 7), "and then seven more cannot")
	adapter.commit(R)
	TEST_ASSERT_EQUAL(round(D.GM.total_moles(), 0.01), 6, "committing took them from the mixture")
	qdel(A)
