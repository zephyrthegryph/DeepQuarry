/// Real changeling setup and public paralysis sting; representative effect/cancel/current-range coverage.
/datum/unit_test/round2_changeling_sting_continuation
	var/sting_case = "accepted"

/datum/unit_test/round2_changeling_sting_continuation/Run()
	test_driver_begin()
	exercise_sting()
	test_driver_end()

/datum/unit_test/round2_changeling_sting_continuation/proc/exercise_sting()
	var/turf/simulated/floor/surface
	var/turf/simulated/floor/adjacent
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.density)
			continue
		var/list/reachable_neighbors = candidate.AdjacentTurfsRangedSting()
		for(var/turf/simulated/floor/neighbor in reachable_neighbors)
			if(!neighbor.density && AStar(candidate, neighbor, TYPE_PROC_REF(/turf, AdjacentTurfsRangedSting), TYPE_PROC_REF(/turf, Distance), max_nodes = 25, max_node_depth = 1))
				surface = candidate
				adjacent = neighbor
				break
		if(surface)
			break
	TEST_ASSERT(surface && adjacent, "Actual map supplies two nondense simulated floors connected by the production sting depth-one path")
	TEST_ASSERT(!surface.density && !adjacent.density, "Actual selected floor pair is nondense without changing map state")
	TEST_ASSERT(adjacent in surface.AdjacentTurfsRangedSting(), "Actual selected neighbor is returned by the production sting adjacency provider")
	TEST_ASSERT(AStar(surface, adjacent, TYPE_PROC_REF(/turf, AdjacentTurfsRangedSting), TYPE_PROC_REF(/turf, Distance), max_nodes = 25, max_node_depth = 1), "Actual selected map pair has a real one-depth sting path before actor allocation")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, surface)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, adjacent)
	var/datum/mind/character = allocate(/datum/mind)
	TEST_ASSERT(transfer_mind(character, actor, "round2 real changeling sting fixture"), "Supported logged mind transfer installs a real mind on the actual human")
	TEST_ASSERT_EQUAL(actor.mind, character, "Real human owns the current mind relationship required by changeling powers")
	actor.make_changeling()
	var/datum/changeling/comp = actor.get_changeling_state()
	TEST_ASSERT(istype(comp) && comp.owner == actor, "Actual make_changeling installs the real owned changeling state")
	TEST_ASSERT_EQUAL(is_changeling(actor), comp, "Actual gameplay trait lookup resolves the installed state")
	comp.purchasePower(actor, "Paralysis Sting")
	var/purchased = FALSE
	for(var/datum/power/changeling/power in comp.purchased_powers)
		if(istype(power, /datum/power/changeling/paralysis_sting))
			purchased = TRUE
	TEST_ASSERT(purchased, "Actual evolution purchase installs the concrete paralysis power without a fake verb or power")
	for(var/i in 1 to 60)
		comp.regenerate()
	TEST_ASSERT_EQUAL(comp.chem_charges, comp.chem_storage, "Actual chemical regeneration fills the real storage without assigning resources or gates")
	TEST_ASSERT(comp.chem_charges >= 30 && comp.check_cooldown(), "Actual prepared changeling can afford a sting and has no active sting cooldown")
	TEST_ASSERT_EQUAL(target.status_units(STAT_WEAKENED), 0, "Actual target begins without the tested paralysis effect")
	TEST_ASSERT(!HAS_SYNTHETIC_BIOLOGY(target), "Actual target has biological sting-compatible anatomy")
	TEST_ASSERT(actor.sting_can_reach(target, comp.sting_range), "Actual production path finder can reach the neighboring target")
	var/original_chems = comp.chem_charges
	actor.changeling_paralysis_sting()
	var/datum/prompt/choice/changeling_sting_target/question = SSrequests.open_for(actor)
	TEST_ASSERT(istype(question) && question.owner == actor && question.answerer == actor, "Actual public power opens its native target request on the original changeling")
	TEST_ASSERT(target in question.choices, "Actual actor-centered target collection offers the real adjacent human")
	TEST_ASSERT_EQUAL(comp.chem_charges, original_chems, "Opening a pending sting does not debit chemicals")
	TEST_ASSERT_EQUAL(target.status_units(STAT_WEAKENED), 0, "Opening a pending sting does not apply the effect")
	if(sting_case == "cancelled")
		test_answer(actor, null, REQ_CANCELLED)
	else if(sting_case == "late_range")
		var/turf/remote
		for(var/turf/candidate in world)
			if(candidate.z != surface.z)
				remote = candidate
				break
		TEST_ASSERT(remote, "Actual map supplies a separate z-level for real late movement")
		TEST_ASSERT(target.forceMove(remote), "Actual target movement removes the offered target from current sting range")
		TEST_ASSERT_EQUAL(target.loc, remote, "Real target actually leaves the actor's z-level")
		test_answer(actor, target)
	else
		test_answer(actor, target)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Accepted, cancelled or late-refused sting retires its original request")
	if(sting_case == "accepted")
		TEST_ASSERT_EQUAL(target.status_units(STAT_WEAKENED), 20, "Actual native continuation resumes the caller's real paralysis effect tail")
		TEST_ASSERT_EQUAL(comp.chem_charges, original_chems - 30, "Actual completed sting debits exactly one thirty-unit chemical cost")
		TEST_ASSERT(!comp.check_cooldown(), "Actual completed sting starts its real common anti-spam cooldown")
		TEST_ASSERT_EQUAL(comp.sting_range, 1, "Actual completed sting resets its next range to the ordinary value")
		TEST_ASSERT_NULL(test_answer(actor, target), "Duplicate driver answer has no retired request to execute")
		TEST_ASSERT_EQUAL(comp.chem_charges, original_chems - 30, "Duplicate answer cannot charge a second sting cost")
		TEST_ASSERT_EQUAL(target.status_units(STAT_WEAKENED), 20, "Duplicate answer preserves the single actual effect")
	else
		TEST_ASSERT_EQUAL(comp.chem_charges, original_chems, "Actual cancellation or late range refusal keeps the chemical budget")
		TEST_ASSERT_EQUAL(target.status_units(STAT_WEAKENED), 0, "Actual cancellation or late range refusal never executes the paralysis tail")
		TEST_ASSERT(comp.check_cooldown(), "Actual cancelled or unreachable sting does not start common cooldown")

/datum/unit_test/round2_changeling_sting_continuation/cancelled
	sting_case = "cancelled"

/datum/unit_test/round2_changeling_sting_continuation/late_range
	sting_case = "late_range"
