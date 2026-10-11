/datum/dq_native_transfer_query_probe
	var/atom/destination
	var/atom/movable/candidate
	var/mob/mover
	var/allowed = TRUE
	var/refusal_text = "closed by native admission"

CAPABILITIES(/datum/dq_native_transfer_query_probe)
	ref_one(nameof(destination), /atom)
	ref_one(nameof(candidate), /atom/movable)
	ref_one(nameof(mover), /mob)

TRACKED(/datum/dq_native_transfer_query_probe, allowed)
TRACKED(/datum/dq_native_transfer_query_probe, refusal_text)

/datum/dq_native_transfer_query_probe/proc/admission(datum/act/op/A)
	if(A.holder != src || A.destination != destination || A.target != candidate || A.actor != mover || A.mover != mover || A.slot_id != "s1_picky")
		return "wrong native admission identities"
	if(A.source != src || A.activation?.source != src || A.cap != A.activation?.def)
		return "wrong native admission activation"
	return allowed ? null : refusal_text

/datum/unit_test/dq_native_transfer_query/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human, T)
	var/obj/s1_fixture/picky/box = allocate(/obj/s1_fixture/picky, T)
	var/obj/item/s1_fixture/gizmo/item = allocate(/obj/item/s1_fixture/gizmo, T)
	rel_set(box, nameof(box.steward), mover)
	var/datum/dq_native_transfer_query_probe/P = allocate(/datum/dq_native_transfer_query_probe)
	rel_set(P, nameof(P.destination), box)
	rel_set(P, nameof(P.candidate), item)
	rel_set(P, nameof(P.mover), mover)
	observe(box, /datum/act/insert, P, needs(req(TYPE_PROC_REF(/datum/dq_native_transfer_query_probe, admission))))
	var/datum/act/op/acceptance/query = acceptance_act(box, box, item, null, mover, "s1_picky")
	var/lease_count = GLOB.act_taken
	TEST_ASSERT_EQUAL(act_context(query.type, P, query.target, query.actor, query), query, "Receiver rebind preserves the existing query lease")
	TEST_ASSERT_EQUAL(query.holder, P, "Receiver rebind uses the real listener")
	TEST_ASSERT_EQUAL(query.destination, box, "Receiver rebind preserves physical destination")
	TEST_ASSERT_EQUAL(query.target, item, "Receiver rebind preserves the candidate")
	TEST_ASSERT_EQUAL(query.mover, mover, "Receiver rebind preserves the mover")
	TEST_ASSERT_EQUAL(GLOB.act_taken, lease_count, "Receiver rebind does not begin a world action")
	acceptance_act_release(query)
	var/datum/rx_state/S = rx_of(box)
	var/before_generation = S.hooks_generation
	TEST_ASSERT_NULL(op_transfer_precheck(box, /datum/act/insert, item, "s1_picky", mover), "Query sees actual candidate, destination, mover, listener and activation")
	TEST_ASSERT_EQUAL(item.loc, T, "Pure admission preserves candidate custody")
	TEST_ASSERT_NULL(box.slot_item("s1_picky"), "Query never performs real insertion")
	P.set_allowed(FALSE)
	TEST_ASSERT_EQUAL(reason_text(op_transfer_precheck(box, /datum/act/insert, item, "s1_picky", mover)), "closed by native admission", "Exact native refusal surfaces from the real hook receiver")
	var/list/reads = op_transfer_read_keys(box, /datum/act/insert, item, "s1_picky", mover)
	var/saw_topology = FALSE
	var/saw_gate = FALSE
	for(var/list/pair as anything in reads)
		if(pair[1] == S && pair[2] == nameof(S.hooks_generation))
			saw_topology = TRUE
		if(pair[1] == P && pair[2] == nameof(P.allowed))
			saw_gate = TRUE
	TEST_ASSERT(saw_topology && saw_gate, "Native query records actual hook topology and tracked veto dependencies")
	TEST_ASSERT(!move_into(box, "s1_picky", item, mover), "Real final insert applies identical native requirement context")
	TEST_ASSERT_EQUAL(item.loc, T, "Refused final action preserves custody")
	P.set_allowed(TRUE)
	TEST_ASSERT(move_into(box, "s1_picky", item, mover), "Cleared requirement allows final real insertion")
	TEST_ASSERT_EQUAL(item.loc, box, "Allowed real action commits custody")
	TEST_ASSERT_EQUAL(box.slot_item("s1_picky"), item, "Actual destination slot contains candidate")
	unobserve(box, /datum/act/insert, P)
	TEST_ASSERT(S.hooks_generation > before_generation, "Actual hook teardown publishes topology invalidation")
	TEST_ASSERT_NULL(op_transfer_precheck(box, /datum/act/insert, item, "s1_picky", mover), "Removed listener no longer refuses queries")

