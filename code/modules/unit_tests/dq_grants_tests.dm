// Generic grant system (code/datums/grants/, doc/rewrite/grants.md): refcounting,
// apply/unapply ordering, auto-revoke on source deletion, queries, holder semantics
// on mind transfer, and the FACTORS/LANGUAGE kinds built on it.

/// A throwaway kind that just counts how many times on_grant()/on_revoke() fired,
/// so tests can check apply/unapply happen exactly once (on the first grant and
/// the last revoke), not once per source. Kind id well clear of the real
/// GRANT_KIND_* range so it never collides with one DQ Medical adds later.
#define GRANT_KIND_DQ_TEST_COUNTER 9001

/datum/grant_kind/dq_test_counter
	kind = GRANT_KIND_DQ_TEST_COUNTER
	var/grants = 0
	var/revokes = 0

/datum/grant_kind/dq_test_counter/on_grant(mob/M, id, datum/source)
	grants++

/datum/grant_kind/dq_test_counter/on_revoke(mob/M, id, datum/source)
	revokes++

/datum/unit_test/proc/dq_test_counter_kind()
	var/static/datum/grant_kind/dq_test_counter/K
	if(!K)
		K = new
	return K

/// Two sources granting the same (kind, id): the grant survives either one alone
/// being revoked, and disappears only once both have.
/datum/unit_test/dq_grants_refcount_two_sources

/datum/unit_test/dq_grants_refcount_two_sources/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source_a = new /datum()
	var/datum/source_b = new /datum()
	grant(H, GRANT_KIND_ABILITY, "dq_test_grant", source_a)
	TEST_ASSERT(H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "granted by one source")
	grant(H, GRANT_KIND_ABILITY, "dq_test_grant", source_b)
	TEST_ASSERT_EQUAL(length(H.grant_sources(GRANT_KIND_ABILITY, "dq_test_grant")), 2, "both sources tracked")
	revoke(H, GRANT_KIND_ABILITY, "dq_test_grant", source_a)
	TEST_ASSERT(H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "still granted through source_b")
	revoke(H, GRANT_KIND_ABILITY, "dq_test_grant", source_b)
	TEST_ASSERT(!H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "gone once every source revoked")
	TEST_ASSERT_NULL(H.grant_sources(GRANT_KIND_ABILITY, "dq_test_grant"), "no leftover empty source list")
	qdel(source_a)
	qdel(source_b)

/// Granting the same (kind, id, source) twice is a no-op: one revoke clears it.
/datum/unit_test/dq_grants_idempotent

/datum/unit_test/dq_grants_idempotent/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source = new /datum()
	grant(H, GRANT_KIND_ABILITY, "dq_test_grant", source)
	grant(H, GRANT_KIND_ABILITY, "dq_test_grant", source)
	TEST_ASSERT_EQUAL(length(H.grant_sources(GRANT_KIND_ABILITY, "dq_test_grant")), 1, "granting twice doesn't duplicate the source")
	revoke(H, GRANT_KIND_ABILITY, "dq_test_grant", source)
	TEST_ASSERT(!H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "one revoke clears a double grant")
	qdel(source)

/// The kind's on_grant()/on_revoke() fire exactly once - on the first source
/// granting and the last revoking - never once per source.
/datum/unit_test/dq_grants_apply_unapply_ordering

/datum/unit_test/dq_grants_apply_unapply_ordering/Run()
	var/datum/grant_kind/dq_test_counter/K = dq_test_counter_kind()
	var/before_grants = K.grants
	var/before_revokes = K.revokes
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source_a = new /datum()
	var/datum/source_b = new /datum()
	var/datum/source_c = new /datum()
	grant(H, GRANT_KIND_DQ_TEST_COUNTER, "counted", source_a)
	grant(H, GRANT_KIND_DQ_TEST_COUNTER, "counted", source_b)
	grant(H, GRANT_KIND_DQ_TEST_COUNTER, "counted", source_c)
	TEST_ASSERT_EQUAL(K.grants - before_grants, 1, "on_grant fires once, on the first source")
	revoke(H, GRANT_KIND_DQ_TEST_COUNTER, "counted", source_a)
	revoke(H, GRANT_KIND_DQ_TEST_COUNTER, "counted", source_b)
	TEST_ASSERT_EQUAL(K.revokes - before_revokes, 0, "on_revoke doesn't fire while a source remains")
	revoke(H, GRANT_KIND_DQ_TEST_COUNTER, "counted", source_c)
	TEST_ASSERT_EQUAL(K.revokes - before_revokes, 1, "on_revoke fires once, on the last source")
	qdel(source_a)
	qdel(source_b)
	qdel(source_c)

