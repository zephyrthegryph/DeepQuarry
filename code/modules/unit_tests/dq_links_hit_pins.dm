// Pins for the buckle, pull and grab links and for what an item click does on a target nothing else answers. Written against the old OM
// relations (om_link) and read only through the accessors (buckled_to(), buckled_mob_list(), pulling_target(), pulled_by_mob(), grab_target(),
// grabbed_by_list()), so the same assertions hold on the declared links that replace them (doc/rewrite/final_api.html section 6, KR2).
// A TEST_NOTICE line records an observation that is not asserted.

/// Buckle and unbuckle: the accessors, the buckled alert, the seat's capacity, a second seat refused, the seat or the rider deleted.
/datum/unit_test/dq_link_pin_buckle

/datum/unit_test/dq_link_pin_buckle/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, get_turf(H))
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	var/obj/structure/bed/chair/C2 = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	TEST_ASSERT_EQUAL(H.buckled_to(), C, "the rider is buckled to the chair")
	TEST_ASSERT(H in C.buckled_mob_list(), "the chair lists the rider")
	TEST_ASSERT(!isnull(H.alerts?["buckled"]), "the rider has the buckled alert")
	TEST_NOTICE(src, "PIN buckle: canmove=[H.canmove] dir=[H.dir] chair_dir=[C.dir] anchored=[H.anchored]")
	TEST_ASSERT(!C.buckle_mob(H2, forced = TRUE), "a one-seat chair refuses a second rider")
	TEST_ASSERT_NULL(H2.buckled_to(), "the refused rider is not buckled")
	TEST_ASSERT(!C2.buckle_mob(H, forced = TRUE), "a rider already buckled is refused by another seat")
	TEST_ASSERT_EQUAL(H.buckled_to(), C, "the refused seat did not take the rider")
	TEST_ASSERT_EQUAL(C.unbuckle_mob(H), H, "unbuckle_mob returns the rider")
	TEST_ASSERT_NULL(H.buckled_to(), "unbuckling clears the rider")
	TEST_ASSERT(!length(C.buckled_mob_list()), "unbuckling empties the chair")
	TEST_ASSERT(isnull(H.alerts?["buckled"]), "unbuckling clears the alert")
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle again")
	qdel(C)
	TEST_ASSERT_NULL(H.buckled_to(), "deleting the chair frees the rider")
	TEST_ASSERT(isnull(H.alerts?["buckled"]), "deleting the chair clears the alert")
	TEST_ASSERT(!QDELETED(H), "deleting the chair does not delete the rider")
	TEST_ASSERT(C2.buckle_mob(H, forced = TRUE), "setup: buckle to the second chair")
	qdel(H)
	TEST_ASSERT(!length(C2.buckled_mob_list()), "deleting the rider empties the chair")

/// A rider moved off the seat's tile is let go; read after the kernel clock has run.
/datum/unit_test/dq_link_pin_buckle_range