/obj/item/dq_live_budget_box
	name = "live budget test box"

/datum/relation_definition/slot/dq_live_budget
	holder = /obj/item/dq_live_budget_box
	slot_id = "budget"
	capacity_model = SLOT_CAPACITY_UNITS
	capacity = 3
	is_default = TRUE

/datum/unit_test/dq_storage_live_budget_generic_ref/proc/contains_read(list/reads, datum/owner, key)
	for(var/list/pair as anything in reads)
		if(pair[1] == owner && pair[2] == key)
			return TRUE
	return FALSE

/datum/unit_test/dq_storage_live_budget_generic_ref/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_live_budget_box/box = allocate(/obj/item/dq_live_budget_box, T)
	var/obj/item/stack/resident = allocate(/obj/item/stack, T)
	var/obj/item/pen/candidate = allocate(/obj/item/pen, T)
	var/datum/matter_synth/left = allocate(/datum/matter_synth, 100)
	var/datum/matter_synth/right = allocate(/datum/matter_synth, 200)
	resident.set_uses_charge(2)
	resident.set_charge_costs(list(10, 20))
	right.set_energy(60)
	TEST_ASSERT_EQUAL(resident.get_amount(), 0, "Missing source prevents charged amount")
	TEST_ASSERT(move_into(box, "budget", resident), "Real charged resident enters slot")
	var/datum/ledger/L = dq_ledger_peek(box)
	TEST_ASSERT(L, "Actual slot ledger exists")
	// Deliberately generic native relation edits, not stack.add_synth and no
	// drain: query correctness must not depend on deferred maintenance.
	rel_add(resident, nameof(resident.synths), left)
	rel_add(resident, nameof(resident.synths), right)
	TEST_ASSERT_EQUAL(resident.get_amount(), 3, "Two real charge sources use the limiting amount")
	var/used_before = L.used["budget"]
	var/cost_before = L.entries[resident][LEDGER_E_COST]
	var/taken = GLOB.act_taken
	var/notices = GLOB.notice_taken
	TEST_ASSERT_EQUAL(L.current_used("budget"), 3, "Pure budget reads current charged minimum before a drain")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(candidate, box, "budget", null), "there's no room for it", "Immediate generic edit refuses candidate at actual capacity")
	TEST_ASSERT_EQUAL(L.used["budget"], used_before, "Query leaves cached accounting untouched")
	TEST_ASSERT_EQUAL(L.entries[resident][LEDGER_E_COST], cost_before, "Query leaves insertion-time entry cost untouched")
	TEST_ASSERT_EQUAL(resident.loc, box, "Query leaves resident custody unchanged")
	TEST_ASSERT_EQUAL(candidate.loc, T, "Refusal leaves candidate outside")
	TEST_ASSERT_EQUAL(GLOB.act_taken, taken, "Query dispatches no world action")
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices, "Query emits no notice")
	var/list/reads = dq_ledger_read_keys(candidate, box, "budget", null)
	TEST_ASSERT(contains_read(reads, resident, nameof(resident.synths)), "Current resident source membership is watched")
	TEST_ASSERT(contains_read(reads, left, nameof(left.energy)), "Left source owner is watched")
	TEST_ASSERT(contains_read(reads, right, nameof(right.energy)), "Right source owner is watched")
	right.set_energy(200)
	TEST_ASSERT_EQUAL(resident.get_amount(), 10, "Increasing limiting source exposes left limit")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(candidate, box, "budget", null), "there's no room for it", "Raised cost remains refused")
	left.set_energy(20)
	TEST_ASSERT_EQUAL(resident.get_amount(), 2, "Changing other source changes real minimum")
	TEST_ASSERT_NULL(dq_ledger_refusal(candidate, box, "budget", null), "Two units plus one candidate exactly fits inclusive budget")
	TEST_ASSERT(move_into(box, "budget", candidate), "Actual transfer commits when live budget allows")
	TEST_ASSERT_EQUAL(candidate.loc, box, "Committed candidate really enters holder")

