// The human's worn look, tail layering and HUD meters (playtest regressions of 3bd7a6f329).

/// Putting a uniform on draws it on the mob; taking it off removes it. The slot's redraw must reach the human's own
/// update_inv_w_uniform(), not the empty /mob one a proc path bound through call() would run.
/datum/unit_test/dq_mob_visuals_equip_redraws_the_human

/datum/unit_test/dq_mob_visuals_equip_redraws_the_human/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	refresh_flush()
	TEST_ASSERT_NULL(H.overlays_standing[UNIFORM_LAYER], "a bare human draws no uniform")
	var/obj/item/clothing/under/color/grey/uniform = allocate(/obj/item/clothing/under/color/grey, H.loc)
	TEST_ASSERT(H.equip_to_slot_if_possible(uniform, SLOT_ID_UNIFORM, disable_warning = TRUE), "the uniform goes on")
	refresh_flush()
	var/image/worn = H.overlays_standing[UNIFORM_LAYER]
	TEST_ASSERT(worn, "the worn uniform is drawn on its layer")
	var/worn_icon = worn.icon
	TEST_ASSERT(dq_mob_visuals_shows(H, worn_icon), "and shows on the mob ([worn_icon])")
	TEST_ASSERT(H.unEquip(uniform, target = H.loc), "the uniform comes off")
	refresh_flush()
	TEST_ASSERT_NULL(H.overlays_standing[UNIFORM_LAYER], "the removed uniform leaves its layer")
	TEST_ASSERT(!dq_mob_visuals_shows(H, worn_icon), "and no longer shows on the mob")

/// TRUE when one of `A`'s overlays draws `drawn` (worn sprites are built icons with no state to tell them apart).
/datum/unit_test/proc/dq_mob_visuals_shows(atom/A, drawn)
	for(var/overlay in A.overlays)
		var/mutable_appearance/MA = new(overlay)
		if(MA.icon == drawn)
			return TRUE
	return FALSE

/// Facing north the tail hangs over the back of the pants; facing south it sits under the clothes (the pre-rewrite layering).
/datum/unit_test/dq_mob_visuals_tail_layers_over_the_uniform

/datum/unit_test/dq_mob_visuals_tail_layers_over_the_uniform/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_dir(NORTH)
	TEST_ASSERT(H.get_tail_layer() > UNIFORM_LAYER, "facing north the tail is drawn above the uniform")
	H.set_dir(SOUTH)
	TEST_ASSERT(H.get_tail_layer() < UNIFORM_LAYER, "facing south the tail is drawn under the uniform")
	var/datum/sprite_accessory/tail/style = new
	TEST_ASSERT(!(NORTH in style.lower_layer_dirs), "a tail style keeps north on the upper layer by default")

/// A human that is not a technomancer has no instability meter on its HUD; instability makes one.
/datum/unit_test/dq_mob_visuals_hud_has_no_instability_meter

/datum/unit_test/dq_mob_visuals_hud_has_no_instability_meter/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	if(!H.hud_used)
		H.set_hud_used(new /datum/hud(H))
		H.hud_used.instantiate()
	TEST_ASSERT_NULL(H.hud_used.wiz_instability_display, "a plain human's HUD has no instability meter")
	for(var/atom/movable/screen/S in H.hud_used.adding + H.hud_used.other)
		TEST_ASSERT(!istype(S, /atom/movable/screen/wizard/instability), "nor one among its screens")
