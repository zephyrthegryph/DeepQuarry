// The verb store (doc/rewrite/systems.md §19, code/datums/om/grant_verbs.dm): a verb is on an atom
// while it is not hidden and something (a grant, the type) gives it; the store is the only writer.

/mob/living/proc/dq_sys_grants_test_verb()
	set name = "DQ Grants Test Verb"
	set hidden = TRUE

/obj/proc/dq_sys_grants_test_obj_verb()
	set name = "DQ Grants Test Object Verb"
	set hidden = TRUE

/obj/proc/dq_sys_grants_test_flag_verb()
	set name = "DQ Grants Test Flag Verb"
	set hidden = TRUE

/obj/item/dq_grants_declared
	var/dq_flag = FALSE

/obj/item/dq_grants_declared/hiding

/mob/living/carbon/human/dq_grants_hiding

TRACKED(/obj/item/dq_grants_declared, dq_flag)

CAPABILITIES(/obj/item/dq_grants_declared)
	verb_entry(/obj/proc/dq_sys_grants_test_obj_verb)
	verb_entry(/obj/proc/dq_sys_grants_test_flag_verb, when = nameof(dq_flag))

CAPABILITIES(/mob/living/carbon/human/dq_grants_hiding)
	verb_entry(/mob/verb/observe, hidden = TRUE)

CAPABILITIES(/obj/item/dq_grants_declared/hiding)
	verb_entry(/obj/proc/dq_sys_grants_test_obj_verb, hidden = TRUE)

/datum/unit_test/dq_sys_grants_verb_follows_sources

/datum/unit_test/dq_sys_grants_verb_follows_sources/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/first = allocate(/obj/item, test_floor())
	var/obj/item/second = allocate(/obj/item, test_floor())
	var/verb_path = /mob/living/proc/dq_sys_grants_test_verb
	TEST_ASSERT(!(verb_path in H.verbs), "the verb starts absent")

	grant(H, granted_verb(verb_path), first)
	TEST_ASSERT(verb_path in H.verbs, "the first source's grant adds the verb")
	grant(H, granted_verb(verb_path), second)
	revoke(H, granted_verb(verb_path), first)
	TEST_ASSERT(verb_path in H.verbs, "the verb stays while another source grants it")

	qdel(second)
	TEST_ASSERT(!(verb_path in H.verbs), "deleting the last source removes the verb")
	TEST_ASSERT(!granted(H, granted_verb(verb_path)), "and the grant")

/datum/unit_test/dq_sys_grants_objects_and_sources

/datum/unit_test/dq_sys_grants_objects_and_sources/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/obj/item/source = allocate(/obj/item, test_floor())
	var/obj/item/target = allocate(/obj/item, test_floor())
	var/obj_verb = /obj/proc/dq_sys_grants_test_obj_verb
	grant(target, granted_verb(obj_verb), source)
	TEST_ASSERT(obj_verb in target.verbs, "objects take verb grants too")
	TEST_ASSERT(revoke(target, granted_verb(obj_verb), source), "revoke reports it ended the grant")
	TEST_ASSERT(!(obj_verb in target.verbs), "revoking takes the verb off")
	grant(target, granted_verb(obj_verb), source)
	qdel(source)
	TEST_ASSERT(!(obj_verb in target.verbs), "the source's deletion takes it off")

/// A type verb that a grant also covers survives the grant's revoke; a hide beats both and lifting
/// it brings the type verb back (the old add/remove pairs desynced here).
/datum/unit_test/dq_sys_grants_hide_and_mixed_sources

/datum/unit_test/dq_sys_grants_hide_and_mixed_sources/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/granter = allocate(/obj/item, test_floor())
	var/obj/item/hider = allocate(/obj/item, test_floor())
	var/type_verb = /mob/verb/observe
	TEST_ASSERT(type_verb in H.verbs, "a human has /mob/verb/observe from its type")

	grant(H, granted_verb(type_verb), granter)
	revoke(H, granted_verb(type_verb), granter)
	TEST_ASSERT(type_verb in H.verbs, "revoking a grant keeps a verb the type gives")

	grant(H, granted_verb(type_verb), granter)
	grant(H, granted_verb(type_verb, hidden = TRUE), hider)
	TEST_ASSERT(!(type_verb in H.verbs), "a hide beats the type and a grant")
	qdel(hider)
	TEST_ASSERT(type_verb in H.verbs, "the hider's deletion brings the verb back")
	revoke(H, granted_verb(type_verb), granter)
	TEST_ASSERT(type_verb in H.verbs, "and it stays with the type once the grant is gone")

	var/verb_path = /mob/living/proc/dq_sys_grants_test_verb
	hider = allocate(/obj/item, test_floor())
	grant(H, granted_verb(verb_path, hidden = TRUE), hider)
	grant(H, granted_verb(verb_path), granter)
	TEST_ASSERT(!(verb_path in H.verbs), "a grant made while hidden stays off")
	revoke(H, granted_verb(verb_path, hidden = TRUE), hider)
	TEST_ASSERT(verb_path in H.verbs, "lifting the hide shows the granted verb")