// A test-only mutable cost model intentionally has no accounting callback.
// Generic ref mutations therefore expose genuine signed stale deltas.
/datum/dq_budget_weight
	var/units = 1

TRACKED(/datum/dq_budget_weight, units)

/obj/item/dq_budget_refs
	var/list/sources

CAPABILITIES(/obj/item/dq_budget_refs)
	ref_many(nameof(sources), /datum/dq_budget_weight)

/datum/relation_definition/slot/dq_live_budget/cost(atom/holder, atom/movable/thing)
	if(istype(thing, /obj/item/dq_budget_refs))
		var/obj/item/dq_budget_refs/R = thing
		. = 0
		for(var/datum/dq_budget_weight/W as anything in R.sources)
			. += W.units
		return
	if(istype(thing, /obj/item/stack))
		var/obj/item/stack/S = thing
		return S.get_amount()
	return 1

/datum/relation_definition/slot/dq_live_budget/cost_read_keys(atom/holder, atom/movable/thing)
	. = list()
	if(istype(thing, /obj/item/dq_budget_refs))
		var/obj/item/dq_budget_refs/R = thing
		. += list(list(R, nameof(R.sources)))
		for(var/datum/dq_budget_weight/W as anything in R.sources)
			. += list(list(W, nameof(W.units)))
	else if(istype(thing, /obj/item/stack))
		var/obj/item/stack/S = thing
		. += S.amount_read_keys()

/datum/unit_test/dq_storage_live_budget_generic_ref/negative_delta/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_live_budget_box/box = allocate(/obj/item/dq_live_budget_box, T)
	var/obj/item/dq_budget_refs/resident = allocate(/obj/item/dq_budget_refs, T)
	var/obj/item/pen/candidate = allocate(/obj/item/pen, T)
	var/datum/dq_budget_weight/left = allocate(/datum/dq_budget_weight)
	var/datum/dq_budget_weight/right = allocate(/datum/dq_budget_weight)
	left.set_units(2)
	right.set_units(1)
	rel_add(resident, nameof(resident.sources), left)
	rel_add(resident, nameof(resident.sources), right)
	TEST_ASSERT(move_into(box, "budget", resident), "Real resident fills finite budget")
	var/datum/ledger/L = dq_ledger_peek(box)
	TEST_ASSERT_EQUAL(L.used["budget"], 3, "Insertion-time cost really starts at three")
	TEST_ASSERT_EQUAL(dq_ledger_refusal(candidate, box, "budget"), "there's no room for it", "Full real budget refuses")
	rel_remove(resident, nameof(resident.sources), right)
	TEST_ASSERT_EQUAL(L.used["budget"], 3, "Generic REF removal deliberately leaves stale insertion-time accounting")
	var/taken = GLOB.act_taken
	var/notices = GLOB.notice_taken
	TEST_ASSERT_EQUAL(L.current_used("budget"), 2, "Signed negative delta reflects generic unlink before drain")
	TEST_ASSERT_NULL(dq_ledger_refusal(candidate, box, "budget"), "Two plus one fits without repairing cache")
	TEST_ASSERT_EQUAL(L.used["budget"], 3, "Allowed query is pure even with negative stale delta")
	TEST_ASSERT_EQUAL(L.entries[resident][LEDGER_E_COST], 3, "Entry cost remains insertion-time value")
	qdel(left)
	TEST_ASSERT_EQUAL(length(resident.sources), 0, "Real declared REF clears deleted source")
	taken = GLOB.act_taken
	notices = GLOB.notice_taken
	TEST_ASSERT_EQUAL(L.current_used("budget"), 0, "Source death produces full negative stale delta without drain")
	TEST_ASSERT_NULL(dq_ledger_refusal(candidate, box, "budget"), "Deleted cost source allows candidate immediately")
	TEST_ASSERT_EQUAL(L.used["budget"], 3, "Death query preserves cached budget")
	TEST_ASSERT_EQUAL(resident.loc, box, "Queries preserve resident custody")
	TEST_ASSERT_EQUAL(candidate.loc, T, "Queries preserve candidate custody")
	TEST_ASSERT_EQUAL(GLOB.act_taken, taken, "Queries after REF death dispatch no world action")
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices, "Queries after REF death publish no world notice")