/// Deleting a source auto-revokes every grant it made, across every kind and
/// without the caller having to remember to revoke first.
/datum/unit_test/dq_grants_qdel_revokes_across_kinds

/datum/unit_test/dq_grants_qdel_revokes_across_kinds/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source = new /datum()
	grant(H, GRANT_KIND_ABILITY, "dq_test_grant", source)
	grant(H, GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM, source)
	grant(H, GRANT_KIND_FACTORS, alist(BF_ALPHA = 0.5), source)
	TEST_ASSERT(H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "ability grant is in place before qdel")
	TEST_ASSERT(H.has_grant(GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM), "language grant is in place before qdel")
	TEST_ASSERT(length(H.grants?[GRANT_KIND_FACTORS]), "factor grant is in place before qdel")
	qdel(source)
	TEST_ASSERT(!H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "ability grant was auto-revoked")
	TEST_ASSERT(!H.has_grant(GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM), "language grant was auto-revoked")
	TEST_ASSERT(!length(H.grants?[GRANT_KIND_FACTORS]), "factor grant was auto-revoked")
	TEST_ASSERT_NULL(grants_from(source), "the source index has nothing left for a deleted source")

/// has_grant()/grant_sources()/grants_from() answer consistently from both sides.
/datum/unit_test/dq_grants_queries

/datum/unit_test/dq_grants_queries/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source = new /datum()
	TEST_ASSERT(!H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "nothing granted yet")
	TEST_ASSERT_NULL(grants_from(source), "a fresh source grants nothing")
	grant(H, GRANT_KIND_ABILITY, "dq_test_grant", source)
	TEST_ASSERT(H.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "has_grant sees it")
	TEST_ASSERT(source in H.grant_sources(GRANT_KIND_ABILITY, "dq_test_grant"), "grant_sources lists the source")
	var/list/from = grants_from(source)
	TEST_ASSERT_EQUAL(length(from), 1, "grants_from lists exactly the one grant")
	var/datum/grant_link/link = from[1]
	TEST_ASSERT_EQUAL(link.M, H, "the link points at the granted mob")
	TEST_ASSERT_EQUAL(link.kind, GRANT_KIND_ABILITY, "the link records the kind")
	TEST_ASSERT_EQUAL(link.id, "dq_test_grant", "the link records the id")
	revoke(H, GRANT_KIND_ABILITY, "dq_test_grant", source)
	TEST_ASSERT_NULL(grants_from(source), "grants_from is empty again once revoked")
	qdel(source)

/// revoke_all() clears every kind a source granted on one mob, without touching
/// what it granted on another.
/datum/unit_test/dq_grants_revoke_all

/datum/unit_test/dq_grants_revoke_all/Run()
	var/mob/living/carbon/human/H1 = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source = new /datum()
	grant(H1, GRANT_KIND_ABILITY, "dq_test_grant", source)
	grant(H1, GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM, source)
	grant(H2, GRANT_KIND_ABILITY, "dq_test_grant", source)
	revoke_all(H1, source)
	TEST_ASSERT(!H1.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "H1's ability grant is gone")
	TEST_ASSERT(!H1.has_grant(GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM), "H1's language grant is gone")
	TEST_ASSERT(H2.has_grant(GRANT_KIND_ABILITY, "dq_test_grant"), "H2's grant from the same source is untouched")
	revoke_all(H2, source)
	qdel(source)

/// A FACTORS grant folds its table into recompute_factors() and marks the body
/// dirty; revoking it removes the contribution again.
/datum/unit_test/dq_grants_factor_dirtying

/datum/unit_test/dq_grants_factor_dirtying/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_EQUAL(H.factor(BF_ALPHA), body_factor_baseline(BF_ALPHA), "alpha starts at baseline")
	var/datum/source = new /datum()
	grant(H, GRANT_KIND_FACTORS, alist(BF_ALPHA = 0.25), source)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_FACTORS, "granting a factor table marks the body dirty")
	TEST_ASSERT(dq_near(H.factor(BF_ALPHA), 0.25), "the granted table folds into the live factor, got [H.factor(BF_ALPHA)]")
	revoke(H, GRANT_KIND_FACTORS, alist(BF_ALPHA = 0.25), source)
	TEST_ASSERT_EQUAL(H.factor(BF_ALPHA), body_factor_baseline(BF_ALPHA), "revoking drops it back to baseline")
	qdel(source)

/// A language granted by two overlapping sources stays known until both revoke -
/// same refcounting as ability, driven through GRANT_KIND_LANGUAGE's add_language()/
/// remove_language() hooks.
/datum/unit_test/dq_grants_language_overlapping_sources

