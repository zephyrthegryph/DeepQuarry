// J6: the keeps_dead opt-outs that stay are the ones whose handler tail is cleanup that must run when an argument was deleted before the timer fired
// (doc/rewrite/framework_gaps.md J6 lists every audited site). Each test schedules the real handler as its site does, deletes the argument and
// asserts the cleanup happened.

/datum/unit_test/om/keeps_dead_smoke_counter_still_drops

/datum/unit_test/om/keeps_dead_smoke_counter_still_drops/run_om(list/made)
	var/datum/effect/effect/system/smoke_spread/S = new
	var/obj/effect/effect/smoke/smoke = allocate(/obj/effect/effect/smoke)
	S.total_smoke = 3
	after(S, 1 SECONDS, TYPE_PROC_REF(/datum/effect/effect/system/smoke_spread, expire_smoke), with = list(smoke), keeps_dead = TRUE)
	qdel(smoke)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(S.total_smoke, 2, "a smoke puff deleted before it expired still frees its slot of the emitter")
	qdel(S)

/datum/unit_test/om/keeps_dead_confetti_counter_still_drops

/datum/unit_test/om/keeps_dead_confetti_counter_still_drops/run_om(list/made)
	var/datum/effect/effect/system/confetti_spread/S = new
	var/obj/effect/effect/confetti/confetti = allocate(/obj/effect/effect/confetti)
	S.total_confetti = 3
	after(S, 1 SECONDS, TYPE_PROC_REF(/datum/effect/effect/system/confetti_spread, expire_confetti), with = list(confetti), keeps_dead = TRUE)
	qdel(confetti)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(S.total_confetti, 2, "a confetti puff deleted before it expired still frees its slot of the emitter")
	qdel(S)

/datum/unit_test/om/keeps_dead_mend_rune_releases_its_strain

/datum/unit_test/om/keeps_dead_mend_rune_releases_its_strain/run_om(list/made)
	var/mob/living/simple_mob/e0_fixture/caster = allocate(/mob/living/simple_mob/e0_fixture)
	var/before = GLOB.runedec
	GLOB.runedec += 10
	after(null, 1 SECONDS, GLOBAL_PROC_REF(cult_mend_rune_wait), with = list(caster), keeps_dead = TRUE)
	qdel(caster)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(GLOB.runedec, before, "a caster deleted while dead no longer holds the mend rune's strain on reality")