/obj/item/dq_live_budget_box/unbounded
	var/forbid_cost = FALSE

TRACKED(/obj/item/dq_live_budget_box/unbounded, forbid_cost)

/datum/relation_definition/slot/dq_live_budget/unbounded
	holder = /obj/item/dq_live_budget_box/unbounded
	capacity = INFINITY

/datum/relation_definition/slot/dq_live_budget/unbounded/cost(atom/holder, atom/movable/thing)
	var/obj/item/dq_live_budget_box/unbounded/B = holder
	if(B.forbid_cost)
		CRASH("Unbounded query evaluated irrelevant cost")
	return ..()

/datum/relation_definition/slot/dq_live_budget/unbounded/cost_read_keys(atom/holder, atom/movable/thing)
	var/obj/item/dq_live_budget_box/unbounded/B = holder
	if(B.forbid_cost)
		CRASH("Unbounded query collected irrelevant cost metadata")
	return ..()

/datum/unit_test/dq_storage_live_budget_generic_ref/unbounded/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_live_budget_box/unbounded/B = allocate(/obj/item/dq_live_budget_box/unbounded, T)
	var/obj/item/pen/resident = allocate(/obj/item/pen, T)
	var/obj/item/pen/candidate = allocate(/obj/item/pen, T)
	TEST_ASSERT(move_into(B, "budget", resident), "Real unbounded slot accepts initial resident")
	var/datum/ledger/L = dq_ledger_peek(B)
	TEST_ASSERT_EQUAL(L.def_by_id("budget").capacity_for(B), INFINITY, "Actual queried slot has unbounded capacity")
	var/cached = L.used["budget"]
	B.set_forbid_cost(TRUE)
	TEST_ASSERT_NULL(dq_ledger_refusal(candidate, B, "budget"), "Unbounded evaluator skips irrelevant live costs")
	var/list/reads = dq_ledger_read_keys(candidate, B, "budget", null)
	TEST_ASSERT(length(reads), "Unbounded query still gathers structural custody metadata")
	TEST_ASSERT_EQUAL(L.used["budget"], cached, "Query preserves cached accounting")
	TEST_ASSERT_EQUAL(candidate.loc, T, "Query never transfers candidate")
	B.set_forbid_cost(FALSE)

