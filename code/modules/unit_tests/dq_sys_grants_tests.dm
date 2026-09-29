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

DECLARE_VERB(/obj/item/dq_grants_declared, /obj/proc/dq_sys_grants_test_obj_verb)
DECLARE_VERB_IF(/obj/item/dq_grants_declared, /obj/proc/dq_sys_grants_test_flag_verb, "dq_flag")
DECLARE_VERB_HIDE(/mob/living/carbon/human/dq_grants_hiding, /mob/verb/observe)
DECLARE_VERB_HIDE(/obj/item/dq_grants_declared/hiding, /obj/proc/dq_sys_grants_test_obj_verb)

/datum/unit_test/dq_sys_grants_verb_follows_sources

/datum/unit_test/dq_sys_grants_verb_follows_sources/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/first = allocate(/obj/item, test_floor())
	var/obj/item/second = allocate(/obj/item, test_floor())
	var/verb_path = /mob/living/proc/dq_sys_grants_test_verb
	TEST_ASSERT(!(verb_path in H.verbs), "the verb starts absent")

	om_grant(H, GRANT_VERB, verb_path, first)
	TEST_ASSERT(verb_path in H.verbs, "the first source's grant adds the verb")
	om_grant(H, GRANT_VERB, verb_path, second)
	om_revoke(H, GRANT_VERB, verb_path, first)
	TEST_ASSERT(verb_path in H.verbs, "the verb stays while another source grants it")

	qdel(second)
	TEST_ASSERT(!(verb_path in H.verbs), "deleting the last source removes the verb")
	TEST_ASSERT(!om_has_grant(H, GRANT_VERB, verb_path), "and the grant")

/datum/unit_test/dq_sys_grants_list_helpers

/datum/unit_test/dq_sys_grants_list_helpers/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/source = allocate(/obj/item, test_floor())
	var/obj/item/target = allocate(/obj/item, test_floor())
	var/verb_path = /mob/living/proc/dq_sys_grants_test_verb
	var/obj_verb = /obj/proc/dq_sys_grants_test_obj_verb

	om_grant_each(H, GRANT_VERB, list(verb_path), source)
	TEST_ASSERT(verb_path in H.verbs, "om_grant_each grants each id")
	om_revoke_all_of(H, GRANT_VERB, source)
	TEST_ASSERT(!(verb_path in H.verbs), "om_revoke_all_of revokes everything the source granted")

	om_grant(target, GRANT_VERB, obj_verb, source)
	TEST_ASSERT(obj_verb in target.verbs, "objects take verb grants too")
	om_revoke_each(target, GRANT_VERB, list(obj_verb), source)
	TEST_ASSERT(!(obj_verb in target.verbs), "om_revoke_each revokes each id")

/// A type verb that a grant also covers survives the grant's revoke; a hide beats both and lifting
/// it brings the type verb back (the old add/remove pairs desynced here).
/datum/unit_test/dq_sys_grants_hide_and_mixed_sources

/datum/unit_test/dq_sys_grants_hide_and_mixed_sources/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/granter = allocate(/obj/item, test_floor())
	var/obj/item/hider = allocate(/obj/item, test_floor())
	var/type_verb = /mob/verb/observe
	TEST_ASSERT(type_verb in H.verbs, "a human has /mob/verb/observe from its type")

	om_grant(H, GRANT_VERB, type_verb, granter)
	om_revoke(H, GRANT_VERB, type_verb, granter)
	TEST_ASSERT(type_verb in H.verbs, "revoking a grant keeps a verb the type gives")

	om_grant(H, GRANT_VERB, type_verb, granter)
	om_grant(H, GRANT_VERB_HIDE, type_verb, hider)
	TEST_ASSERT(!(type_verb in H.verbs), "a hide beats the type and a grant")
	qdel(hider)
	TEST_ASSERT(type_verb in H.verbs, "the hider's deletion brings the verb back")
	om_revoke(H, GRANT_VERB, type_verb, granter)
	TEST_ASSERT(type_verb in H.verbs, "and it stays with the type once the grant is gone")

	var/verb_path = /mob/living/proc/dq_sys_grants_test_verb
	hider = allocate(/obj/item, test_floor())
	om_grant(H, GRANT_VERB_HIDE, verb_path, hider)
	om_grant(H, GRANT_VERB, verb_path, granter)
	TEST_ASSERT(!(verb_path in H.verbs), "a grant made while hidden stays off")
	om_revoke(H, GRANT_VERB_HIDE, verb_path, hider)
	TEST_ASSERT(verb_path in H.verbs, "lifting the hide shows the granted verb")