/datum/unit_test/dq_grants_language_overlapping_sources/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/language/L = GLOB.all_languages[LANGUAGE_GALCOM]
	var/datum/source_a = new /datum()
	var/datum/source_b = new /datum()
	var/already_knew = (L in H.languages)
	grant(H, GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM, source_a)
	TEST_ASSERT(L in H.languages, "the language is added on the first grant")
	grant(H, GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM, source_b)
	TEST_ASSERT(L in H.languages, "still known with two sources")
	revoke(H, GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM, source_a)
	TEST_ASSERT(L in H.languages, "still known through source_b")
	revoke(H, GRANT_KIND_LANGUAGE, LANGUAGE_GALCOM, source_b)
	TEST_ASSERT_EQUAL((L in H.languages), already_knew, "removed once every source has revoked (back to however it started)")
	qdel(source_a)
	qdel(source_b)

/// Holder semantics on mind transfer: a grant sourced from the mind itself moves
/// to the new body; a grant sourced from something else (standing in for an organ,
/// implant or item) stays on the old body.
/datum/unit_test/dq_grants_transfer_holder_semantics

/datum/unit_test/dq_grants_transfer_holder_semantics/Run()
	var/mob/living/carbon/human/H1 = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, test_floor())
	var/datum/mind/M = dq_test_give_mind(H1, "dq_grants_transfer")
	TEST_ASSERT_NOTNULL(M, "H1 has a mind")
	var/datum/body_source = new /datum() // stands in for an organ/implant/item: stays put
	grant(H1, GRANT_KIND_ABILITY, "dq_mind_grant", M)
	grant(H1, GRANT_KIND_ABILITY, "dq_body_grant", body_source)
	transfer_mind(M, H2, "dq_grants_transfer test", force = TRUE)
	TEST_ASSERT(H2.has_grant(GRANT_KIND_ABILITY, "dq_mind_grant"), "the mind-sourced grant followed the mind to H2")
	TEST_ASSERT(!H1.has_grant(GRANT_KIND_ABILITY, "dq_mind_grant"), "H1 no longer carries the mind-sourced grant")
	TEST_ASSERT(H1.has_grant(GRANT_KIND_ABILITY, "dq_body_grant"), "the body-sourced grant stayed on H1")
	TEST_ASSERT(!H2.has_grant(GRANT_KIND_ABILITY, "dq_body_grant"), "H2 never had the body-sourced grant")
	revoke(H1, GRANT_KIND_ABILITY, "dq_body_grant", body_source)
	qdel(body_source)

/// A robot module's language grants are refcounted against the robot's own innate
/// grant (robot.dm's Initialize()): removing the module never needs to snapshot and
/// restore anything, it just drops what nothing else still grants. Also checks
/// GRANT_KIND_LANGUAGE_SPEECH: languages[lang] = 1 grants speech too, = 0 understanding only.
/datum/unit_test/dq_grants_robot_module_languages

/datum/unit_test/dq_grants_robot_module_languages/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/datum/language/robot_talk = GLOB.all_languages[LANGUAGE_ROBOT_TALK]
	var/datum/language/sol_common = GLOB.all_languages[LANGUAGE_SOL_COMMON]
	var/datum/language/unathi = GLOB.all_languages[LANGUAGE_UNATHI]
	TEST_ASSERT(robot_talk in R.languages, "every robot starts knowing robot talk (innate grant)")
	TEST_ASSERT(robot_talk in R.speech_synthesizer_langs, "and can speak it")

	var/obj/item/robot_module/module = new(R)
	module.add_languages(R)
	TEST_ASSERT(sol_common in R.languages, "the module's languages[LANGUAGE_SOL_COMMON]=1 entry is understood")
	TEST_ASSERT(sol_common in R.speech_synthesizer_langs, "...and speakable (can_speak = 1)")
	TEST_ASSERT(unathi in R.languages, "languages[LANGUAGE_UNATHI]=0 is still understood")
	TEST_ASSERT(!(unathi in R.speech_synthesizer_langs), "...but not speakable (can_speak = 0)")

	module.remove_languages(R)
	TEST_ASSERT(!(sol_common in R.languages), "the module's own language is gone once the module is")
	TEST_ASSERT(!(unathi in R.languages), "same for its understand-only language")
	TEST_ASSERT(robot_talk in R.languages, "the robot's innate grant survived - no snapshot/restore needed")
	TEST_ASSERT(robot_talk in R.speech_synthesizer_langs, "...still speakable too")
	qdel(module)

#undef GRANT_KIND_DQ_TEST_COUNTER
