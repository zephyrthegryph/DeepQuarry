/// Counts the real human's redraws (its whole look is one draw).
/mob/living/carbon/human/interim_holo_sword_holder
	/// Draws per holder (REF -> count). A plain static list: a tracked var written by the draw it is read in marks itself changed during its own refresh.
	var/static/list/draw_log = list()

/// The holder's look is one draw: a redraw counts for both hands.
/mob/living/carbon/human/interim_holo_sword_holder/draw(datum/look/look)
	draw_log[REF(src)] = (draw_log[REF(src)] || 0) + 1
	..()

/mob/living/carbon/human/interim_holo_sword_holder/proc/redraws()
	return draw_log[REF(src)] || 0

/mob/living/carbon/human/interim_holo_sword_holder/proc/clear_redraws()
	draw_log -= REF(src)

/// A synthetic native click supplies ambient usr while observing the real appearance output.
/obj/item/holo/esword/interim_holder_appearance
	var/list/observed_overlays

/// Runs the queued draws (the presentation lane) and records the overlays the sword shows now.
/obj/item/holo/esword/interim_holder_appearance/proc/observe_look()
	refresh_flush()
	observed_overlays = overlays.Copy()

/datum/unit_test/interim_holo_sword_holder_appearance/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_holo_sword_holder/holder = allocate(/mob/living/carbon/human/interim_holo_sword_holder, T)
	var/mob/living/carbon/human/interim_holo_sword_holder/bystander = allocate(/mob/living/carbon/human/interim_holo_sword_holder, T)
	var/obj/item/holo/esword/interim_holder_appearance/sword = allocate(/obj/item/holo/esword/interim_holder_appearance, T)
	TEST_ASSERT(holder.put_in_active_hand(sword), "the actual holographic sword occupies its holder's hand")
	sword.observe_look()
	var/inherited_count = length(sword.observed_overlays)
	var/inactive_blades = 0
	for(var/mutable_appearance/entry as anything in sword.observed_overlays)
		if(entry && entry.icon_state == "esword_blade")
			inactive_blades++
	TEST_ASSERT_EQUAL(inactive_blades, 0, "the actual initial inactive appearance contains no blade")
	holder.clear_redraws()
	holder.clear_redraws()
	bystander.clear_redraws()
	bystander.clear_redraws()
	test_op_handler(sword, "interaction_self", holder, sword)
	TEST_ASSERT(sword.active, "the actual sword interaction extends its blade")
	TEST_ASSERT_EQUAL(combat_of(sword).force, 30, "actual holo activation applies its configured active force")
	TEST_ASSERT_EQUAL(sword.w_class, ITEMSIZE_LARGE, "actual holo activation enlarges its real blade")
	TEST_ASSERT_EQUAL(sword.item_state, "esword_blade", "the actual extended blade has its held item state")
	sword.observe_look()
	TEST_ASSERT(holder.redraws() + holder.redraws() > 0, "the blade change redraws the hand the sword is held in")
	TEST_ASSERT_EQUAL(bystander.redraws(), 0, "appearance generation does not redraw the ambient caller's left hand")
	TEST_ASSERT_EQUAL(bystander.redraws(), 0, "appearance generation does not redraw the ambient caller's right hand")
	TEST_ASSERT_EQUAL(length(sword.observed_overlays), inherited_count + 1, "the real extended sword adds exactly one overlay to its inherited appearance")
	var/active_blades = 0
	for(var/mutable_appearance/entry as anything in sword.observed_overlays)
		if(entry && entry.icon_state == "esword_blade")
			active_blades++
	TEST_ASSERT_EQUAL(active_blades, 1, "the actual extended appearance contains exactly one blade overlay")
	TEST_ASSERT_EQUAL(holder.get_active_hand(), sword, "appearance generation preserves actual held ownership")
	test_op_handler(sword, "interaction_self", holder, sword)
	TEST_ASSERT(!sword.active, "the actual sword interaction retracts its blade")
	TEST_ASSERT_EQUAL(combat_of(sword).force, 3, "actual holo retraction restores its force")
	TEST_ASSERT_EQUAL(sword.w_class, ITEMSIZE_SMALL, "actual holo retraction restores its concealable size")
	TEST_ASSERT_EQUAL(sword.item_state, "esword", "the actual retracted sword restores its held item state")
	sword.observe_look()
	TEST_ASSERT_EQUAL(length(sword.observed_overlays), inherited_count, "retracting the actual blade restores its inherited appearance count")
	var/retracted_blades = 0
	for(var/mutable_appearance/entry as anything in sword.observed_overlays)
		if(entry && entry.icon_state == "esword_blade")
			retracted_blades++
	TEST_ASSERT_EQUAL(retracted_blades, 0, "the actual retracted appearance contains no blade overlay")
	TEST_ASSERT(holder.unEquip(sword), "the actual holder releases the sword to the floor")
	refresh_flush() // the release's own redraw runs before the counters are zeroed
	holder.clear_redraws()
	holder.clear_redraws()
	sword.observe_look()
	TEST_ASSERT_EQUAL(holder.redraws(), 0, "an unheld holographic sword does not redraw its former holder")
	TEST_ASSERT_EQUAL(holder.redraws(), 0, "an unheld holographic sword leaves its former holder's right hand untouched")
	TEST_ASSERT_EQUAL(bystander.redraws(), 0, "an unheld holographic sword never redraws an unrelated ambient caller")
	TEST_ASSERT_EQUAL(bystander.redraws(), 0, "an unheld holographic sword leaves the unrelated caller's right hand untouched")
