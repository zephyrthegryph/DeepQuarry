// J6, the rest of the kept keeps_dead sites (doc/rewrite/framework_gaps.md "J6 audit"): each test schedules the site's real handler with keeps_dead,
// deletes an argument before it fires and asserts the cleanup still happened.

/// The malf AI's unlock timer clears its hacking flag even when the cyborg was deleted meanwhile.
/datum/unit_test/om/keeps_dead_malf_unlock_clears_hacking

/datum/unit_test/om/keeps_dead_malf_unlock_clears_hacking/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	AI.hacking = 1
	after(AI, 1 SECONDS, GLOBAL_PROC_REF(malf_unlock_cyborg_done), with = list(AI, R), keeps_dead = TRUE)
	qdel(R)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(AI.hacking, 0, "the AI is not left hacking a cyborg that is gone")

/// An apportionment whose target vanished still uses up the spell.
/datum/unit_test/om/keeps_dead_apportation_consumes_spell

/datum/unit_test/om/keeps_dead_apportation_consumes_spell/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/L = allocate(/mob/living/carbon/human, T)
	var/obj/item/spell/apportation/spell = allocate(/obj/item/spell/apportation, T)
	after(spell, 1 SECONDS, TYPE_PROC_REF(/obj/item/spell/apportation, finish_apportation_grab), with = list(user, L), keeps_dead = TRUE)
	qdel(L)
	scheduler_advance(2)
	TEST_ASSERT(QDELETED(spell) || spell.loc != T, "the spell is used up when its target is gone")

/// A spiderling crawling through a vent that vanished comes back out of the entry vent.
/datum/unit_test/om/keeps_dead_spiderling_vent_midway_returns

/datum/unit_test/om/keeps_dead_spiderling_vent_midway_returns/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/machinery/atmospherics/unary/vent_pump/entry = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/obj/machinery/atmospherics/unary/vent_pump/exit_vent = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/obj/effect/spider/spiderling/S = allocate(/obj/effect/spider/spiderling, T)
	after(S, 1 SECONDS, TYPE_PROC_REF(/obj/effect/spider/spiderling, vent_crawl_midway), with = list(entry, exit_vent, 1), keeps_dead = TRUE)
	qdel(exit_vent)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(S.loc, entry, "the spiderling is put back in the vent it entered")

/datum/unit_test/om/keeps_dead_spiderling_vent_exit_returns

/datum/unit_test/om/keeps_dead_spiderling_vent_exit_returns/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/machinery/atmospherics/unary/vent_pump/entry = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/obj/machinery/atmospherics/unary/vent_pump/exit_vent = allocate(/obj/machinery/atmospherics/unary/vent_pump, T)
	var/obj/effect/spider/spiderling/S = allocate(/obj/effect/spider/spiderling, T)
	after(S, 1 SECONDS, TYPE_PROC_REF(/obj/effect/spider/spiderling, vent_crawl_exit), with = list(entry, exit_vent), keeps_dead = TRUE)
	qdel(exit_vent)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(S.loc, entry, "the spiderling is put back in the vent it entered")

/// A one-shot spawner is spent even when the body it made is gone.
/datum/unit_test/om/keeps_dead_apprentice_spawner_is_spent

/datum/unit_test/om/keeps_dead_apprentice_spawner_is_spent/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/antag_spawner/technomancer_apprentice/spawner = allocate(/obj/item/antag_spawner/technomancer_apprentice, T)
	after(spawner, 1 SECONDS, TYPE_PROC_REF(/obj/item/antag_spawner/technomancer_apprentice, finish_technomancer_spawn), with = list(H), keeps_dead = TRUE)
	qdel(H)
	scheduler_advance(2)
	TEST_ASSERT(spawner.used, "the spawner is marked used")

/datum/unit_test/om/keeps_dead_drone_teleporter_is_spent

/datum/unit_test/om/keeps_dead_drone_teleporter_is_spent/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/obj/item/antag_spawner/syndicate_drone/spawner = allocate(/obj/item/antag_spawner/syndicate_drone, T)
	after(spawner, 1 SECONDS, TYPE_PROC_REF(/obj/item/antag_spawner/syndicate_drone, finish_drone_spawn), with = list(R), keeps_dead = TRUE)
	qdel(R)
	scheduler_advance(2)
	TEST_ASSERT(QDELETED(spawner), "the teleporter is used up")

/// A card wiping an AI that was deleted stops flushing.
/datum/unit_test/om/keeps_dead_aicard_wipe_stops

/datum/unit_test/om/keeps_dead_aicard_wipe_stops/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	var/obj/item/aicard/card = allocate(/obj/item/aicard, T)
	card.flush = TRUE
	after(card, 1 SECONDS, TYPE_PROC_REF(/obj/item/aicard, wipe_ai_tick), with = list(AI, 0), keeps_dead = TRUE)
	qdel(AI)
	scheduler_advance(2)
	TEST_ASSERT(!card.flush, "the card is not left mid-wipe")

/// The ghost call's last stage takes the black screen off even when the caller is gone.
/datum/unit_test/om/keeps_dead_ghost_dial_removes_blackness

