// Behaviour-preservation tests for the mob/living domain (hc-mobs): what a player, an AI or an explosion can observe of the mobs whose legacy
// declarations (DAMAGE_REACTION, om_ask, DECLARE_UI, DECLARE_INTERACTIONS ...) are converted to the final forms. The file passes on the legacy
// code and after the conversion; only the adapter block below changes.
//
// Rules the tests keep (as in dq_p2_*_behaviour.dm):
//   - Input goes through the public entry points of the mob (ex_act, emp_act, bullet_act, test_ui, test_answer), never an op key.
//   - State is read through the adapters below and plain vars; nothing depends on message text.
//   - A conversion that changes behaviour on purpose is a line in doc/rewrite/intended_changes.md and an edit here.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters: the handlers the DAMAGE_REACTION rows named. After the conversion they take the hit's act, not the packet.
// ---------------------------------------------------------------------------------------------------------------------

/// A mob that was blown apart or deleted by a blast: gone, or dead.
/proc/hc_gone(atom/movable/A)
	if(QDELETED(A))
		return TRUE
	var/mob/living/L = A
	return istype(L) && L.stat == DEAD

// ---------------------------------------------------------------------------------------------------------------------
// Damage reactions: the blocks (a blast does not reach the mob's own ladder), the effects (an EMP, a hit) and their order.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_mobs
	abstract_type = /datum/unit_test/dq_hc_mobs

/// Takes ownership of what a test's subject left around the test floor (gibs, sparks), so the block's leak check stays about the test's own objects.
/datum/unit_test/dq_hc_mobs/proc/own_around(turf/T = test_floor())
	for(var/turf/N in range(3, T))
		own_turf_contents(N)

/// A blast on a creature whose type declares a blocking reaction: the reaction answers it and the family ladder never runs.
/datum/unit_test/dq_hc_mobs/blast_blocked_by_type
	var/list/gone_types = list(
		/mob/living/simple_mob/vore/rabbit/killer,
		/mob/living/simple_mob/slime/xenobio/dark_purple,
		/mob/living/simple_mob/slime/feral/dark_purple,
		/mob/living/silicon/ai,
	)
	var/list/stays_types = list(
		/mob/living/simple_mob/animal/passive/cockroach,
		/mob/living/simple_mob/illusion,
	)

/datum/unit_test/dq_hc_mobs/blast_blocked_by_type/Run()
	for(var/type in stays_types)
		var/mob/living/M = allocate(type, test_floor())
		var/vitality = M.vitality()
		M.ex_act(1)
		TEST_ASSERT(!QDELETED(M), "[type] shrugs off a blast")
		TEST_ASSERT_EQUAL(M.vitality(), vitality, "[type] takes nothing from a blast")
	for(var/type in gone_types)
		var/mob/living/M
		if(ispath(type, /mob/living/silicon/ai))
			M = allocate(type, test_floor(), null, null, null, TRUE)
		else
			M = allocate(type, test_floor())
		M.ex_act(1)
		own_around()
		TEST_ASSERT(hc_gone(M), "[type] does not survive a direct blast")

/// An AI core survives a distant blast and loses the shell link on an ion pulse; only a direct blast ends it.
/datum/unit_test/dq_hc_mobs/ai_core_blast_severity
/datum/unit_test/dq_hc_mobs/ai_core_blast_severity/Run()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, test_floor(), null, null, null, TRUE)
	AI.ex_act(3)
	TEST_ASSERT(!QDELETED(AI), "a weak blast leaves the core standing")
	AI.ex_act(2)
	TEST_ASSERT(!QDELETED(AI), "a medium blast leaves the core standing")
	AI.ex_act(1)
	TEST_ASSERT(QDELETED(AI), "a direct blast destroys the core outright")

/// A pAI shaken by an EMP is silenced for two minutes.
/datum/unit_test/dq_hc_mobs/pai_emp_silences
/datum/unit_test/dq_hc_mobs/pai_emp_silences/Run()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, test_floor())
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai, card)
	P.silence_time = 0
	P.emp_act(EMP_MEDIUM)
	own_around()
	TEST_ASSERT(P.silence_time > world.timeofday, "a pulse starts the communication reboot")

/// A synthetic simple mob takes ionic damage from a pulse, scaled to its endurance; an organic one takes none.
/datum/unit_test/dq_hc_mobs/simple_mob_emp_surge
/datum/unit_test/dq_hc_mobs/simple_mob_emp_surge/Run()
	var/mob/living/simple_mob/mechanical/robot = allocate(/mob/living/simple_mob/mechanical, test_floor())
	var/mob/living/simple_mob/animal/passive/mouse/organic = allocate(/mob/living/simple_mob/animal/passive/mouse, test_floor())
	var/robot_before = robot.vitality()
	var/organic_before = organic.vitality()
	robot.emp_act(EMP_HEAVY)
	organic.emp_act(EMP_HEAVY)
	TEST_ASSERT(robot.vitality() < robot_before, "a pulse hurts a synthetic mob")
	TEST_ASSERT_EQUAL(organic.vitality(), organic_before, "and leaves an organic one alone")

/// A borg's module pulses its matter synths: the charge drops on a pulse.
/datum/unit_test/dq_hc_mobs/robot_module_emp_synths
/datum/unit_test/dq_hc_mobs/robot_module_emp_synths/Run()
	var/obj/item/robot_module/module = allocate(/obj/item/robot_module/robot/standard, test_floor())
	var/datum/matter_synth/S = new /datum/matter_synth/metal(1000)
	module.synths = list(S)
	var/before = S.energy
	module.emp_act(EMP_HEAVY)
	TEST_ASSERT(S.energy < before, "a pulse drains the synths of the module")
	qdel(S)