/// DECLARE_VERB, DECLARE_VERB_IF and DECLARE_VERB_HIDE apply at init and keep no store entry.
/datum/unit_test/dq_sys_grants_declared_verbs

/datum/unit_test/dq_sys_grants_declared_verbs/Run()
	var/obj/item/dq_grants_declared/D = allocate(/obj/item/dq_grants_declared, test_floor())
	TEST_ASSERT(/obj/proc/dq_sys_grants_test_obj_verb in D.verbs, "DECLARE_VERB puts the verb on at init")
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_flag_verb in D.verbs), "DECLARE_VERB_IF stays off while the var is false")
	TEST_ASSERT(!D.om_rec?.contribs, "declared verbs keep no per-instance store entry")

	D.dq_flag = TRUE
	verb_store_refresh(D, /obj/proc/dq_sys_grants_test_flag_verb)
	TEST_ASSERT(/obj/proc/dq_sys_grants_test_flag_verb in D.verbs, "refreshing after the var turns true adds it")
	D.dq_flag = FALSE
	verb_store_refresh(D, /obj/proc/dq_sys_grants_test_flag_verb)
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_flag_verb in D.verbs), "and removes it when the var turns false")

	var/obj/item/source = allocate(/obj/item, test_floor())
	om_grant(D, GRANT_VERB, /obj/proc/dq_sys_grants_test_obj_verb, source)
	om_revoke(D, GRANT_VERB, /obj/proc/dq_sys_grants_test_obj_verb, source)
	TEST_ASSERT(/obj/proc/dq_sys_grants_test_obj_verb in D.verbs, "a revoke keeps a declared verb")

	var/obj/item/dq_grants_declared/hiding/H = allocate(/obj/item/dq_grants_declared/hiding, test_floor())
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_obj_verb in H.verbs), "a subtype's DECLARE_VERB_HIDE overrides the parent's DECLARE_VERB")
	om_grant(H, GRANT_VERB, /obj/proc/dq_sys_grants_test_obj_verb, source)
	TEST_ASSERT(!(/obj/proc/dq_sys_grants_test_obj_verb in H.verbs), "a declared hide beats a runtime grant")

	var/mob/living/carbon/human/dq_grants_hiding/M = allocate(/mob/living/carbon/human/dq_grants_hiding, test_floor())
	TEST_ASSERT(!(/mob/verb/observe in M.verbs), "DECLARE_VERB_HIDE strips an inherited /type/verb/")

/// VERB_NAMED: a renamed verb instance, granted and revoked by its key.
/datum/unit_test/dq_sys_grants_named_verb

/datum/unit_test/dq_sys_grants_named_verb/Run()
	var/obj/item/target = allocate(/obj/item, test_floor())
	var/obj/item/source = allocate(/obj/item, test_floor())
	var/key = VERB_NAMED(/obj/proc/dq_sys_grants_test_obj_verb, "DQ Renamed Verb", "A renamed test verb")
	om_grant(target, GRANT_VERB, key, source)
	TEST_ASSERT(has_verb(target, key), "the named verb is on after the grant")
	var/found = FALSE
	for(var/procpath/P as anything in target.verbs)
		if(P.name == "DQ Renamed Verb")
			found = TRUE
	TEST_ASSERT(found, "it shows under its own name")
	qdel(source)
	TEST_ASSERT(!has_verb(target, key), "the source's deletion takes it off")
	found = FALSE
	for(var/procpath/P as anything in target.verbs)
		if(P.name == "DQ Renamed Verb")
			found = TRUE
	TEST_ASSERT(!found, "and out of the verbs list")

/// Turf verbs are declared (DECLARE_VERB_IF on climbable): toggling needs no store entry on the turf.
/datum/unit_test/dq_sys_grants_turf_declared

/datum/unit_test/dq_sys_grants_turf_declared/Run()
	var/turf/simulated/T = test_floor()
	TEST_ASSERT(istype(T), "the test floor is simulated")
	var/was = T.climbable
	T.toggle_climbability()
	TEST_ASSERT_EQUAL(!!(/turf/simulated/proc/climb_wall in T.verbs), !!T.climbable, "climb_wall follows climbable after a toggle")
	T.toggle_climbability()
	TEST_ASSERT_EQUAL(!!(/turf/simulated/proc/climb_wall in T.verbs), !!was, "and back")
	TEST_ASSERT(!T.om_rec?.contribs, "a turf holds no verb grant")