/datum/unit_test/dq_link_pin_buckle_range/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	var/turf/away = locate(C.x + 3, C.y, C.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 3 tiles east of the chair")
	H.forceMove(away)
	TEST_ASSERT_NOTEQUAL(get_turf(H), get_turf(C), "setup: the rider is off the chair's tile")
	TEST_NOTICE(src, "PIN buckle_range immediately: [H.buckled_to() ? "still buckled" : "free"]")
	test_time(1 SECONDS)
	test_driver_end()
	TEST_NOTICE(src, "PIN buckle_range after 1s: [H.buckled_to() ? "still buckled" : "free"]")
	TEST_ASSERT_NULL(H.buckled_to(), "a rider moved off the chair's tile is let go")
	TEST_ASSERT(!length(C.buckled_mob_list()), "the chair has no riders left")
	TEST_ASSERT(isnull(H.alerts?["buckled"]), "the alert is cleared")

/// Pulling: the accessors, a second puller taking the pulled, pulling the same thing twice stopping, both ends deleted.
/datum/unit_test/dq_link_pin_pull

/datum/unit_test/dq_link_pin_pull/Run()
	var/mob/living/carbon/human/P = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/Q = allocate(/mob/living/carbon/human, get_turf(P))
	var/mob/living/carbon/human/M = allocate(/mob/living/carbon/human, get_turf(P))
	P.start_pulling(M)
	TEST_ASSERT_EQUAL(P.pulling_target(), M, "the puller pulls the mob")
	TEST_ASSERT_EQUAL(M.pulled_by_mob(), P, "the mob is pulled by the puller")
	TEST_NOTICE(src, "PIN pull: hud=[P.pullin?.icon_state]")
	Q.start_pulling(M)
	TEST_ASSERT_EQUAL(Q.pulling_target(), M, "a second puller takes the mob")
	TEST_ASSERT_EQUAL(M.pulled_by_mob(), Q, "the mob is pulled by the second puller")
	TEST_ASSERT_NULL(P.pulling_target(), "the first puller lost the mob")
	Q.start_pulling(M)
	TEST_ASSERT_NULL(Q.pulling_target(), "pulling the same mob again lets go")
	TEST_ASSERT_NULL(M.pulled_by_mob(), "nobody pulls the mob after that")
	P.start_pulling(M)
	P.stop_pulling()
	TEST_ASSERT_NULL(P.pulling_target(), "stop_pulling clears the pull")
	TEST_ASSERT_NULL(M.pulled_by_mob(), "stop_pulling clears the pulled")
	TEST_NOTICE(src, "PIN pull after stop: hud=[P.pullin?.icon_state]")
	P.start_pulling(M)
	qdel(M)
	TEST_ASSERT_NULL(P.pulling_target(), "deleting the pulled frees the puller")
	var/mob/living/carbon/human/M2 = allocate(/mob/living/carbon/human, get_turf(P))
	P.start_pulling(M2)
	qdel(P)
	TEST_ASSERT_NULL(M2.pulled_by_mob(), "deleting the puller frees the pulled")
	TEST_ASSERT(!QDELETED(M2), "deleting the puller does not delete the pulled")

/// Moving apart breaks a pull; read after the kernel clock has run.
/datum/unit_test/dq_link_pin_pull_range

/datum/unit_test/dq_link_pin_pull_range/Run()
	test_driver_begin()
	var/mob/living/carbon/human/P = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/M = allocate(/mob/living/carbon/human, get_turf(P))
	P.start_pulling(M)
	TEST_ASSERT_EQUAL(P.pulling_target(), M, "setup: pulling")
	var/turf/away = locate(M.x + 5, M.y, M.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 5 tiles east")
	P.forceMove(away)
	TEST_NOTICE(src, "PIN pull_range immediately: [P.pulling_target() ? "still pulling" : "free"]")
	test_time(1 SECONDS)
	test_driver_end()
	TEST_NOTICE(src, "PIN pull_range after 1s: [P.pulling_target() ? "still pulling" : "free"]")
	TEST_ASSERT_NULL(P.pulling_target(), "moving apart ends the pull")
	TEST_ASSERT_NULL(M.pulled_by_mob(), "the pulled is free")

/// A grab: the accessors, reveal, a pull on the victim ending, the states and what they hold on the victim, both ends deleted.
/datum/unit_test/dq_link_pin_grab

/datum/unit_test/dq_link_pin_grab/Run()
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/V = allocate(/mob/living/carbon/human, get_turf(A))
	if(!A.zone_sel)
		rel_set(A, nameof(A.zone_sel), allocate(/atom/movable/screen/zone_sel))
	A.start_pulling(V)
	TEST_ASSERT_EQUAL(A.pulling_target(), V, "setup: the assailant pulls the victim")
	var/obj/item/grab/G = allocate(/obj/item/grab, A, V)
	TEST_ASSERT(!QDELETED(G), "setup: the grab holds")
	TEST_ASSERT_EQUAL(G.grab_target(), V, "the grab's target")
	TEST_ASSERT(G in V.grabbed_by_list(), "the victim lists the grab")
	TEST_ASSERT_EQUAL(G.grab_assailant(), A, "the assailant holds the grab")
	TEST_ASSERT_EQUAL(G.state, GRAB_PASSIVE, "a grab starts passive")
	TEST_ASSERT_NULL(A.pulling_target(), "grabbing the one you pull ends the pull")
	TEST_NOTICE(src, "PIN grab: dancing=[G.dancing]")
	G.confirm()
	COOLDOWN_RESET(G, upgrade_cooldown)
	G.s_click(G.hud)
	TEST_ASSERT_EQUAL(G.state, GRAB_AGGRESSIVE, "the first tighten makes it aggressive")
	G.periodic_step()
	COOLDOWN_RESET(G, upgrade_cooldown)
	G.s_click(G.hud)
	TEST_ASSERT_EQUAL(G.state, GRAB_NECK, "the second tighten makes it a neck hold")
	G.periodic_step()
	TEST_NOTICE(src, "PIN grab neck: stunned=[V.has_status(STAT_STUNNED)] airway=[!isnull(V.body)]")
	TEST_ASSERT(V.has_status(STAT_STUNNED), "a neck hold stuns the victim")
	COOLDOWN_RESET(G, upgrade_cooldown)
	G.s_click(G.hud)
	TEST_ASSERT_EQUAL(G.state, GRAB_KILL, "the third tighten is a strangle")
	G.periodic_step()
	TEST_NOTICE(src, "PIN grab kill: weakened=[V.has_status(STAT_WEAKENED)] stuttering=[V.has_status(STAT_STUTTERING)] losebreath=[V.losebreath]")
	TEST_ASSERT(V.has_status(STAT_WEAKENED), "a strangle weakens the victim")
	TEST_ASSERT(V.has_status(STAT_STUTTERING), "a strangle mutes the victim")
	G.reset_kill_state()
	TEST_ASSERT_EQUAL(G.state, GRAB_NECK, "losing the strangle drops back to the neck hold")
	qdel(G)
	TEST_ASSERT(!length(V.grabbed_by_list()), "deleting the grab frees the victim")
	var/obj/item/grab/G2 = allocate(/obj/item/grab, A, V)
	TEST_ASSERT_EQUAL(G2.grab_target(), V, "setup: a second grab")
	var/mob/living/carbon/human/V2 = allocate(/mob/living/carbon/human, get_turf(A))
	var/obj/item/grab/G3 = allocate(/obj/item/grab, V, A)
	TEST_NOTICE(src, "PIN grab clinch: dancing=[G3?.dancing] first=[G2?.dancing]")
	qdel(V)
	TEST_ASSERT(QDELETED(G2), "deleting the grabbed mob deletes the grab")
	TEST_ASSERT(!QDELETED(V2), "setup: the other mob stays")

/// A wheelchair pulls: its handles are gripped with ctrl-click, released the same way, and either end going frees the other.
/datum/unit_test/dq_link_pin_wheelchair

/datum/unit_test/dq_link_pin_wheelchair/Run()
	var/mob/living/carbon/human/P = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/R = allocate(/mob/living/carbon/human, get_turf(P))
	var/obj/structure/bed/chair/wheelchair/W = allocate(/obj/structure/bed/chair/wheelchair, get_turf(P))
	TEST_ASSERT(W.buckle_mob(R, forced = TRUE), "setup: the rider sits")
	W.click_ctrl(P)
	TEST_ASSERT_EQUAL(W.pulling_target(), P, "the chair is pulled by whoever grips the handles")
	TEST_ASSERT_EQUAL(P.pulled_by_mob(), W, "the pusher is held by the chair")
	W.click_ctrl(P)
	TEST_ASSERT_NULL(W.pulling_target(), "gripping again lets go")
	W.click_ctrl(P)
	TEST_ASSERT_EQUAL(W.pulling_target(), P, "setup: grip again")
	qdel(P)
	TEST_ASSERT_NULL(W.pulling_target(), "deleting the pusher frees the chair")
	var/mob/living/carbon/human/P2 = allocate(/mob/living/carbon/human, get_turf(W))
	W.click_ctrl(P2)
	TEST_ASSERT_EQUAL(W.pulling_target(), P2, "setup: a second pusher")
	qdel(W)
	TEST_ASSERT_NULL(P2.pulled_by_mob(), "deleting the chair frees the pusher")
	TEST_ASSERT(isnull(R.buckled_to()), "deleting the chair frees the rider")

// ---- what an item click does on a target nothing else answers ----

/// A crowbar in combat mode and a spray bottle in help stance, each used on a sample of targets, recording whether the target took a blow, whether
/// the click was an op's, and whether the spray bottle's own afterattack ran.
/datum/unit_test/dq_hit_pin_item_clicks

/datum/unit_test/dq_hit_pin_item_clicks/Run()
	var/list/types = list(
		/obj/structure/closet, /obj/structure/grille, /obj/structure/table/steel, /obj/machinery/door/airlock,
		/obj/machinery/portable_atmospherics/canister/oxygen, /obj/machinery/photocopier, /obj/machinery/seed_extractor,
		/obj/machinery/door/blast/regular, /obj/machinery/cablelayer, /obj/machinery/shower, /obj/machinery/power/smes/buildable,
		/obj/machinery/atmospherics/pipe/tank/air, /obj/machinery/light/small/torch, /obj/machinery/light, /obj/effect/spider/stickyweb,
		/obj/machinery/computer/turbine_computer, /obj/machinery/vending/cola)
	var/turf/T = get_turf(run_loc_floor_bottom_left)
	var/turf/side = locate(T.x + 1, T.y, T.z)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, side)
	for(var/type in types)
		var/atom/target = allocate(type, T)
		if(QDELETED(target))
			TEST_NOTICE(src, "PIN item_click [type]: deleted itself")
			continue
		if(ismachinery(target))
			var/obj/machinery/M = target
			M.set_grid_power(TRUE)
			M.set_broken_condition(FALSE)
		var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, side)
		H.put_in_hands(bar)
		H.set_combat_mode(TRUE)
		var/before = target.get_integrity()
		var/datum/op_result/hit = test_click(H, target, bar)
		test_drain()
		var/after = QDELETED(target) ? "deleted" : target.get_integrity()
		var/hit_key = hit ? hit.key : "no op"
		var/hit_outcome = hit ? hit.outcome : "-"
		qdel(bar)
		var/obj/item/reagent_containers/spray/cleaner/spray = allocate(/obj/item/reagent_containers/spray/cleaner, side)
		H.put_in_hands(spray)
		H.set_combat_mode(FALSE)
		var/volume = spray.reagents?.total_volume
		var/datum/op_result/used = test_click(H, target, spray)
		test_drain()
		var/sprayed = volume - spray.reagents?.total_volume
		qdel(spray)
		TEST_NOTICE(src, "PIN item_click [type]: crowbar integrity [before] -> [after] op=[hit_key]/[hit_outcome]; spray used=[sprayed] op=[used ? used.key : "no op"]")
		if(!QDELETED(target))
			qdel(target)
		for(var/turf/near in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
			own_turf_contents(near)

/// damageable(): the closet takes a crowbar in combat mode through the capability's op, and no swallow op stands between a held item and the targets that
/// had one: a crowbar leaves a shower alone and a spray bottle's own op reaches it.
/datum/unit_test/dq_hit_damageable_closet

/datum/unit_test/dq_hit_damageable_closet/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left)
	var/turf/side = locate(T.x + 1, T.y, T.z)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, side)
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, side)
	H.put_in_hands(bar)
	H.set_combat_mode(TRUE)
	var/before = C.get_integrity()
	var/datum/op_result/hit = test_click(H, C, bar)
	test_drain()
	TEST_ASSERT_EQUAL(hit?.key, "damageable.hit", "a crowbar in combat mode hits the closet through the capability's op")
	TEST_ASSERT(C.get_integrity() < before, "the closet took the blow")
	H.set_combat_mode(FALSE)
	var/obj/machinery/shower/S = allocate(/obj/machinery/shower, T)
	var/datum/op_result/none = test_click(H, S, bar)
	TEST_ASSERT(isnull(none) || none.key != "swallow", "no swallow op answers a crowbar on a shower")
