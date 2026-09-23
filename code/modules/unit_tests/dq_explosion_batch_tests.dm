// Batched explosions and the shared EMP ladder (doc/rewrite/damage.md §7, D5).
// Atoms reached by an explosion get their blast packets from
// SSexplosions.deliver_blast_batches(): grouped by type, bounded by a budget,
// with container contents queued in bulk. Objects are destroyed by integrity.

GLOBAL_LIST_EMPTY(dq_blast_probe_log)

/obj/structure/dq_blast_probe
	name = "blast probe"
	max_integrity = 100

/obj/structure/dq_blast_probe/ex_act(severity)
	GLOB.dq_blast_probe_log += type
	return ..()

/obj/structure/dq_blast_probe/alpha
/obj/structure/dq_blast_probe/beta

/datum/unit_test/dq_explosion_batch
	abstract_type = /datum/unit_test/dq_explosion_batch

/// Deliver a blast of `severity` to `atoms` the way an explosion epoch does.
/datum/unit_test/dq_explosion_batch/proc/blast(list/atoms, severity, budget = INFINITY)
	for(var/atom/movable/AM as anything in atoms)
		SSexplosions.queue_blast(AM, severity)
	return SSexplosions.deliver_blast_batches(budget, FALSE)


/// Outcome parity: which fixture objects survive each severity ring, and with
/// what integrity, against the deleted severity ladders. The old ladders were
/// coin flips (`prob` then `qdel`); a ring's outcome matches when the new
/// deterministic result is within 0.5 of the old chance of destruction.
/datum/unit_test/dq_explosion_batch/outcome_parity

/datum/unit_test/dq_explosion_batch/outcome_parity/Run()
	// type = old chance of destruction at severity 1, 2, 3
	var/list/fixture = list(
		/obj/item/paper = list(1, 0.5, 0.05),
		/obj/structure/bed = list(1, 0.5, 0.05),
		/obj/structure/closet = list(1, 0.5, 0.05),
		/obj/item/cell = list(1, 0.5, 0.25),
		/obj/structure/dq_blast_probe = list(1, 0.5, 0.05),
	)
	var/list/remaining = list(1, 0.5, 0.75) // integrity fraction left per ring
	for(var/path in fixture)
		var/list/old_chance = fixture[path]
		for(var/severity in 1 to 3)
			var/obj/O = allocate(path, test_floor())
			var/max_int = O.max_integrity
			blast(list(O), severity)
			var/destroyed = QDELETED(O) ? 1 : 0
			TEST_ASSERT(abs(destroyed - old_chance[severity]) <= 0.5, "[path] at severity [severity]: destroyed=[destroyed], the old ladder destroyed it [old_chance[severity] * 100]% of the time")
			if(!destroyed)
				TEST_ASSERT(abs(O.get_integrity() - max_int * remaining[severity]) <= 1, "[path] at severity [severity] kept [O.get_integrity()]/[max_int] integrity, expected [max_int * remaining[severity]]")
			if(severity == 1)
				TEST_ASSERT(destroyed, "[path] survived a devastating blast")


/// A container's contents take the blast with it, queued in bulk, and spill
/// when the container is destroyed.
/datum/unit_test/dq_explosion_batch/contents_spill

/datum/unit_test/dq_explosion_batch/contents_spill/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	var/obj/structure/dq_blast_probe/inner = allocate(/obj/structure/dq_blast_probe, C)
	C.opened = FALSE
	inner.forceMove(C)
	blast(list(C), 1)
	TEST_ASSERT(QDELETED(C), "a devastating blast should destroy the closet")
	TEST_ASSERT(!QDELETED(inner), "the closet shields its contents one step")
	TEST_ASSERT_EQUAL(inner.loc, T, "a destroyed closet spills its contents onto the turf")
	TEST_ASSERT_EQUAL(inner.get_integrity(), inner.max_integrity * 0.5, "contents take the blast one step down (severity 2)")

	// Severity 3 leaves both standing, and the closet shields its contents entirely.
	var/obj/structure/closet/C2 = allocate(/obj/structure/closet, T)
	var/obj/structure/dq_blast_probe/inner2 = allocate(/obj/structure/dq_blast_probe, C2)
	inner2.forceMove(C2)
	blast(list(C2), 3)
	TEST_ASSERT(!QDELETED(C2), "a light blast should not destroy a closet")
	TEST_ASSERT_EQUAL(inner2.loc, C2, "an intact closet keeps its contents")
	TEST_ASSERT_EQUAL(inner2.get_integrity(), inner2.max_integrity, "a light blast doesn't reach inside a closet")


/// Delivery stops at the budget and resumes where it stopped; atoms are
/// grouped by type, each hit exactly once at its strongest severity.
/datum/unit_test/dq_explosion_batch/budget_and_grouping

