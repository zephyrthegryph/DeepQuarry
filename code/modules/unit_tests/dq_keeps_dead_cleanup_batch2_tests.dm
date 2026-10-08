// J6 batch 2: cleanup tests for the remaining kept keeps_dead sites (doc/rewrite/framework_gaps.md "J6 audit"). Same shape as dq_keeps_dead_cleanup_more_tests.dm.

/datum/unit_test/om/keeps_dead_tube_arrival_opened_clears_moving

/datum/unit_test/om/keeps_dead_tube_arrival_opened_clears_moving/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/structure/transit_tube/station/station = allocate(/obj/structure/transit_tube/station, T)
	var/obj/structure/transit_tube_pod/pod = allocate(/obj/structure/transit_tube_pod, T)
	station.pod_moving = 1
	after(station, 1 SECONDS, TYPE_PROC_REF(/obj/structure/transit_tube/station, arrival_opened), with = list(pod), keeps_dead = TRUE)
	qdel(pod)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(station.pod_moving, 0, "the station is not left busy after its pod is gone")

/datum/unit_test/om/keeps_dead_tube_arrival_open_chain

/datum/unit_test/om/keeps_dead_tube_arrival_open_chain/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/structure/transit_tube/station/station = allocate(/obj/structure/transit_tube/station, T)
	var/obj/structure/transit_tube_pod/pod = allocate(/obj/structure/transit_tube_pod, T)
	station.pod_moving = 1
	after(station, 0.5 SECONDS, TYPE_PROC_REF(/obj/structure/transit_tube/station, arrival_open), with = list(pod), keeps_dead = TRUE)
	qdel(pod)
	scheduler_advance(4)
	TEST_ASSERT_EQUAL(station.pod_moving, 0, "the arrival still finishes opening when the pod is gone")

/datum/unit_test/om/keeps_dead_toilet_tertiary_flush_refills

/datum/unit_test/om/keeps_dead_toilet_tertiary_flush_refills/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/structure/toilet/toilet = allocate(/obj/structure/toilet, T)
	var/obj/item/pen/flushed = allocate(/obj/item/pen, T)
	toilet.refilling = TRUE
	after(toilet, 0.1 SECONDS, TYPE_PROC_REF(/obj/structure/toilet, tertiary_flush), with = list(flushed, TRUE), keeps_dead = TRUE)
	qdel(flushed)
	scheduler_advance(25)
	TEST_ASSERT(!toilet.refilling, "the toilet is not stuck refilling when the flushed object is gone")

/datum/unit_test/om/keeps_dead_needle_cycle_resets_mode

/datum/unit_test/om/keeps_dead_needle_cycle_resets_mode/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe, T)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	S.mode = NEEDLE_INJECT
	after(S, 1 SECONDS, GLOBAL_PROC_REF(needle_inject_cycle), with = list(S, user, target, 1 SECONDS, 0, 0, "mode", T, T, null), keeps_dead = TRUE)
	qdel(user)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(S.mode, NEEDLE_DRAW, "the emptied syringe is set back to draw when the injector is gone")

/datum/unit_test/om/keeps_dead_anomalock_clears_overlay_ref

/datum/unit_test/om/keeps_dead_anomalock_clears_overlay_ref/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/organ/internal/heart/machine/anomalock/heart = allocate(/obj/item/organ/internal/heart/machine/anomalock, T)
	heart.lightning_overlay = mutable_appearance(icon = 'icons/effects/effects.dmi', icon_state = "lightning")
	after(heart, 1 SECONDS, TYPE_PROC_REF(/obj/item/organ/internal/heart/machine/anomalock, clear_lightning_overlay), key = "lightning_timer", with = list(H), keeps_dead = TRUE)
	qdel(H)
	scheduler_advance(2)
	TEST_ASSERT(isnull(heart.lightning_overlay), "the heart does not keep a stale lightning overlay")

/datum/unit_test/om/keeps_dead_stealth_armour_ends_stealth

/datum/unit_test/om/keeps_dead_stealth_armour_ends_stealth/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/suit/armor/reactive/stealth/armour = allocate(/obj/item/clothing/suit/armor/reactive/stealth, T)
	armour.in_stealth = TRUE
	after(armour, 1 SECONDS, TYPE_PROC_REF(/obj/item/clothing/suit/armor/reactive/stealth, end_stealth), with = list(H), keeps_dead = TRUE)
	qdel(H)
	scheduler_advance(2)
	TEST_ASSERT(!armour.in_stealth, "the armour is not left in stealth")

