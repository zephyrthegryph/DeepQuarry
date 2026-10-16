// Finalization is a death-pipeline phase, never a stat transition subscription.
/datum/dq_death_policy_listener
	var/finals = 0
	var/saw_live = FALSE
	var/clear_policy = FALSE
	var/revive = FALSE
	var/revived = FALSE
/datum/dq_death_policy_listener/proc/watch(mob/living/L)
	observe(L, /datum/notice/living_death_final, src, then(PROC_REF(final_notice)))
/datum/dq_death_policy_listener/proc/final_notice(datum/act/notice/N)
	var/mob/living/L = N.target
	finals++
	saw_live = !QDELETED(L)
	if(clear_policy)
		vars_write(L, "delete_on_death", FALSE)
	if(revive)
		revived = L.return_from_death("death policy fixture", src, REVIVE_HEAL) == TRUE

/datum/unit_test/dq_death_policy_home
/datum/unit_test/dq_death_policy_home/proc/scope_diagnostics()
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.coalesce_absorbed), GLOB.coalesce_absorbed)
/datum/unit_test/dq_death_policy_home/Run()
	scope_diagnostics()
	TEST_ASSERT(!death_policy_of_type(/mob/living).delete_on_death, "root default remains opt out")
	TEST_ASSERT(death_policy_of_type(/mob/living/simple_mob/construct/shade).delete_on_death, "real shade default remains opt in")
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_EQUAL(death_policy_of(A), death_policy_of(B), "untouched peers share real policy")
	TEST_ASSERT(vars_write(A, "delete_on_death", TRUE), "historical runtime alias enables policy")
	TEST_ASSERT(death_policy_of(A).delete_on_death && !death_policy_of(B).delete_on_death, "actual COW isolates opt in")
	TEST_ASSERT(A.vv_edit_var("@death_policy.delete_on_death", FALSE), "admin can disable actual native policy")
	TEST_ASSERT(!death_policy_of(A).delete_on_death, "explicit false is not lost to default merge")
	TEST_ASSERT(!death_policy_of_type(A.type).delete_on_death, "instance writes leave type default false")
	TEST_ASSERT(!("delete_on_death" in A.vars), "historical name does not retain duplicate physical state")

/datum/unit_test/dq_death_policy_home/final_phase
/datum/unit_test/dq_death_policy_home/final_phase/Run()
	scope_diagnostics()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(vars_write(H, "delete_on_death", TRUE), "actual runtime opt in accepted")
	var/datum/dq_death_policy_listener/L = allocate(/datum/dq_death_policy_listener)
	L.watch(H)
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT(!QDELETED(H), "unconscious stat alone never consumes holder")
	TEST_ASSERT(H.death(), "actual ordered pipeline transitions to dead")
	TEST_ASSERT_EQUAL(L.finals, 1, "actual final notice ran once")
	TEST_ASSERT(L.saw_live, "every final notice still sees undeleted holder")
	TEST_ASSERT(QDELETED(H), "opt in deletes only after final notice completes")
	var/mob/living/carbon/human/corpse = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(corpse.death(), "ordinary opt-out also runs actual death pipeline")
	TEST_ASSERT(!QDELETED(corpse) && corpse.stat == DEAD, "opt-out keeps actual corpse")

/datum/unit_test/dq_death_policy_home/final_listener_override
/datum/unit_test/dq_death_policy_home/final_listener_override/Run()
	scope_diagnostics()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(vars_write(H, "delete_on_death", TRUE), "initial policy enabled")
	var/datum/dq_death_policy_listener/L = allocate(/datum/dq_death_policy_listener)
	L.clear_policy = TRUE
	L.watch(H)
	TEST_ASSERT(H.death(), "actual death reaches final observer")
	TEST_ASSERT_EQUAL(L.finals, 1, "clear listener runs exactly once")
	TEST_ASSERT(!death_policy_of(H).delete_on_death, "listener actually clears final policy through historical alias")
	TEST_ASSERT(!QDELETED(H) && H.stat == DEAD, "final hook reads current instance policy after observers, not cached/type-only opt in")
	var/mob/living/carbon/human/R = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(vars_write(R, "delete_on_death", TRUE), "revival subject initially opted in")
	var/datum/dq_death_policy_listener/reviver = allocate(/datum/dq_death_policy_listener)
	reviver.revive = TRUE
	reviver.watch(R)
	TEST_ASSERT(R.death(), "actual death notification reaches reviver")
	TEST_ASSERT(reviver.saw_live && reviver.revived, "real return_from_death succeeds within final observer")
	TEST_ASSERT(!QDELETED(R) && R.stat != DEAD, "final hook still honors actual revived status")

/datum/unit_test/dq_death_policy_home/map_alias
/datum/unit_test/dq_death_policy_home/map_alias/Run()
	scope_diagnostics()
	SSatoms.map_loader_begin("dq_death_policy_map")
	var/mob/living/simple_mob/e0_fixture/M = new(test_floor())
	var/accepted = vars_write(M, "delete_on_death", TRUE)
	SSatoms.map_loader_stop("dq_death_policy_map")
	own(M)
	SSatoms.InitializeAtoms(list(M))
	TEST_ASSERT(accepted && !QDELETED(M), "map alias applies without changing constructor lifetime")
	TEST_ASSERT(death_policy_of(M).delete_on_death, "mapped opt in survives actual parent chain")
	TEST_ASSERT(M.death(), "mapped subject actually dies")
	TEST_ASSERT(QDELETED(M), "mapped native policy keeps original final-phase deletion")