/datum/unit_test/dq_native_transfer_query/silent_unequip/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/under/hyperfiber/bluespace/U = allocate(/obj/item/clothing/under/hyperfiber/bluespace, T)
	var/obj/item/storage/backpack/B = allocate(/obj/item/storage/backpack, T)
	TEST_ASSERT(H.equip_to_slot_if_possible(U, SLOT_ID_UNIFORM, disable_warning = TRUE), "Real garment is equipped on actual wearer")
	var/size_before = H.size_multiplier
	U.original_size = size_before + 0.25
	var/restore = U.original_size
	var/taken = GLOB.act_taken
	var/notices = GLOB.notice_taken
	TEST_ASSERT_NULL(dq_ledger_refusal(U, B, CONTAINER_SLOT_STORAGE, H), "Silent native storage query permits real removable garment")
	TEST_ASSERT_EQUAL(H.size_multiplier, size_before, "Pure query does not resize wearer")
	TEST_ASSERT_EQUAL(U.original_size, restore, "Pure query does not consume saved resize effect")
	TEST_ASSERT_EQUAL(U.loc, H, "Pure query preserves equipped custody")
	TEST_ASSERT_EQUAL(GLOB.act_taken, taken, "Pure query starts no world action")
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices, "Pure query emits no notice")
	TEST_ASSERT(H.unEquip(U, target = T), "Actual ordinary removal retains legacy resize effects")
	TEST_ASSERT_EQUAL(U.loc, T, "Actual removal drops garment at real destination")
	TEST_ASSERT_NULL(U.original_size, "Real removal path consumes saved resize effect")
	TEST_ASSERT_EQUAL(H.size_multiplier, restore, "Real removal path restores original size")

/datum/unit_test/dq_native_transfer_query/source_first/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human, T)
	var/obj/s1_fixture/picky/source = allocate(/obj/s1_fixture/picky, T)
	var/obj/s1_fixture/picky/destination = allocate(/obj/s1_fixture/picky, T)
	var/obj/item/s1_fixture/gizmo/item = allocate(/obj/item/s1_fixture/gizmo, T)
	rel_set(source, nameof(source.steward), mover)
	rel_set(destination, nameof(destination.steward), mover)
	TEST_ASSERT(move_into(source, "s1_picky", item, mover), "Real source slot contains candidate before removal veto")
	var/datum/dq_native_transfer_query_probe/S = allocate(/datum/dq_native_transfer_query_probe)
	var/datum/dq_native_transfer_query_probe/D = allocate(/datum/dq_native_transfer_query_probe)
	rel_set(S, nameof(S.destination), source)
	rel_set(D, nameof(D.destination), destination)
	for(var/datum/dq_native_transfer_query_probe/P as anything in list(S, D))
		rel_set(P, nameof(P.candidate), item)
		rel_set(P, nameof(P.mover), mover)
		P.set_allowed(FALSE)
	S.set_refusal_text("source removal refused")
	D.set_refusal_text("destination insertion refused")
	observe(source, /datum/act/remove, S, needs(req(TYPE_PROC_REF(/datum/dq_native_transfer_query_probe, admission))))
	observe(destination, /datum/act/insert, D, needs(req(TYPE_PROC_REF(/datum/dq_native_transfer_query_probe, admission))))
	TEST_ASSERT_EQUAL(dq_ledger_refusal(item, destination, "s1_picky", mover), "source removal refused", "Removal refusal precedes destination refusal")
	S.set_allowed(TRUE)
	TEST_ASSERT_EQUAL(dq_ledger_refusal(item, destination, "s1_picky", mover), "destination insertion refused", "Clearing source exposes destination reason")
	TEST_ASSERT_EQUAL(item.loc, source, "Both queries leave actual custody unchanged")
	D.set_allowed(TRUE)
	TEST_ASSERT(move_into(destination, "s1_picky", item, mover), "Both cleared requirements allow final transfer")
	TEST_ASSERT_EQUAL(item.loc, destination, "Final transfer commits destination custody")
	unobserve(source, /datum/act/remove, S)
	unobserve(destination, /datum/act/insert, D)

/datum/dq_transfer_guard_gate
	var/enabled = FALSE

