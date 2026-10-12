// Clothing on the body: a coat picked up and put on is drawn on the player, taken off it is not; a tail hangs over the back of the
// pants seen from behind and under the clothes seen from the front.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Picks a coat off the floor, puts it on with the equip key, takes it off at the HUD slot and drops it: the look follows each step.
/datum/unit_test/dq_gameplay/coat_on_and_off

/datum/unit_test/dq_gameplay/coat_on_and_off/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 2))
	var/obj/item/clothing/suit/greatcoat/coat = allocate(/obj/item/clothing/suit/greatcoat, tile(2, 2)) // no pockets: a click on a worn coat with pockets opens them
	TEST_ASSERT_NULL(H.overlays_standing[SUIT_LAYER], "no coat drawn before")
	var/list/look_before = H.overlays.Copy()
	click(H, coat)
	TEST_ASSERT_EQUAL(H.get_active_hand(), coat, "clicking the coat on the floor picks it up")
	key_equip(H)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_SUIT), coat, "the equip key puts the coat on")
	var/image/worn = H.overlays_standing[SUIT_LAYER]
	TEST_ASSERT_NOTNULL(worn, "the worn coat has a drawn layer")
	TEST_ASSERT(draws_icon(H, worn.icon), "and the coat shows on the player ([worn.icon])")
	TEST_ASSERT(length(H.overlays ^ look_before), "the player's look changed when the coat went on")
	var/worn_icon = worn.icon
	var/obj/screen_slot = hud_slot(H, SLOT_ID_SUIT)
	TEST_ASSERT_NOTNULL(screen_slot, "the HUD has a suit slot")
	click(H, screen_slot)
	TEST_ASSERT_EQUAL(H.get_active_hand(), coat, "an empty hand on the suit slot takes the coat off")
	TEST_ASSERT_NULL(H.overlays_standing[SUIT_LAYER], "the removed coat leaves its layer")
	TEST_ASSERT(!draws_icon(H, worn_icon), "and no longer shows on the player")
	key_drop(H)
	TEST_ASSERT_EQUAL(coat.loc, H.loc, "the drop key puts it on the floor")

/// A tailed player in a jumpsuit: walking north (seen from behind) the tail is drawn over the uniform; walking south it is under it.
/datum/unit_test/dq_gameplay/tail_over_uniform
	// /atom/proc/set_dir() returns null, so /mob/living/carbon/human/set_dir()'s `if(. && (species.tail || tail_style))` never redraws the
	// suit and tail layers when the player turns: the tail keeps the layer of the direction it was drawn facing (human draw lane).
	expected_failure = "the tail is not redrawn when the player turns: /atom/proc/set_dir() returns null, so human set_dir() never calls update_inv_wear_suit()"

/datum/unit_test/dq_gameplay/tail_over_uniform/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 1), species = SPECIES_TAJARAN)
	TEST_ASSERT_NOTNULL(H.overlays_standing[UNIFORM_LAYER], "the uniform is drawn")
	TEST_ASSERT(stride(H, NORTH), "the player walks north")
	TEST_ASSERT_EQUAL(H.dir, NORTH, "and faces north")
	var/list/north = tail_and_uniform(H)
	TEST_ASSERT(north, "a tail and a uniform are drawn facing north ([json_encode(drawn_layers(H))])")
	TEST_ASSERT(north[1] > north[2], "facing north the tail ([north[1]]) is drawn over the uniform ([north[2]])")
	TEST_ASSERT(stride(H, SOUTH), "the player walks south")
	var/list/south = tail_and_uniform(H)
	TEST_ASSERT(south, "a tail and a uniform are drawn facing south ([json_encode(drawn_layers(H))])")
	TEST_ASSERT(south[1] < south[2], "facing south the tail ([south[1]]) is drawn under the uniform ([south[2]])")

/// The drawn layers of the tail and of the uniform on `H` (both must be among its overlays), or null.
/datum/unit_test/dq_gameplay/tail_over_uniform/proc/tail_and_uniform(mob/living/carbon/human/H)
	var/image/uniform = H.overlays_standing[UNIFORM_LAYER]
	var/image/tail
	for(var/index in list(TAIL_UPPER_LAYER, TAIL_UPPER_LAYER_HIGH, TAIL_UPPER_LAYER_LOW, TAIL_LOWER_LAYER))
		if(H.overlays_standing[index])
			tail = H.overlays_standing[index]
			break
	if(!uniform || !tail)
		return null
	var/list/drawn = drawn_layers(H)
	if(!(tail.layer in drawn) || !(uniform.layer in drawn))
		return null
	return list(tail.layer, uniform.layer)

#endif
