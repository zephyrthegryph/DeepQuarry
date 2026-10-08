/// Observes only helper entry, then executes the actual coordinate-selection implementation.
/atom/movable/screen/zone_sel/interim_actor_probe
	var/last_actor_ref

/atom/movable/screen/zone_sel/interim_actor_probe/click_with_actor(mob/user, location, control, params)
	last_actor_ref = user ? REF(user) : null
	return ..()

/datum/unit_test/om/interim_target_zone_hud_actor/proc/targeting_raises(datum/entity)
	var/count = 0
	for(var/list/entry as anything in sched.test_raises)
		if(entry[1] == entity && (entry[2] & CHANGE_MOB_TARGETING))
			count++
	return count

/// Real coordinates change the actual selected zone, appearance and exact actor notification.
/datum/unit_test/om/interim_target_zone_hud_actor/run_om(list/made)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/observer/dead/observer = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/atom/movable/screen/zone_sel/interim_actor_probe/button = allocate(/atom/movable/screen/zone_sel/interim_actor_probe)
	rel_set(actor, nameof(actor.zone_sel), button)
	TEST_ASSERT_EQUAL(actor.zone_sel, button, "the actual target selector belongs to the initiating mob")
	TEST_ASSERT_EQUAL(button.selecting, BP_TORSO, "the actual target selector starts on the torso")
	var/datum/om/rec/actor_rec = om_rec_of(actor)
	var/datum/om/rec/bystander_rec = om_rec_of(bystander)
	TEST_ASSERT_EQUAL(actor_rec.sched, sched, "the real actor uses the actual test scheduler notification instrumentation")
	TEST_ASSERT_EQUAL(bystander_rec.sched, sched, "the real bystander uses the same actual notification instrumentation")
	set_var(actor, nameof(actor.om_listen), actor.om_listen | CHANGE_MOB_TARGETING)
	set_var(bystander, nameof(bystander.om_listen), bystander.om_listen | CHANGE_MOB_TARGETING)
	sched.test_raises = list()
	// The existing native synthetic helper supplies empty params: it proves actor capture only.
	km_synthetic_click(actor, button)
	TEST_ASSERT_EQUAL(button.last_actor_ref, REF(actor), "the actual native boundary captures the initiating actor")
	TEST_ASSERT_EQUAL(button.selecting, BP_TORSO, "missing native coordinates preserve the actual zone")
	TEST_ASSERT_EQUAL(targeting_raises(actor), 0, "missing coordinates emit no targeting change")
	TEST_ASSERT_NULL(button.click_with_actor(actor, null, null, "icon-x=16;icon-y=26"), "actual valid-coordinate selection preserves the original implicit null return")
	TEST_ASSERT_EQUAL(button.selecting, O_EYES, "the actual eye coordinates select the eye zone")
	TEST_ASSERT_EQUAL(targeting_raises(actor), 1, "the real selection notifies the exact initiating actor once")
	TEST_ASSERT_EQUAL(targeting_raises(bystander), 0, "the actual first selection does not notify the unrelated mob")
	refresh_flush()
	var/list/actual_overlays = dq_overlay_states(button)
	TEST_ASSERT_EQUAL(length(actual_overlays), 1, "the actual selector appearance contains its single zone overlay")
	TEST_ASSERT_EQUAL(actual_overlays[1], "[O_EYES]", "the selected zone redraws by itself and depicts eyes")
	button.click_with_actor(actor, null, null, "icon-x=16;icon-y=26")
	TEST_ASSERT_EQUAL(targeting_raises(actor), 1, "the same actual zone does not emit a redundant notification")
	button.click_with_actor(bystander, null, null, "icon-x=18;icon-y=2")
	TEST_ASSERT_EQUAL(button.last_actor_ref, REF(bystander), "the helper receives its explicit second actor")
	TEST_ASSERT_EQUAL(button.selecting, BP_L_FOOT, "the actual foot coordinates select the left foot")
	TEST_ASSERT_EQUAL(targeting_raises(actor), 1, "the second actual selection does not notify the first actor again")
	TEST_ASSERT_EQUAL(targeting_raises(bystander), 1, "the second actual selection notifies precisely its explicit actor")
	button.click_with_actor(observer, null, null, "icon-x=16;icon-y=18")
	TEST_ASSERT_EQUAL(button.selecting, BP_L_FOOT, "an actual observer is refused even with valid torso coordinates")
	TEST_ASSERT_EQUAL(button.click_with_actor(actor, null, null, "icon-x=1;icon-y=1"), 1, "invalid actual coordinates preserve the handled return")
	TEST_ASSERT_EQUAL(button.selecting, BP_L_FOOT, "invalid coordinates preserve the real selected zone")
	TEST_ASSERT_EQUAL(targeting_raises(actor), 1, "observer/invalid selections issue no extra actor notification")
	TEST_ASSERT_EQUAL(targeting_raises(bystander), 1, "observer/invalid selections issue no extra bystander notification")
	button.click_with_actor(actor, null, null, "icon-x=16;icon-y=18")
	TEST_ASSERT_EQUAL(button.selecting, BP_TORSO, "actual torso coordinates restore the starting zone")
	TEST_ASSERT_EQUAL(targeting_raises(actor), 2, "the real return to torso notifies the actor exactly once more")
	refresh_flush()
	actual_overlays = dq_overlay_states(button)
	TEST_ASSERT_EQUAL(length(actual_overlays), 1, "the actual restored appearance retains exactly one selected-zone overlay")
	TEST_ASSERT_EQUAL(actual_overlays[1], "[BP_TORSO]", "the restored zone is drawn: the torso")
	sched.test_raises = null
