// The cost of a join, phase by phase, first join of the round against later ones (JOIN_TIMING's phases).
// Logged as JOIN_COST lines; the assertions are the per-frame budgets a join must stay under.

/// Milliseconds since `started` (a TICK_USAGE_REAL stamp).
/proc/dq_join_ms_since(started)
	return TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)

/datum/unit_test/dq_join_phase_cost

/datum/unit_test/dq_join_phase_cost/Run()
	var/list/join = SSjob.late_spawn(null, JOB_INTERN)
	var/turf/T = join?["turf"]
	TEST_ASSERT(isturf(T), "the job system gives a late joiner an arrivals turf")
	var/datum/preferences/dq_test_stub/prefs = dq_palette_test_prefs()
	for(var/round_number in 1 to 3)
		var/stamp = TICK_USAGE_REAL
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
		var/body_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		prefs.copy_to(H, icon_updates = TRUE)
		var/prefs_ms = dq_join_ms_since(stamp)
		// What create_character() does to the body after the preferences are on it, step by step.
		stamp = TICK_USAGE_REAL
		H.dna.ready_dna(H)
		var/ready_dna_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		H.sync_dna_traits(TRUE)
		var/traits_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		H.sync_organ_dna()
		var/organ_dna_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		H.sync_addictions()
		var/addictions_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		H.initialize_vessel()
		var/vessel_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		H.force_update_limbs()
		H.update_transform()
		var/limbs_ms = dq_join_ms_since(stamp)
		log_test("JOIN_COST: join [round_number] body tail: ready_dna [round(ready_dna_ms, 0.1)] ms, sync_dna_traits [round(traits_ms, 0.1)] ms, sync_organ_dna [round(organ_dna_ms, 0.1)] ms, sync_addictions [round(addictions_ms, 0.1)] ms, initialize_vessel [round(vessel_ms, 0.1)] ms, force_update_limbs [round(limbs_ms, 0.1)] ms")
		// copy_to's sanitize pass once rewrote every list pref, and each write redrew the preview: about 700 ms a join for ~45 ms of work.
		TEST_ASSERT(prefs_ms < 250, "join [round_number]: applying the preferences took [round(prefs_ms, 0.1)] ms: a clean preference is not rewritten (and its preview redrawn) on spawn")
		H.mind_initialize()
		defer_cleanup(null, GLOBAL_PROC_REF(dq_gameplay_forget_mind), H.mind)
		stamp = TICK_USAGE_REAL
		SSjob.equip_rank(H, JOB_INTERN, TRUE, FALSE)
		var/equip_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		refresh_flush()
		var/flush_ms = dq_join_ms_since(stamp)
		stamp = TICK_USAGE_REAL
		latejoin_register(H, JOB_INTERN, "has arrived", "Common", H.z)
		var/register_ms = dq_join_ms_since(stamp)
		log_test("JOIN_COST: join [round_number]: body [round(body_ms, 0.1)] ms, prefs [round(prefs_ms, 0.1)] ms, equip [round(equip_ms, 0.1)] ms, first draws [round(flush_ms, 0.1)] ms, register [round(register_ms, 0.1)] ms")
	cancel_after(prefs, "preferences_preview_full")
	fdel(prefs.path)
	qdel(prefs, TRUE)

/// icon2base64 of a one-frame body-sized icon: the cost of one photo or preview frame, and its size.
/datum/unit_test/dq_icon2base64_cost

/datum/unit_test/dq_icon2base64_cost/Run()
	var/icon/frame = icon('icons/effects/effects.dmi', "nothing")
	var/total_ms = 0
	var/bytes = 0
	for(var/i in 1 to 20)
		var/stamp = TICK_USAGE_REAL
		var/encoded = icon2base64(frame)
		total_ms += dq_join_ms_since(stamp)
		bytes = length(encoded)
	log_test("JOIN_COST: icon2base64 of one [frame.Width()]x[frame.Height()] frame: [round(total_ms / 20, 0.01)] ms each over 20, [bytes] base64 bytes")
	TEST_ASSERT(bytes > 0, "the icon encodes")
	// Deleting and recreating a scratch savefile on every call cost about 19 ms each once the ten slots wrapped round.
	TEST_ASSERT(total_ms / 20 < 5, "icon2base64 takes [round(total_ms / 20, 0.1)] ms a frame: its scratch savefile is reused, not rebuilt per call")
