// Verbs through grants (doc/rewrite/systems.md §19): a GRANT_VERB grant puts the verb on the
// atom while any source grants it; the last revoke, or the last source's deletion, takes it off.

/mob/living/proc/dq_sys_grants_test_verb()
	set name = "DQ Grants Test Verb"
	set hidden = TRUE

/obj/proc/dq_sys_grants_test_obj_verb()
	set name = "DQ Grants Test Object Verb"
	set hidden = TRUE

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