/datum/unit_test/om/keeps_dead_ghost_dial_removes_blackness/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/communicator/comm = allocate(/obj/item/communicator, T)
	var/mob/living/voice/voice = allocate(/mob/living/voice, T)
	var/atom/movable/screen/blackness = allocate(/atom/movable/screen)
	after(comm, 1 SECONDS, TYPE_PROC_REF(/obj/item/communicator, dial_ghost), with = list(user, voice, blackness, "someone", 1), keeps_dead = TRUE)
	qdel(user)
	scheduler_advance(20)
	TEST_ASSERT(QDELETED(blackness), "the black screen is spent when the dial-up finishes")

/// A toy fight whose opponent toy was deleted ends and resets the survivor.
/datum/unit_test/om/keeps_dead_toy_brawl_ends

/datum/unit_test/om/keeps_dead_toy_brawl_ends/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/item/toy/mecha/toy = allocate(/obj/item/toy/mecha, T)
	var/obj/item/toy/mecha/foe = allocate(/obj/item/toy/mecha, T)
	toy.in_combat = TRUE
	toy.combat_health = 1
	after(toy, 1 SECONDS, TYPE_PROC_REF(/obj/item/toy/mecha, brawl_round), with = list(foe, null, null, 0), keeps_dead = TRUE)
	qdel(foe)
	scheduler_advance(2)
	TEST_ASSERT(!toy.in_combat, "the toy leaves combat")
	TEST_ASSERT_EQUAL(toy.combat_health, toy.max_combat_health, "and is mended")

/datum/unit_test/om/keeps_dead_toy_brawl_exchange_ends

/datum/unit_test/om/keeps_dead_toy_brawl_exchange_ends/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/item/toy/mecha/toy = allocate(/obj/item/toy/mecha, T)
	var/obj/item/toy/mecha/foe = allocate(/obj/item/toy/mecha, T)
	toy.in_combat = TRUE
	toy.combat_health = 1
	after(toy, 1 SECONDS, TYPE_PROC_REF(/obj/item/toy/mecha, brawl_exchange), with = list(foe, null, null, 0), keeps_dead = TRUE)
	qdel(foe)
	scheduler_advance(2)
	TEST_ASSERT(!toy.in_combat, "the toy leaves combat")

/// A chair pushed by an extinguisher stops being propelled even when its rider was deleted mid-way.
/datum/unit_test/om/keeps_dead_extinguisher_chair_stops

/datum/unit_test/om/keeps_dead_extinguisher_chair_stops/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/bed/chair/chair = allocate(/obj/structure/bed/chair, T)
	var/obj/item/extinguisher/ext = allocate(/obj/item/extinguisher, T)
	chair.anchored = FALSE
	chair.propelled = 5
	ext.propel_object(chair, user, NORTH)
	qdel(user)
	scheduler_advance(30)
	TEST_ASSERT_EQUAL(chair.propelled, 0, "the chair's propulsion runs out")

/// A shorted secure case stops sparking and opens when the one who shorted it is gone.
/datum/unit_test/om/keeps_dead_secure_case_finishes_shorting

/datum/unit_test/om/keeps_dead_secure_case_finishes_shorting/run_om(list/made)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/secure/S = allocate(/obj/item/storage/secure, T)
	S.short_lock(user)
	qdel(user)
	scheduler_advance(2)
	TEST_ASSERT(!S.sparking, "it stops sparking")
	TEST_ASSERT(!S.locked, "and is unlocked")

/// A station that sent a pod which was then deleted stops being busy.
/datum/unit_test/om/keeps_dead_tube_station_not_stuck_moving

/datum/unit_test/om/keeps_dead_tube_station_not_stuck_moving/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/structure/transit_tube/station/station = allocate(/obj/structure/transit_tube/station, T)
	var/obj/structure/transit_tube_pod/pod = allocate(/obj/structure/transit_tube_pod, T)
	station.pod_moving = 1
	after(station, 1 SECONDS, TYPE_PROC_REF(/obj/structure/transit_tube/station, launch_go), with = list(pod), keeps_dead = TRUE)
	qdel(pod)
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(station.pod_moving, 0, "the station can launch again")

/// The pod prop finishes changing state even if its door overlay is gone.
/datum/unit_test/om/keeps_dead_nt_pod_finishes_state_change

/datum/unit_test/om/keeps_dead_nt_pod_finishes_state_change/run_om(list/made)
	var/turf/T = test_floor()
	var/obj/structure/prop/machine/nt_pod/pod = allocate(/obj/structure/prop/machine/nt_pod, T)
	var/obj/effect/overlay/vis/door = allocate(/obj/effect/overlay/vis)
	pod.changing_state = TRUE
	after(pod, 1 SECONDS, TYPE_PROC_REF(/obj/structure/prop/machine/nt_pod, delayed_flick), with = list(door, "nothing", "nt_pod_opening", 1 SECONDS), keeps_dead = TRUE)
	qdel(door)
	scheduler_advance(5)
	TEST_ASSERT(!pod.changing_state, "the pod is not left stuck changing state")