/datum/unit_test/om/keeps_dead_vending_finish_resets_ready

/datum/unit_test/om/keeps_dead_vending_finish_resets_ready/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/machinery/vending/V = allocate(/obj/machinery/vending, T)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/datum/stored_item/vending_product/R = new /datum/stored_item/vending_product(V, /obj/item/pen, null, 1)
	V.set_vend_ready(FALSE)
	after(V, 1 SECONDS, TYPE_PROC_REF(/obj/machinery/vending, finish_vend), with = list(R, user), keeps_dead = TRUE)
	qdel(R)
	scheduler_advance(2)
	TEST_ASSERT(V.vend_ready, "the machine is ready again when the product record is gone")

// keeps_dead cleanup tests, batch 1: each schedules the site's real handler with keeps_dead, deletes the datum argument first and asserts
// the cleanup still happened. Not tested here: fulton chain (covered by c4_fulton_deleted_payload), dark_maw do_trigger (lit test map
// makes the maw self-delete on Initialize), integrated circuit inject_mob (UNSURE).

/// A lunge whose target vanished still drops the leaping flag.
/datum/unit_test/om/keeps_dead_target_lunge_land_clears_leaping

/datum/unit_test/om/keeps_dead_target_lunge_land_clears_leaping/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	H.set_status_flags(H.status_flags | LEAPING)
	after(H, 1 SECONDS, TYPE_PROC_REF(/mob/living, target_lunge_land), with = list(target), keeps_dead = TRUE)
	qdel(target)
	scheduler_advance(2)
	TEST_ASSERT(!(H.status_flags & LEAPING), "the lunger stops leaping when the target is gone")

/// A xenomorph leap at a vanished target still drops the leaping flag.
/datum/unit_test/om/keeps_dead_alien_leap_land_clears_leaping

/datum/unit_test/om/keeps_dead_alien_leap_land_clears_leaping/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	H.set_status_flags(H.status_flags | LEAPING)
	after(H, 1 SECONDS, TYPE_PROC_REF(/mob/living/carbon/human, leap_land), with = list(target), keeps_dead = TRUE)
	qdel(target)
	scheduler_advance(2)
	TEST_ASSERT(!(H.status_flags & LEAPING), "the leaper stops leaping when the target is gone")

/// A borg leap at a vanished target still drops the leaping flag.
/datum/unit_test/om/keeps_dead_borg_leap_land_clears_leaping

/datum/unit_test/om/keeps_dead_borg_leap_land_clears_leaping/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	R.set_status_flags(R.status_flags | LEAPING)
	after(R, 1 SECONDS, TYPE_PROC_REF(/mob/living/silicon/robot, leap_land), with = list(target), keeps_dead = TRUE)
	qdel(target)
	scheduler_advance(2)
	TEST_ASSERT(!(R.status_flags & LEAPING), "the borg stops leaping when the target is gone")

/// A simple mob leap at a vanished target still drops the leaping flag.
/datum/unit_test/om/keeps_dead_simple_mob_leap_land_clears_leaping

/datum/unit_test/om/keeps_dead_simple_mob_leap_land_clears_leaping/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	S.set_status_flags(S.status_flags | LEAPING)
	after(S, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob, leap_land), with = list(target), keeps_dead = TRUE)
	qdel(target)
	scheduler_advance(2)
	TEST_ASSERT(!(S.status_flags & LEAPING), "the mob stops leaping when the target is gone")

/// A telegraphed attack whose target vanished still ends the AI hold.
/datum/unit_test/om/keeps_dead_attack_delay_releases_ai_hold

/datum/unit_test/om/keeps_dead_attack_delay_releases_ai_hold/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_test_subject, T)
	var/obj/item/paper/A = allocate(/obj/item/paper, T)
	TEST_ASSERT(S.ai_brain, "the subject owns an AI brain")
	S.handle_attack_delay(A, 1 SECONDS, null)
	TEST_ASSERT(S.ai_brain.is_busy(), "the telegraph holds the AI")
	qdel(A)
	scheduler_advance(5)
	TEST_ASSERT(!S.ai_brain.is_busy(), "the AI hold ends although the target is gone")

/// A dragon lunge whose target vanished before the leap still releases the AI hold.
/datum/unit_test/om/keeps_dead_ddraig_lunge_1_releases_ai_hold