TRACKED(/datum/dq_transfer_guard_gate, enabled)

/obj/s1_fixture/picky/query_guard
	var/datum/dq_transfer_guard_gate/gate

CAPABILITIES(/obj/s1_fixture/picky/query_guard)
	ref_one(nameof(gate), /datum/dq_transfer_guard_gate)
	when(PROC_REF(guard_enabled), extend(/datum/act/insert, needs(req(PROC_REF(guard_refusal)))))

/obj/s1_fixture/picky/query_guard/proc/guard_enabled(datum/act/op/A)
	return gate?.enabled

/obj/s1_fixture/picky/query_guard/proc/guard_refusal(datum/act/op/A)
	return "cross-entity gate refuses insertion"

/datum/unit_test/dq_native_transfer_query/guard_reads/proc/has_read(list/reads, datum/owner, key)
	for(var/list/pair as anything in reads)
		if(pair[1] == owner && pair[2] == key)
			return TRUE
	return FALSE

/datum/unit_test/dq_native_transfer_query/guard_reads/Run()
	var/turf/T = test_floor()
	var/old_reason = GLOB.act_last_reason
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human, T)
	var/obj/s1_fixture/picky/query_guard/box = allocate(/obj/s1_fixture/picky/query_guard, T)
	var/obj/item/s1_fixture/gizmo/candidate = allocate(/obj/item/s1_fixture/gizmo, T)
	var/datum/dq_transfer_guard_gate/G = allocate(/datum/dq_transfer_guard_gate)
	var/datum/dq_transfer_guard_gate/replacement = allocate(/datum/dq_transfer_guard_gate)
	rel_set(box, nameof(box.steward), mover)
	rel_set(box, nameof(box.gate), G)
	TEST_ASSERT_NULL(op_transfer_precheck(box, /datum/act/insert, candidate, "s1_picky", mover), "False actual cross-entity guard skips refusal")
	var/list/reads = op_transfer_read_keys(box, /datum/act/insert, candidate, "s1_picky", mover)
	TEST_ASSERT(has_read(reads, box, nameof(box.gate)), "Guard watches real relation replacement")
	TEST_ASSERT(has_read(reads, G, nameof(G.enabled)), "Guard watches actual far-owner tracked state even while false")
	G.set_enabled(TRUE)
	TEST_ASSERT_EQUAL(reason_text(op_transfer_precheck(box, /datum/act/insert, candidate, "s1_picky", mover)), "cross-entity gate refuses insertion", "Actual guard changes query refusal")
	TEST_ASSERT(!move_into(box, "s1_picky", candidate, mover), "Final insertion uses identical guarded needs")
	TEST_ASSERT_EQUAL(candidate.loc, T, "Refused final insertion preserves custody")
	rel_set(box, nameof(box.gate), replacement)
	reads = op_transfer_read_keys(box, /datum/act/insert, candidate, "s1_picky", mover)
	TEST_ASSERT(has_read(reads, replacement, nameof(replacement.enabled)), "Replacing relation collects new concrete far-owner")
	TEST_ASSERT(!has_read(reads, G, nameof(G.enabled)), "Replaced owner is absent from fresh metadata")
	TEST_ASSERT_NULL(op_transfer_precheck(box, /datum/act/insert, candidate, "s1_picky", mover), "False replacement guard allows again")
	qdel(replacement)
	TEST_ASSERT_NULL(box.gate, "Actual declared reference clears dead gate")
	reads = op_transfer_read_keys(box, /datum/act/insert, candidate, "s1_picky", mover)
	TEST_ASSERT(has_read(reads, box, nameof(box.gate)), "Missing far end retains relation dependency")
	TEST_ASSERT(move_into(box, "s1_picky", candidate, mover), "Cleared guard allows real final custody")
	TEST_ASSERT_EQUAL(candidate.loc, box, "Actual candidate is transferred")
	GLOB.act_last_reason = old_reason