/datum/unit_test/dq_explosion_batch/budget_and_grouping/Run()
	GLOB.dq_blast_probe_log.Cut()
	var/list/atoms = list()
	for(var/i in 1 to 5)
		atoms += allocate(/obj/structure/dq_blast_probe/alpha, test_floor())
		atoms += allocate(/obj/structure/dq_blast_probe/beta, test_floor())
	for(var/atom/movable/AM as anything in atoms)
		SSexplosions.queue_blast(AM, 3)
	SSexplosions.queue_blast(atoms[1], 2) // a stronger ring reaches it too
	TEST_ASSERT_EQUAL(SSexplosions.pending_blast_count(), 10, "a doubly reached atom should be queued once")

	TEST_ASSERT(!SSexplosions.deliver_blast_batches(4, FALSE), "delivery should stop at the budget")
	TEST_ASSERT_EQUAL(length(GLOB.dq_blast_probe_log), 4, "exactly the budget's worth of atoms should get packets")
	TEST_ASSERT_EQUAL(SSexplosions.pending_blast_count(), 6, "the rest should stay queued")
	TEST_ASSERT(SSexplosions.deliver_blast_batches(INFINITY, FALSE), "delivery should finish")
	TEST_ASSERT_EQUAL(length(GLOB.dq_blast_probe_log), 10, "every atom should get one packet")

	var/list/expected = list()
	for(var/i in 1 to 5)
		expected += /obj/structure/dq_blast_probe/alpha
	for(var/i in 1 to 5)
		expected += /obj/structure/dq_blast_probe/beta
	TEST_ASSERT_EQUAL(jointext(GLOB.dq_blast_probe_log, ","), jointext(expected, ","), "packets should be delivered in type batches")
	var/obj/structure/dq_blast_probe/first = atoms[1]
	TEST_ASSERT_EQUAL(first.get_integrity(), first.max_integrity * 0.5, "a doubly reached atom takes the strongest severity once")
	GLOB.dq_blast_probe_log.Cut()


/// Bomb-proof objects are never queued.
/datum/unit_test/dq_explosion_batch/bomb_proof

/datum/unit_test/dq_explosion_batch/bomb_proof/Run()
	var/obj/structure/dq_blast_probe/P = allocate(/obj/structure/dq_blast_probe, test_floor())
	P.resistance_flags |= BOMB_PROOF
	blast(list(P), 1)
	TEST_ASSERT(!QDELETED(P), "a bomb-proof object survives a devastating blast")
	TEST_ASSERT_EQUAL(P.get_integrity(), P.max_integrity, "a bomb-proof object takes no blast")


/// A blast batch is one power topology commit (M3, fixes.md Q13): cables the
/// blast destroys queue their removal, and the edits reach Rust together when
/// the explosion epoch ends.
/datum/unit_test/dq_explosion_batch/one_topology_commit

/datum/unit_test/dq_explosion_batch/one_topology_commit/Run()
	var/list/run = dq_power_test_run(4)
	TEST_ASSERT_NOTNULL(run, "no clear floor run for the power batch test")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	SSmachines.power_flush(TRUE)
	var/sent = SSmachines.power_edits_sent
	SSmachines.power_batch_begin()
	var/obj/structure/cable/cut_a = cables[2]
	var/obj/structure/cable/cut_b = cables[3]
	blast(list(cut_a, cut_b), 1)
	TEST_ASSERT(QDELETED(cut_a) && QDELETED(cut_b), "a devastating blast should cut the cables")
	SSmachines.power_flush()
	TEST_ASSERT_EQUAL(SSmachines.power_edits_sent, sent, "edits reached Rust inside the explosion epoch")
	TEST_ASSERT(length(SSmachines.power_ops), "the cut cables did not queue their removal")
	SSmachines.power_batch_end()
	TEST_ASSERT(!length(SSmachines.power_ops), "ending the epoch did not send the batch")
	TEST_ASSERT(SSmachines.power_edits_sent > sent, "the batch was not sent")
	for(var/obj/structure/cable/C as anything in cables)
		if(!QDELETED(C))
			qdel(C)
	for(var/turf/T as anything in run)
		for(var/obj/item/stack/cable_coil/coil in T)
			qdel(coil)


/// The one EMP ladder: EMP severities read it forwards, ionic hits backwards,
/// and every target (object or mob) is pulsed through the same path.
/obj/structure/dq_emp_probe
	name = "emp probe"
	var/last_severity

/obj/structure/dq_emp_probe/emp_act(severity, recursive)
	last_severity = severity
	return ..()

/datum/unit_test/dq_explosion_batch/emp_ladder

/datum/unit_test/dq_explosion_batch/emp_ladder/Run()
	for(var/severity in EMP_HEAVY to EMP_HARMLESS)
		var/amount = emp_ionic_damage(severity)
		TEST_ASSERT(amount > 0, "severity [severity] should have an ionic amount")
		TEST_ASSERT_EQUAL(emp_severity_for_ionic(amount), severity, "the ladder should round-trip severity [severity]")
		if(severity > EMP_HEAVY)
			TEST_ASSERT(amount < emp_ionic_damage(severity - 1), "the ladder should weaken with severity")
	TEST_ASSERT_EQUAL(emp_ionic_damage(EMP_NONE), 0, "EMP_NONE carries nothing")
	TEST_ASSERT_EQUAL(emp_severity_for_ionic(0), EMP_HARMLESS, "a spent ionic hit is harmless")
	TEST_ASSERT_EQUAL(emp_severity_for_ionic(1000), EMP_HEAVY, "an overwhelming ionic hit is heavy")
	for(var/i in 1 to 20)
		var/blended = emp_severity_for_ionic(emp_ionic_damage(EMP_HEAVY) - 20)
		TEST_ASSERT(blended == EMP_HEAVY || blended == EMP_MEDIUM, "an amount between rungs lands on one of them, got [blended]")

	var/obj/structure/dq_emp_probe/target = allocate(/obj/structure/dq_emp_probe, test_floor())
	for(var/severity in EMP_HEAVY to EMP_HARMLESS)
		target.receive_ionic(emp_ionic_damage(severity))
		TEST_ASSERT_EQUAL(target.last_severity, severity, "an ionic hit pulses at the ladder's severity")

	var/obj/item/projectile/ion/bolt = allocate(/obj/item/projectile/ion)
	var/mob/living/simple_mob/dq_damage_probe/victim = allocate(/mob/living/simple_mob/dq_damage_probe)
	TEST_ASSERT_EQUAL(bolt.inflict_injury(victim, BP_TORSO), 0, "an ion bolt pulses instead of injuring")
