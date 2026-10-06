// W6 O5: the sealed death pipeline, the one revive path (return_from_death()) and the
// vital-state predicates.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Counts the death and revival signals a mob sends.
/datum/dq_vital_listener
	var/deaths = 0
	var/finals = 0
	var/revivals = 0
	var/datum/last_revive_source
	var/last_revive_reason
	/// stat seen when mob_death arrived (the transition must already have happened).
	var/stat_at_death

/datum/dq_vital_listener/proc/watch(mob/living/L)
	observe(L, /datum/notice/mob_death, src, then(PROC_REF(on_death)))
	observe(L, /datum/notice/living_death_final, src, then(PROC_REF(on_final)))
	observe(L, /datum/notice/living_revived, src, then(PROC_REF(on_revived)))

/datum/dq_vital_listener/proc/on_death(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/source = N.target
	deaths++
	stat_at_death = source.stat

/datum/dq_vital_listener/proc/on_final(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	finals++

/datum/dq_vital_listener/proc/on_revived(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/living_revived/event = N
	revivals++
	rel_set(src, nameof(last_revive_source), event.source_)
	last_revive_reason = event.reason

// --- Death pipeline ------------------------------------------------------------------------

/// death() transitions once: stat, lists and time of death, then the signals in order.
/datum/unit_test/dq_death_pipeline_transitions_once

/datum/unit_test/dq_death_pipeline_transitions_once/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/dq_vital_listener/listener = new
	listener.watch(H)
	TEST_ASSERT(H.death(), "the first death() should report the transition")
	TEST_ASSERT_EQUAL(H.stat, DEAD, "death() should leave the mob DEAD")
	TEST_ASSERT(H in REGISTRY_MEMBERS(REGISTRY_DEAD_MOBS), "a dead mob is on the dead list")
	TEST_ASSERT(!(H in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)), "a dead mob is off the living list")
	TEST_ASSERT(H.timeofdeath > 0, "death() records the time of death")
	TEST_ASSERT_EQUAL(listener.stat_at_death, DEAD, "mob_death is emitted after the stat transition")
	TEST_ASSERT_EQUAL(listener.deaths, 1, "mob_death is emitted once")
	TEST_ASSERT_EQUAL(listener.finals, 1, "living_death_final is emitted once")
	qdel(listener)

/// delete_on_death rides the pipeline's final hook: the mob is deleted after every listener
/// (living_death_final included) has run, never by a stat change.
/datum/unit_test/dq_death_final_hook_deletes_on_death

/datum/unit_test/dq_death_final_hook_deletes_on_death/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	M.delete_on_death = TRUE
	var/datum/dq_vital_listener/listener = new
	listener.watch(M)
	M.set_stat(UNCONSCIOUS)
	TEST_ASSERT(!QDELETED(M), "a stat change alone must not delete a delete_on_death mob")
	M.death()
	TEST_ASSERT_EQUAL(listener.finals, 1, "the final hook's listeners run before the deletion")
	TEST_ASSERT(QDELETED(M), "delete_on_death deletes the mob from the final hook")
	qdel(listener)

/// A repeated death() is a no-op: no second signal, no second time of death.
/datum/unit_test/dq_death_pipeline_repeat_has_no_side_effects

/datum/unit_test/dq_death_pipeline_repeat_has_no_side_effects/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/datum/dq_vital_listener/listener = new
	listener.watch(M)
	TEST_ASSERT(M.death(), "the first death() should transition")
	var/first_time = M.timeofdeath
	TEST_ASSERT(!M.death(), "a second death() must report no transition")
	TEST_ASSERT(!M.death(TRUE), "a gibbed repeat is refused too")
	TEST_ASSERT_EQUAL(M.timeofdeath, first_time, "a repeated death() must not move the time of death")
	TEST_ASSERT_EQUAL(listener.deaths, 1, "mob_death must not repeat")
	TEST_ASSERT_EQUAL(listener.finals, 1, "living_death_final must not repeat")
	qdel(listener)

/// replace_death() takes over before any side effect: the cockroach vanishes, never DEAD.
/datum/unit_test/dq_death_pipeline_replace_death

/datum/unit_test/dq_death_pipeline_replace_death/Run()
	var/mob/living/simple_mob/animal/passive/cockroach/C = allocate(/mob/living/simple_mob/animal/passive/cockroach)
	var/turf/where = get_turf(C)
	var/datum/dq_vital_listener/listener = new
	listener.watch(C)
	TEST_ASSERT(!C.death(), "a replaced death reports no transition")
	for(var/obj/effect/decal/cleanable/bug_remains/R in where)
		own(R)
	TEST_ASSERT(QDELETED(C), "the cockroach vanishes instead")
	TEST_ASSERT_EQUAL(listener.deaths, 0, "a replaced death sends no death signal")
	TEST_ASSERT_EQUAL(listener.finals, 0, "a replaced death sends no final signal")
	qdel(listener)

/// Subtypes pick their message through death_message / get_death_message(), not death() args.
/datum/unit_test/dq_death_pipeline_messages

/datum/unit_test/dq_death_pipeline_messages/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT_EQUAL(M.get_death_message(FALSE), "dies!", "simple mobs die with their own message")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.get_death_message(FALSE), H.species.get_death_message(H), "humans use the species message")
	var/mob/living/carbon/brain/B = allocate(/mob/living/carbon/brain)
	TEST_ASSERT_EQUAL(B.get_death_message(FALSE), DEATHGASP_NO_MESSAGE, "a loose brain view dies silently")

/// The simple mob's on_death() clears density; its on_revived() restores it (A8).
/datum/unit_test/dq_death_simple_mob_revive_restores

/datum/unit_test/dq_death_simple_mob_revive_restores/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/initial_density = M.density
	M.death()
	TEST_ASSERT(!M.density, "a dead simple mob doesn't block")
	TEST_ASSERT_EQUAL(M.return_from_death("unit test", src, REVIVE_HEAL), TRUE, "a healed mouse comes back")
	TEST_ASSERT_EQUAL(M.density, initial_density, "revival restores density")

// --- One revive path ---------------------------------------------------------------------

/// return_from_death() is the way back: lists, time of death, stat, signal and source.
/datum/unit_test/dq_revive_restores_life

/datum/unit_test/dq_revive_restores_life/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/dq_vital_listener/listener = new
	listener.watch(H)
	H.death()
	var/obj/item/shockpaddles/paddles = allocate(/obj/item/shockpaddles)
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", paddles), TRUE, "a fresh corpse with a working brain comes back")
	TEST_ASSERT_EQUAL(H.stat, CONSCIOUS, "the default revival is conscious")
	TEST_ASSERT(H in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS), "a revived mob is on the living list")
	TEST_ASSERT(!(H in REGISTRY_MEMBERS(REGISTRY_DEAD_MOBS)), "a revived mob is off the dead list")
	TEST_ASSERT_EQUAL(H.timeofdeath, 0, "revival clears the time of death")
	TEST_ASSERT_EQUAL(listener.revivals, 1, "living_revived is emitted once")
	TEST_ASSERT_EQUAL(listener.last_revive_source, paddles, "the signal carries the source")
	TEST_ASSERT_EQUAL(listener.last_revive_reason, "unit test", "the signal carries the reason")
	TEST_ASSERT(H.death(), "a revived mob can die again through the pipeline")
	qdel(listener)