/// verb_entry(), conditional verb_entry() and hidden verb_entry() apply at init and keep no store entry.
/datum/unit_test/dq_sys_grants_declared_verbs

/datum/unit_test/dq_sys_grants_declared_verbs/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/obj/item/dq_grants_declared/D = allocate(/obj/item/dq_grants_declared, test_floor())
	TEST_ASSERT(/obj/proc/dq_sys_grants_test_obj_verb in D.verbs, "verb_entry() puts the verb on at init")
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_flag_verb in D.verbs), "conditional verb_entry() stays off while the var is false")

	D.set_dq_flag(TRUE)
	test_time(0.2 SECONDS)
	TEST_ASSERT(/obj/proc/dq_sys_grants_test_flag_verb in D.verbs, "refreshing after the var turns true adds it")
	D.set_dq_flag(FALSE)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_flag_verb in D.verbs), "and removes it when the var turns false")

	var/obj/item/source = allocate(/obj/item, test_floor())
	grant(D, granted_verb(/obj/proc/dq_sys_grants_test_obj_verb), source)
	revoke(D, granted_verb(/obj/proc/dq_sys_grants_test_obj_verb), source)
	TEST_ASSERT(/obj/proc/dq_sys_grants_test_obj_verb in D.verbs, "a revoke keeps a declared verb")

	var/obj/item/dq_grants_declared/hiding/H = allocate(/obj/item/dq_grants_declared/hiding, test_floor())
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_obj_verb in H.verbs), "a subtype's hidden verb_entry() overrides the parent's verb_entry()")
	grant(H, granted_verb(/obj/proc/dq_sys_grants_test_obj_verb), source)
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_obj_verb in H.verbs), "a declared hide beats a runtime grant")

	var/mob/living/carbon/human/dq_grants_hiding/M = allocate(/mob/living/carbon/human/dq_grants_hiding, test_floor())
	TEST_ASSERT(!(/mob/verb/observe in M.verbs), "hidden verb_entry() strips an inherited /type/verb/")

/// Turf verbs are declared (conditional verb_entry() on climbable): toggling needs no store entry on the turf.
/datum/unit_test/dq_sys_grants_turf_declared

/datum/unit_test/dq_sys_grants_turf_declared/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/turf/simulated/T = test_floor()
	TEST_ASSERT(istype(T), "the test floor is simulated")
	var/was = T.climbable
	T.toggle_climbability()
	TEST_ASSERT_EQUAL(!!(/turf/simulated/proc/climb_wall in T.verbs), !!T.climbable, "climb_wall follows climbable after a toggle")
	T.toggle_climbability()
	TEST_ASSERT_EQUAL(!!(/turf/simulated/proc/climb_wall in T.verbs), !!was, "and back")

/// Exercise the production form hooks before replacing their grant/revoke calls.
/datum/form/dq_grant_test

TYPE_TABLE(/datum/form/dq_grant_test, get_form_verbs, list(/mob/living/proc/dq_sys_grants_test_verb))

/datum/unit_test/dq_retire_form_verbs

/datum/unit_test/dq_retire_form_verbs/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/form/dq_grant_test/F = allocate(/datum/form/dq_grant_test)
	var/datum/form/dq_grant_test/other = allocate(/datum/form/dq_grant_test)
	var/path = /mob/living/proc/dq_sys_grants_test_verb
	TEST_ASSERT(!(path in H.verbs), "the form verb starts absent")
	F.on_enter(null, H)
	TEST_ASSERT(path in H.verbs, "entering a form grants its configured verb")
	other.on_enter(null, H)
	F.on_exit(null, H)
	TEST_ASSERT(path in H.verbs, "leaving one form preserves the other source's grant")
	other.on_exit(null, H)
	TEST_ASSERT(!(path in H.verbs), "leaving the last form revokes the verb")
	F.on_enter(null, H)
	qdel(F)
	TEST_ASSERT(!(path in H.verbs), "deleting the granting form removes its verb")
