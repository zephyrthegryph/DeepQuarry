// Hand-toggled lights derive from state: a flashlight is lit while it is on, a helmet while its lamp is lit, a skimmer while it flies, an event
// headset while worn. The light is part of the look, so it follows the state whatever last changed it and wherever the item is (held, worn, dropped).

/datum/unit_test/dq_state_derived_light
	abstract_type = /datum/unit_test/dq_state_derived_light

/datum/unit_test/dq_state_derived_light/proc/lit(atom/A)
	return A.light_on && glow_of(A).range > 0

/datum/unit_test/dq_state_derived_light/flashlight
/datum/unit_test/dq_state_derived_light/flashlight_worn
/datum/unit_test/dq_state_derived_light/flashlight_flicker_colour
/datum/unit_test/dq_state_derived_light/lamp_and_slime
/datum/unit_test/dq_state_derived_light/helmet
/datum/unit_test/dq_state_derived_light/uav
/datum/unit_test/dq_state_derived_light/event_headset

/datum/unit_test/dq_state_derived_light/flashlight/Run()
	var/obj/item/flashlight/light = allocate(/obj/item/flashlight, test_floor())
	refresh_flush()
	TEST_ASSERT(!lit(light), "a flashlight that was never switched on casts nothing")
	light.set_on(1)
	refresh_flush()
	TEST_ASSERT(lit(light), "switched on it casts light")
	TEST_ASSERT_EQUAL(glow_of(light).range, 4, "at its type's range")
	light.set_on(0)
	refresh_flush()
	TEST_ASSERT(!lit(light), "switched off it casts nothing")
	light.set_on(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(light).range, 4, "and lights again at the same range")
	var/obj/item/flashlight/pen/pen = allocate(/obj/item/flashlight/pen, test_floor())
	pen.set_on(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(pen).range, 2, "a subtype lights at its own range")

/datum/unit_test/dq_state_derived_light/flashlight_worn/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/flashlight/light = allocate(/obj/item/flashlight)
	TEST_ASSERT(H.equip_to_slot_if_possible(light, SLOT_ID_BELT, quiet = TRUE), "the flashlight goes on the belt")
	light.set_on(1)
	refresh_flush()
	TEST_ASSERT(lit(light), "a carried flashlight that is on casts light")
	light.set_on(0)
	refresh_flush()
	TEST_ASSERT(!lit(light), "and stops when it goes off in the pocket")

/datum/unit_test/dq_state_derived_light/flashlight_flicker_colour/Run()
	var/obj/item/flashlight/light = allocate(/obj/item/flashlight, test_floor())
	light.set_on(1)
	refresh_flush()
	var/original = glow_of(light).color
	light.set_light_color("#ff0000")
	light.set_on(0)
	refresh_flush()
	light.set_on(1)
	refresh_flush()
	TEST_ASSERT(lit(light), "a flickering light comes back on")
	TEST_ASSERT_EQUAL(glow_of(light).color, "#ff0000", "in the colour the flicker gave it")
	light.set_light_color(original)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(light).color, original, "and the colour it had before once the flicker ends")

/datum/unit_test/dq_state_derived_light/lamp_and_slime/Run()
	var/obj/item/flashlight/lamp/lamp = allocate(/obj/item/flashlight/lamp, test_floor())
	var/obj/item/flashlight/slime/slime = allocate(/obj/item/flashlight/slime, test_floor())
	refresh_flush()
	TEST_ASSERT(lit(lamp), "a desk lamp starts on and casts light")
	TEST_ASSERT(lit(slime), "a slime extract light is always lit")
	TEST_ASSERT_EQUAL(glow_of(slime).range, 6, "in its own range")
	TEST_ASSERT_EQUAL(glow_of(slime).color, "#FFF423", "and its own colour")
	lamp.set_on(0)
	refresh_flush()
	TEST_ASSERT(!lit(lamp), "a lamp switched off is dark")

/datum/unit_test/dq_state_derived_light/helmet/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/head/hardhat/hat = allocate(/obj/item/clothing/head/hardhat)
	TEST_ASSERT(H.equip_to_slot_if_possible(hat, SLOT_ID_HEAD, quiet = TRUE), "the hard hat goes on the head")
	refresh_flush()
	TEST_ASSERT(!lit(hat), "an unlit lamp casts nothing")
	hat.update_flashlight(H)
	refresh_flush()
	TEST_ASSERT(hat.lamp_lit, "toggling lights the lamp")
	TEST_ASSERT(lit(hat), "and the worn helmet casts light")
	TEST_ASSERT_EQUAL(glow_of(hat).range, 4, "at its type's range")
	hat.update_flashlight(H)
	refresh_flush()
	TEST_ASSERT(!lit(hat), "toggled again it is dark")
	hat.update_flashlight(H)
	refresh_flush()
	TEST_ASSERT(lit(hat), "and it can be lit again after having been dark")
	var/obj/item/clothing/head/hood/winter/ratvar/hood = allocate(/obj/item/clothing/head/hood/winter/ratvar, test_floor())
	refresh_flush()
	TEST_ASSERT(lit(hood), "a hood that starts lit casts light")

/datum/unit_test/dq_state_derived_light/uav/Run()
	var/obj/item/uav/uav = allocate(/obj/item/uav, test_floor())
	refresh_flush()
	TEST_ASSERT(!lit(uav), "a grounded skimmer casts nothing")
	uav.set_state(1) // UAV_ON
	refresh_flush()
	TEST_ASSERT(lit(uav), "a flying skimmer casts light")
	uav.set_state(0)
	refresh_flush()
	TEST_ASSERT(!lit(uav), "a skimmer set down is dark")

/datum/unit_test/dq_state_derived_light/event_headset/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/radio/headset/event/headset = allocate(/obj/item/radio/headset/event)
	set_glow(headset, GLOW(null, 1, null)) // an admin gives it a power: the base type declares none
	refresh_flush()
	TEST_ASSERT(!lit(headset), "a headset nobody wears casts nothing")
	TEST_ASSERT(H.equip_to_slot_if_possible(headset, SLOT_ID_EAR_L, quiet = TRUE), "the headset goes on an ear")
	refresh_flush()
	TEST_ASSERT(lit(headset), "worn, it casts light")
	TEST_ASSERT_EQUAL(glow_of(headset).range, 6, "at its type's range")
	H.drop_from_inventory(headset)
	refresh_flush()
	TEST_ASSERT(!lit(headset), "taken off, it is dark")
	TEST_ASSERT(H.equip_to_slot_if_possible(headset, SLOT_ID_EAR_L, quiet = TRUE), "it goes on again")
	refresh_flush()
	TEST_ASSERT(lit(headset), "and lights again")