/// Refusals: a living mob, and a revival window that has closed.
/datum/unit_test/dq_revive_refusals

/datum/unit_test/dq_revive_refusals/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", src), "not dead", "a living mob can't be revived")
	H.death()
	var/obj/item/organ/internal/brain/brain = H.organ_in(O_BRAIN)
	TEST_ASSERT(istype(brain), "a human has a brain")
	brain.expire_defib_window()
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", src), "brain decayed", "a decayed brain closes the window")
	TEST_ASSERT_EQUAL(H.stat, DEAD, "a refused revival leaves the mob dead")
	TEST_ASSERT(H in REGISTRY_MEMBERS(REGISTRY_DEAD_MOBS), "a refused revival leaves the lists alone")
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", src, REVIVE_IGNORE_WINDOW), TRUE, "ignoring the window revives")

/// Lethal injuries always refuse; REVIVE_HEAL heals them first.
/datum/unit_test/dq_revive_lethal_injuries

/datum/unit_test/dq_revive_lethal_injuries/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	M.injure(INJURY_BLUNT, M.get_endurance() * 3, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_EQUAL(M.stat, DEAD, "lethal injuries kill")
	TEST_ASSERT(M.body.is_lethal(), "the body reports lethal injuries")
	TEST_ASSERT_EQUAL(M.return_from_death("unit test", src, REVIVE_IGNORE_WINDOW), "lethal injuries", "lethal injuries refuse even without the window")
	TEST_ASSERT_EQUAL(M.stat, DEAD, "still dead")
	TEST_ASSERT_EQUAL(M.return_from_death("unit test", src, REVIVE_HEAL), TRUE, "REVIVE_HEAL heals first, then revives")
	TEST_ASSERT(!M.body.is_lethal(), "healed")

/// REVIVE_UNCONSCIOUS lands unconscious (defib, CPR).
/datum/unit_test/dq_revive_unconscious

/datum/unit_test/dq_revive_unconscious/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.death()
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", src, REVIVE_UNCONSCIOUS), TRUE, "the revival succeeds")
	TEST_ASSERT_EQUAL(H.stat, UNCONSCIOUS, "REVIVE_UNCONSCIOUS lands unconscious")

/// Rejuvenate (admin heal, resleeving) routes a dead mob through return_from_death().
/datum/unit_test/dq_revive_rejuvenate_routes_through

/datum/unit_test/dq_revive_rejuvenate_routes_through/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/dq_vital_listener/listener = new
	listener.watch(H)
	H.death()
	H.rejuvenate()
	TEST_ASSERT(H.stat != DEAD, "rejuvenate revives")
	TEST_ASSERT_EQUAL(listener.revivals, 1, "rejuvenate revives through return_from_death()")
	TEST_ASSERT_EQUAL(listener.last_revive_reason, "rejuvenated", "with its own reason")
	qdel(listener)

/// Robots come back through the pipeline too: rejuvenate rebuilds and revives.
/datum/unit_test/dq_revive_robot_rejuvenate

/datum/unit_test/dq_revive_robot_rejuvenate/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/datum/dq_vital_listener/listener = new
	listener.watch(R)
	R.death()
	TEST_ASSERT_EQUAL(R.stat, DEAD, "the robot dies")
	R.rejuvenate()
	TEST_ASSERT(R.stat != DEAD, "rejuvenate revives the robot")
	TEST_ASSERT_EQUAL(listener.revivals, 1, "through return_from_death()")
	qdel(listener)

/// Vore reform's flags revive anything dead: a husked body whose brain decayed and died.
/datum/unit_test/dq_revive_restore_always_succeeds

/datum/unit_test/dq_revive_restore_always_succeeds/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.death()
	var/obj/item/organ/internal/brain/brain = H.organ_in(O_BRAIN)
	TEST_ASSERT(istype(brain), "a human has a brain")
	brain.expire_defib_window()
	brain.die()
	H.ChangeToHusk()
	TEST_ASSERT(H.return_from_death("unit test", src, REVIVE_HEAL) != TRUE, "without REVIVE_RESTORE the dead brain refuses")
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", src, REVIVE_RESTORE | REVIVE_IGNORE_WINDOW | REVIVE_HEAL | REVIVE_UNCONSCIOUS), TRUE, "reform flags always revive")
	TEST_ASSERT(H.stat != DEAD, "the reformed body is alive")
	TEST_ASSERT(!(HUSK in H.mutations), "the husk is cleared")
	TEST_ASSERT(!H.is_brain_dead(), "the brain is restored")

/// REVIVE_RESTORE regrows a missing brain.
/datum/unit_test/dq_revive_restore_regrows_brain

/datum/unit_test/dq_revive_restore_regrows_brain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.death()
	var/obj/item/organ/internal/brain/brain = H.organ_in(O_BRAIN)
	brain.removed()
	qdel(brain)
	TEST_ASSERT_NULL(H.organ_in(O_BRAIN), "the brain is gone")
	TEST_ASSERT_EQUAL(H.return_from_death("unit test", src, REVIVE_RESTORE | REVIVE_IGNORE_WINDOW | REVIVE_HEAL), TRUE, "reform flags revive a brainless body")
	TEST_ASSERT_NOTNULL(H.organ_in(O_BRAIN), "the brain is regrown")

/// Vore reform fully restores the stored body: a husked, brain-dead, badly hurt corpse comes back whole.
/datum/unit_test/dq_revive_reform_restore_full

/datum/unit_test/dq_revive_reform_restore_full/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_BLUNT, 60, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.death()
	var/obj/item/organ/internal/brain/brain = H.organ_in(O_BRAIN)
	brain.expire_defib_window()
	brain.die()
	H.ChangeToHusk()
	H.reform_restore("unit test", src)
	TEST_ASSERT(H.stat != DEAD, "reform always revives")
	TEST_ASSERT(!(HUSK in H.mutations), "the husk is cleared")
	TEST_ASSERT(!H.is_brain_dead(), "the brain is restored")
	TEST_ASSERT(!H.is_injured(), "the body is fully healed, not left barely out of crit")

// --- Vital-state predicates --------------------------------------------------------------

/// alive / dead / band follow stat and vitality.
/datum/unit_test/dq_vital_predicates_bands

/datum/unit_test/dq_vital_predicates_bands/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(M.is_alive() && !M.is_dead(), "a fresh mouse is alive")
	TEST_ASSERT(!M.is_dying(), "a fresh mouse is not dying")
	TEST_ASSERT_EQUAL(M.vital_band(), VITAL_BAND_HEALTHY, "a fresh mouse is healthy")
	M.injure(INJURY_BLUNT, M.get_endurance() * 0.6, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT(M.is_alive(), "60% of endurance doesn't kill")
	TEST_ASSERT_EQUAL(M.vital_band(), VITAL_BAND_HURT, "vitality 0.4 is hurt ([M.vitality()])")
	M.injure(INJURY_BLUNT, M.get_endurance() * 0.1, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_EQUAL(M.vital_band(), VITAL_BAND_SERIOUS, "vitality 0.3 is serious ([M.vitality()])")
	M.death()
	TEST_ASSERT(M.is_dead() && !M.is_alive(), "a dead mouse is dead")
	TEST_ASSERT(!M.is_dying(), "the dead are not dying")
	TEST_ASSERT_EQUAL(M.vital_band(), VITAL_BAND_DEAD, "the dead band")
	TEST_ASSERT_EQUAL(vital_band_name(VITAL_BAND_DEAD), "dead", "band names")

/// is_dying(): alive, but the body's injuries are lethal (a keep-alive holds the death off).
/datum/unit_test/dq_vital_predicates_dying

/datum/unit_test/dq_vital_predicates_dying/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	observe(M, /datum/act/body_status, src, instead())
	M.injure(INJURY_BLUNT, M.get_endurance() * 3, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT(M.is_alive(), "the keep-alive should hold off death while lethally hurt")
	TEST_ASSERT(M.body.is_lethal(), "the injuries are lethal")
	TEST_ASSERT(M.is_dying(), "alive with lethal injuries is dying")
	TEST_ASSERT_EQUAL(M.vital_band(), VITAL_BAND_DYING, "the dying band")
	unobserve(M, /datum/act/body_status, src)

#endif