/datum/unit_test/om/keeps_dead_ddraig_lunge_1_releases_ai_hold/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/ddraig/D = allocate(/mob/living/simple_mob/vore/ddraig, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(D.ai_brain, "the dragon owns an AI brain")
	D.ai_busy_begin()
	TEST_ASSERT(D.ai_brain.is_busy(), "the telegraph holds the AI")
	after(D, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/ddraig, lunge_1), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!D.ai_brain.is_busy(), "the AI hold ends although the target is gone")

/// The dragon's landing step drops the leaping flag and the AI hold when the target vanished.
/datum/unit_test/om/keeps_dead_ddraig_lunge_2_lands

/datum/unit_test/om/keeps_dead_ddraig_lunge_2_lands/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/ddraig/D = allocate(/mob/living/simple_mob/vore/ddraig, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(D.ai_brain, "the dragon owns an AI brain")
	D.ai_busy_begin()
	D.set_status_flags(D.status_flags | LEAPING)
	after(D, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/ddraig, lunge_2), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!(D.status_flags & LEAPING), "the dragon stops leaping when the target is gone")
	TEST_ASSERT(!D.ai_brain.is_busy(), "and the AI hold ends")

// keeps_dead cleanup tests, batch 2: each schedules the real handler with keeps_dead, deletes the victim/target arg, and asserts the owner's busy hold was released.
// cultist/wraith use a null destination (the handler's own abort path) so the hold release is reachable without a real jaunt.

/datum/unit_test/om/keeps_dead_ddraig_firebreath_releases_busy

/datum/unit_test/om/keeps_dead_ddraig_firebreath_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/ddraig/D = allocate(/mob/living/simple_mob/vore/ddraig, T)
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	D.ai_busy_begin()
	TEST_ASSERT(D.ai_brain.is_busy(), "the windup claims the AI")
	after(D, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/ddraig, firebreathend), with = list(A), keeps_dead = TRUE)
	qdel(A)
	scheduler_advance(2)
	TEST_ASSERT(!D.ai_brain.is_busy(), "the dragon busy hold is released when its target is gone")

/datum/unit_test/om/keeps_dead_bigdragon_firebreath_releases_busy

/datum/unit_test/om/keeps_dead_bigdragon_firebreath_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/bigdragon/D = allocate(/mob/living/simple_mob/vore/bigdragon, T)
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	D.ai_busy_begin()
	TEST_ASSERT(D.ai_brain.is_busy(), "the windup claims the AI")
	after(D, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/bigdragon, firebreathend), with = list(A), keeps_dead = TRUE)
	qdel(A)
	scheduler_advance(2)
	TEST_ASSERT(!D.ai_brain.is_busy(), "the dragon busy hold is released when its target is gone")

/datum/unit_test/om/keeps_dead_bigdragon_charge_releases_busy

/datum/unit_test/om/keeps_dead_bigdragon_charge_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/bigdragon/D = allocate(/mob/living/simple_mob/vore/bigdragon, T)
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	D.ai_busy_begin()
	TEST_ASSERT(D.ai_brain.is_busy(), "the windup claims the AI")
	after(D, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/bigdragon, chargeend), with = list(A), keeps_dead = TRUE)
	qdel(A)
	scheduler_advance(2)
	TEST_ASSERT(!D.ai_brain.is_busy(), "the dragon busy hold is released when its target is gone")

/datum/unit_test/om/keeps_dead_blackhole_leap_releases_busy

/datum/unit_test/om/keeps_dead_blackhole_leap_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/otie/syndicate/blackhole/M = allocate(/mob/living/simple_mob/vore/otie/syndicate/blackhole, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	TEST_ASSERT(M.ai_brain.is_busy(), "the windup claims the AI")
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/otie/syndicate/blackhole, doLeap), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released when the leap target is gone")

/datum/unit_test/om/keeps_dead_cryptdrake_leap_releases_busy

/datum/unit_test/om/keeps_dead_cryptdrake_leap_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/cryptdrake/M = allocate(/mob/living/simple_mob/vore/cryptdrake, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	TEST_ASSERT(M.ai_brain.is_busy(), "the windup claims the AI")
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/cryptdrake, do_special_attack_1), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released when the leap target is gone")

/datum/unit_test/om/keeps_dead_cryptdrake_landing_clears_leaping

/datum/unit_test/om/keeps_dead_cryptdrake_landing_clears_leaping/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/cryptdrake/M = allocate(/mob/living/simple_mob/vore/cryptdrake, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	M.set_status_flags(M.status_flags | LEAPING)
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/cryptdrake, do_special_attack_2), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!(M.status_flags & LEAPING), "the leaping pass-through flag is cleared after landing")
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released after landing")

