// A worn or held item's state reaches the wearer's picture by itself: the setters publish, the wearer watches what it wears, and no
// item asks for a redraw (the hand `changed()` mark and update_clothing_icon() are gone).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Worn goggles switched off show their off sprite on the wearer.
/datum/unit_test/dq_worn_redraw_glasses_toggle

/datum/unit_test/dq_worn_redraw_glasses_toggle/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "glasses")
	var/obj/item/clothing/glasses/meson/goggles = new(H)
	H.equip_to_slot_or_del(goggles, SLOT_ID_EYES)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_EYES), goggles, "the goggles are worn")
	refresh_flush()
	var/list/on_overlays = H.overlays.Copy()
	goggles.toggle_active(H)
	TEST_ASSERT_EQUAL(goggles.icon_state, goggles.off_state, "switching them off takes their off sprite")
	refresh_flush()
	TEST_ASSERT(length(H.overlays ^ on_overlays), "and the wearer's applied look changed without any redraw ask")
	goggles.toggle_active(H)
	refresh_flush()
	TEST_ASSERT(!length(H.overlays ^ on_overlays), "switching them on again restores the applied look")

/// A hood pulled up is drawn on the head and put down it is not.
/datum/unit_test/dq_worn_redraw_hood_toggle

/datum/unit_test/dq_worn_redraw_hood_toggle/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "hood")
	var/obj/item/clothing/suit/storage/hooded/costume/carp/coat = new(H)
	H.equip_to_slot_or_del(coat, SLOT_ID_SUIT)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_SUIT), coat, "the coat is worn")
	TEST_ASSERT_NULL(H.look_layers()[HEAD_LAYER], "no hood is drawn before it is pulled up")
	var/down_picture = dq_hd_picture(H)
	coat.ToggleHood()
	TEST_ASSERT(coat.hood_up, "the hood is up")
	TEST_ASSERT_NOTNULL(H.look_layers()[HEAD_LAYER], "the hood is drawn on the head")
	TEST_ASSERT(dq_hd_picture(H) != down_picture, "and the wearer shows it")
	coat.ToggleHood()
	TEST_ASSERT_NULL(H.look_layers()[HEAD_LAYER], "put down again, the head layer is empty")
	TEST_ASSERT_EQUAL(dq_hd_picture(H), down_picture, "and the picture is back")

/// A two-handed weapon is wielded while the other hand is free: the hands changing re-derives it.
/datum/unit_test/dq_worn_redraw_wield_follows_hands

/datum/unit_test/dq_worn_redraw_wield_follows_hands/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "wield")
	var/obj/item/material/twohanded/fireaxe/axe = allocate(/obj/item/material/twohanded/fireaxe, test_floor())
	H.put_in_hands(axe)
	TEST_ASSERT_EQUAL(axe.loc, H, "the axe is in a hand")
	TEST_ASSERT(axe.wielded, "with the other hand free it is wielded")
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, test_floor())
	H.put_in_hands(bar)
	TEST_ASSERT(!axe.wielded, "a full pair of hands unwields it")
	H.drop_from_inventory(bar)
	bar.forceMove(test_floor())
	TEST_ASSERT(axe.wielded, "and it is wielded again once the hand is free")

#endif
