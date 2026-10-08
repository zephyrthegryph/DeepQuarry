/// Counts observe real human inventory redraws and still chain their real implementations.
/mob/living/carbon/human/interim_energy_shield_holder
	var/left_redraws = 0
	var/right_redraws = 0

/mob/living/carbon/human/interim_energy_shield_holder/update_inv_l_hand()
	left_redraws++
	return ..()

/mob/living/carbon/human/interim_energy_shield_holder/update_inv_r_hand()
	right_redraws++
	return ..()

/// Draws the real look and applies it, observing the overlays it lays.
/obj/item/shield/energy/interim_holder_appearance
	var/list/observed_overlays

/obj/item/shield/energy/interim_holder_appearance/proc/observe()
	var/datum/look/look = new
	draw(look)
	observed_overlays = look.overlays ? look.overlays.Copy() : list()
	look.apply_to(src)

/datum/unit_test/interim_energy_shield_holder_appearance/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_energy_shield_holder/holder = allocate(/mob/living/carbon/human/interim_energy_shield_holder, T)
	var/mob/living/carbon/human/interim_energy_shield_holder/bystander = allocate(/mob/living/carbon/human/interim_energy_shield_holder, T)
	var/obj/item/shield/energy/interim_holder_appearance/shield = allocate(/obj/item/shield/energy/interim_holder_appearance, T)
	TEST_ASSERT(holder.put_in_active_hand(shield), "the actual energy shield occupies its holder's hand")
	shield.observe()
	var/inherited_count = length(shield.observed_overlays)
	var/inactive_blades = 0
	for(var/mutable_appearance/entry as anything in shield.observed_overlays)
		if(entry && entry.icon_state == "eshield_blade")
			inactive_blades++
	TEST_ASSERT_EQUAL(inactive_blades, 0, "the actual initial inactive appearance contains no blade")
	holder.left_redraws = 0
	holder.right_redraws = 0
	bystander.left_redraws = 0
	bystander.right_redraws = 0
	perform_op(holder, shield, "toggle", null, ORIGIN_SYSTEM)
	shield.observe()
	TEST_ASSERT(shield.active, "the actual shield interaction extends its blade")
	TEST_ASSERT_EQUAL(shield.item_state, "eshield_blade", "the actual extended blade has its held item state")
	TEST_ASSERT_EQUAL(shield.light_range, shield.lrange, "the real active shield enables its configured illumination")
	TEST_ASSERT_EQUAL(shield.light_power, shield.lpower, "the real active shield uses its configured light power")
	shield.observe()
	TEST_ASSERT(holder.left_redraws > 0 && holder.right_redraws > 0, "real appearance generation redraws the actual holder's hands")
	TEST_ASSERT_EQUAL(bystander.left_redraws, 0, "appearance generation does not redraw the ambient caller's left hand")
	TEST_ASSERT_EQUAL(bystander.right_redraws, 0, "appearance generation does not redraw the ambient caller's right hand")
	TEST_ASSERT_EQUAL(length(shield.observed_overlays), inherited_count + 1, "the real extended shield adds exactly one overlay to its inherited appearance")
	var/active_blades = 0
	for(var/mutable_appearance/entry as anything in shield.observed_overlays)
		if(entry && entry.icon_state == "eshield_blade")
			active_blades++
	TEST_ASSERT_EQUAL(active_blades, 1, "the actual extended appearance contains exactly one blade overlay")
	TEST_ASSERT_EQUAL(holder.get_active_hand(), shield, "appearance generation preserves actual held ownership")
	perform_op(holder, shield, "toggle", null, ORIGIN_SYSTEM)
	shield.observe()
	TEST_ASSERT(!shield.active, "the actual shield interaction retracts its blade")
	TEST_ASSERT_EQUAL(shield.light_range, 0, "the real retracted shield extinguishes its illumination")
	TEST_ASSERT_EQUAL(shield.item_state, "eshield", "the actual retracted shield restores its held item state")
	shield.observe()
	TEST_ASSERT_EQUAL(length(shield.observed_overlays), inherited_count, "retracting the actual blade restores its inherited appearance count")
	var/retracted_blades = 0
	for(var/mutable_appearance/entry as anything in shield.observed_overlays)
		if(entry && entry.icon_state == "eshield_blade")
			retracted_blades++
	TEST_ASSERT_EQUAL(retracted_blades, 0, "the actual retracted appearance contains no blade overlay")
	TEST_ASSERT(holder.unEquip(shield), "the actual holder releases the shield to the floor")
	holder.left_redraws = 0
	holder.right_redraws = 0
	shield.observe()
	TEST_ASSERT_EQUAL(holder.left_redraws, 0, "an unheld energy shield does not redraw its former holder")
	TEST_ASSERT_EQUAL(holder.right_redraws, 0, "an unheld energy shield leaves its former holder's right hand untouched")
	TEST_ASSERT_EQUAL(bystander.left_redraws, 0, "an unheld energy shield never redraws an unrelated ambient caller")
	TEST_ASSERT_EQUAL(bystander.right_redraws, 0, "an unheld energy shield leaves the unrelated caller's right hand untouched")