/datum/unit_test/retire_alien_evolve_without_adult_hides_verb
/datum/unit_test/retire_alien_evolve_without_adult_hides_verb/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/mob/living/carbon/alien/A = allocate(/mob/living/carbon/alien, test_floor())
	TEST_ASSERT_EQUAL(A.stat, CONSCIOUS, "the real base alien is conscious")
	TEST_ASSERT(isnull(A.adult_form), "the actual base alien has no adult form")
	TEST_ASSERT(/mob/living/carbon/alien/verb/evolve in A.verbs, "the inherited public evolve verb starts present")
	A.evolve()
	TEST_ASSERT(!(/mob/living/carbon/alien/verb/evolve in A.verbs), "the actual no-adult branch hides evolve")
	TEST_ASSERT(!QDELETED(A), "refusing evolution preserves the real larval body")
	TEST_ASSERT(isnull(A.adult_form), "the branch does not fabricate a grown body type")

/datum/unit_test/retire_robot_default_and_subsystem_verbs
/datum/unit_test/retire_robot_default_and_subsystem_verbs/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	R.add_robot_verbs()
	TEST_ASSERT(/mob/living/silicon/robot/proc/robot_checklaws in R.verbs, "actual default laws proc is granted")
	TEST_ASSERT(/mob/living/silicon/proc/subsystem_alarm_monitor in R.verbs, "actual alarm subsystem proc is granted")
	R.add_robot_verbs()
	R.remove_robot_verbs()
	TEST_ASSERT(!(/mob/living/silicon/robot/proc/robot_checklaws in R.verbs), "one removal ends the same-source default grant despite repeated addition")
	TEST_ASSERT(!(/mob/living/silicon/proc/subsystem_alarm_monitor in R.verbs), "one removal ends the same-source subsystem grant")
	R.add_robot_verbs()
	TEST_ASSERT(/mob/living/silicon/robot/proc/robot_checklaws in R.verbs, "default grant can be restored")
	TEST_ASSERT(/mob/living/silicon/proc/subsystem_alarm_monitor in R.verbs, "subsystem grant can be restored")

/datum/unit_test/retire_malf_source_verbs

/datum/unit_test/retire_malf_source_verbs/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, test_floor(), null, null, null, TRUE)
	AI.setup_for_malf()
	var/datum/malf_research/research = AI.research
	TEST_ASSERT(research, "malfunction setup creates the real granting research source")
	var/path = /mob/living/proc/dq_sys_grants_test_verb
	grant(AI, granted_verb(path), research)
	TEST_ASSERT(path in AI.verbs, "the research source grants its real runtime verb")
	TEST_ASSERT(/datum/game_mode/malfunction/verb/ai_help in AI.verbs, "malfunction setup grants the help verb")
	AI.stop_malf()
	test_time(1 SECOND)
	TEST_ASSERT(!(path in AI.verbs), "delayed malfunction cleanup removes research-granted verbs")
	TEST_ASSERT(!granted(AI, granted_verb(path)), "cleanup also ends the activation, preventing a later re-grant")
	TEST_ASSERT(!(/datum/game_mode/malfunction/verb/ai_help in AI.verbs), "cleanup revokes its own malfunction verbs")
	TEST_ASSERT(!granted(AI, granted_verb(/datum/game_mode/malfunction/verb/ai_help)), "cleanup ends self-sourced activations rather than only their presentation")
	TEST_ASSERT_NULL(AI.research, "cleanup releases the research source")

/datum/unit_test/retire_timed_hidden_verb

/datum/unit_test/retire_timed_hidden_verb/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source = allocate(/datum)
	var/path = /mob/verb/observe
	TEST_ASSERT(path in H.verbs, "the inherited verb is initially visible")
	grant(H, granted_verb(path, hidden = TRUE), source, lasts = 1 SECOND)
	TEST_ASSERT(!(path in H.verbs), "the native timed hide suppresses the inherited verb")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!(path in H.verbs), "the hide remains before its deadline")
	test_time(0.6 SECONDS)
	TEST_ASSERT(path in H.verbs, "expiry restores the inherited verb")
	TEST_ASSERT(!granted(H, granted_verb(path, hidden = TRUE)), "expiry removes the hide activation")