/datum/unit_test/om/keeps_dead_gryphon_leap_releases_busy

/datum/unit_test/om/keeps_dead_gryphon_leap_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/gryphon/M = allocate(/mob/living/simple_mob/vore/gryphon, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	TEST_ASSERT(M.ai_brain.is_busy(), "the windup claims the AI")
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/gryphon, do_special_attack_1), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released when the leap target is gone")

/datum/unit_test/om/keeps_dead_scel_lunge_releases_busy

/datum/unit_test/om/keeps_dead_scel_lunge_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/scel/M = allocate(/mob/living/simple_mob/vore/scel, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	TEST_ASSERT(M.ai_brain.is_busy(), "the windup claims the AI")
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/scel, lunge_1), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released when the lunge target is gone")

/datum/unit_test/om/keeps_dead_scel_landing_clears_leaping

/datum/unit_test/om/keeps_dead_scel_landing_clears_leaping/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/scel/M = allocate(/mob/living/simple_mob/vore/scel, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	M.set_status_flags(M.status_flags | LEAPING)
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/scel, lunge_2), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!(M.status_flags & LEAPING), "the leaping pass-through flag is cleared after landing")
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released after landing")

/datum/unit_test/om/keeps_dead_bloodjaunt_arrival_releases_busy

/datum/unit_test/om/keeps_dead_bloodjaunt_arrival_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/M = allocate(/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt, T)
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	TEST_ASSERT(M.ai_brain.is_busy(), "the windup claims the AI")
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt, do_special_attack_1), with = list(A, null, T), keeps_dead = TRUE)
	qdel(A)
	scheduler_advance(2)
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released when the jaunt target is gone")

/datum/unit_test/om/keeps_dead_wraith_arrival_releases_busy

/datum/unit_test/om/keeps_dead_wraith_arrival_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/construct/wraith/M = allocate(/mob/living/simple_mob/construct/wraith, T)
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human, T)
	M.ai_busy_begin()
	TEST_ASSERT(M.ai_brain.is_busy(), "the windup claims the AI")
	after(M, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/construct/wraith, do_special_attack_1), with = list(A, null, T), keeps_dead = TRUE)
	qdel(A)
	scheduler_advance(2)
	TEST_ASSERT(!M.ai_brain.is_busy(), "the busy hold is released when the phase target is gone")

// keeps_dead cleanup tests, batch 3: each schedules the site's real handler with keeps_dead, deletes an argument and asserts the cleanup still ran.

/// A larva crawling toward a vent that vanished is put back out of the vent it entered.
/datum/unit_test/om/keeps_dead_grub_arrive_exits_vent

/datum/unit_test/om/keeps_dead_grub_arrive_exits_vent/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/machinery/atmospherics/unary/vent_pump/entry = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/obj/machinery/atmospherics/unary/vent_pump/end_vent = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/mob/living/simple_mob/animal/solargrub_larva/grub = allocate(/mob/living/simple_mob/animal/solargrub_larva, T)
	grub.forceMove(entry)
	after(grub, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/animal/solargrub_larva, ventcrawl_arrive), with = list(entry, end_vent, 3), keeps_dead = TRUE)
	qdel(end_vent)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(grub.loc, T, "the larva is not left inside the vent when its exit is gone")

/// A leaper whose target vanished mid-windup releases its AI busy hold.
/datum/unit_test/om/keeps_dead_leaper_leap_releases_busy

/datum/unit_test/om/keeps_dead_leaper_leap_releases_busy/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/simple_mob/vore/vore_hostile/leaper/leaper = allocate(/mob/living/simple_mob/vore/vore_hostile/leaper, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	leaper.ai_busy_begin()
	TEST_ASSERT(leaper.ai_brain?.is_busy(), "the leaper is busy before the leap lands")
	after(leaper, 1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/vore/vore_hostile/leaper, do_special_attack_1), with = list(L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(!leaper.ai_brain?.is_busy(), "the leaper is not left busy after its target is gone")

/// The resleeving computer stops sequencing even when the injector it made is gone.
/datum/unit_test/om/keeps_dead_resleeving_injector_clears_sequencing

/datum/unit_test/om/keeps_dead_resleeving_injector_clears_sequencing/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/machinery/computer/transhuman/resleeving/computer = allocate(/obj/machinery/computer/transhuman/resleeving, T)
	var/obj/item/dnainjector/I = allocate(/obj/item/dnainjector, computer)
	computer.gene_sequencing = TRUE
	after(computer, 1 SECONDS, TYPE_PROC_REF(/obj/machinery/computer/transhuman/resleeving, dispense_injector), with = list(I), keeps_dead = TRUE)
	qdel(I)
	scheduler_advance(2)
	TEST_ASSERT(!computer.gene_sequencing, "the computer is not stuck sequencing")

/// A jaunt whose animation vanished at resurface still frees the jaunter.
/datum/unit_test/om/keeps_dead_jaunt_resurface_frees_jaunter

/datum/unit_test/om/keeps_dead_jaunt_resurface_frees_jaunter/run_om(list/made)
	var/turf/T = test_floor()
	var/datum/spell/targeted/ethereal_jaunt/spell = allocate(/datum/spell/targeted/ethereal_jaunt)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/obj/effect/dummy/spell_jaunt/holder = allocate(/obj/effect/dummy/spell_jaunt, T)
	var/atom/movable/overlay/animation = allocate(/atom/movable/overlay, T)
	target.forceMove(holder)
	target.canmove = 0
	after(spell, 1 SECONDS, TYPE_PROC_REF(/datum/spell/targeted/ethereal_jaunt, jaunt_resurface), with = list(target, holder, animation), keeps_dead = TRUE)
	qdel(animation)
	scheduler_advance(2)
	TEST_ASSERT(target.loc != holder, "the jaunter is let out of the holder")
	TEST_ASSERT_EQUAL(target.canmove, 1, "the jaunter can move again")

/// A jaunt whose animation vanished at reform still frees the jaunter.
/datum/unit_test/om/keeps_dead_jaunt_reform_frees_jaunter

/datum/unit_test/om/keeps_dead_jaunt_reform_frees_jaunter/run_om(list/made)
	var/turf/T = test_floor()
	var/datum/spell/targeted/ethereal_jaunt/spell = allocate(/datum/spell/targeted/ethereal_jaunt)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/obj/effect/dummy/spell_jaunt/holder = allocate(/obj/effect/dummy/spell_jaunt, T)
	var/atom/movable/overlay/animation = allocate(/atom/movable/overlay, T)
	target.forceMove(holder)
	target.canmove = 0
	after(spell, 1 SECONDS, TYPE_PROC_REF(/datum/spell/targeted/ethereal_jaunt, jaunt_reform), with = list(target, holder, animation), keeps_dead = TRUE)
	qdel(animation)
	scheduler_advance(2)
	TEST_ASSERT(target.loc != holder, "the jaunter is let out of the holder")
	TEST_ASSERT_EQUAL(target.canmove, 1, "the jaunter can move again")

/// The final jaunt step frees the jaunter even if the animation vanished.
/datum/unit_test/om/keeps_dead_jaunt_finish_frees_jaunter

/datum/unit_test/om/keeps_dead_jaunt_finish_frees_jaunter/run_om(list/made)
	var/turf/T = test_floor()
	var/datum/spell/targeted/ethereal_jaunt/spell = allocate(/datum/spell/targeted/ethereal_jaunt)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/obj/effect/dummy/spell_jaunt/holder = allocate(/obj/effect/dummy/spell_jaunt, T)
	var/atom/movable/overlay/animation = allocate(/atom/movable/overlay, T)
	target.forceMove(holder)
	target.canmove = 0
	after(spell, 1 SECONDS, TYPE_PROC_REF(/datum/spell/targeted/ethereal_jaunt, jaunt_finish), with = list(target, holder, animation), keeps_dead = TRUE)
	qdel(animation)
	scheduler_advance(2)
	TEST_ASSERT(target.loc != holder, "the jaunter is let out of the holder")
	TEST_ASSERT_EQUAL(target.canmove, 1, "the jaunter can move again")

/// The shadekin phase-out restores the phased mob's state even when the shadekin datum was deleted meanwhile.
/datum/unit_test/om/keeps_dead_shadekin_phase_out_applies

/datum/unit_test/om/keeps_dead_shadekin_phase_out_applies/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/shadekin/SK = new
	H.alpha = 255
	after(H, 1 SECONDS, TYPE_PROC_REF(/mob/living, complete_phase_out), with = list(TRUE, SK), keeps_dead = TRUE)
	qdel(SK)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(H.alpha, 127, "the mob finishes phasing out")
