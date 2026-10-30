// The look forms that replaced the last raw overlay writes: look.live_image() (an image its owner edits: a HUD icon), look.mimic() (another atom's
// appearance), look_flash() of an image (a transient layer that takes itself back) and a limb's shown_layers.

/// How many of A's overlays sit on `plane`, and the icon_states they show.
/datum/unit_test/proc/look_forms_on_plane(atom/A, plane)
	. = list()
	for(var/layer in A.overlays)
		var/mutable_appearance/MA = new(layer)
		if(MA.plane == plane)
			. += "[MA.icon_state]"

/// A HUD image edited in place reaches the overlays only through the publish, replaces the copy it made (no stale layer), and a draw that stops
/// showing it takes it back.
/datum/unit_test/dq_look_live_image

/datum/unit_test/dq_look_live_image/Run()
	var/obj/item/pen/pen = allocate(/obj/item/pen, test_floor())
	var/image/hud = image('icons/mob/hud.dmi', null, "hudhealthy")
	hud.plane = PLANE_CH_STATUS
	var/base_count = length(pen.overlays)
	var/datum/look/first = new
	first.live_image(hud)
	first.apply_to(pen)
	TEST_ASSERT_EQUAL(length(pen.overlays), base_count + 1, "the image is shown as one layer")
	TEST_ASSERT_EQUAL(jointext(look_forms_on_plane(pen, PLANE_CH_STATUS), ","), "hudhealthy", "with the state it had")
	var/key_before = first.change_key()
	hud.icon_state = "huddead"
	var/datum/look/second = new
	second.live_image(hud)
	TEST_ASSERT(second.change_key() != key_before, "an edit of the image is a different look")
	second.apply_to(pen)
	TEST_ASSERT_EQUAL(length(pen.overlays), base_count + 1, "the old copy is cut by what was added: no stale layer")
	TEST_ASSERT_EQUAL(jointext(look_forms_on_plane(pen, PLANE_CH_STATUS), ","), "huddead", "and the new state shows")
	var/datum/look/none = new
	none.live_image(null)
	none.live_image(hud, when = FALSE)
	none.apply_to(pen)
	TEST_ASSERT_EQUAL(length(pen.overlays), base_count, "a look that no longer shows it takes it back")

/// The human carries its HUD images through apply_hud(): the edit reaches the overlays once, with no overlay call of its own.
/datum/unit_test/dq_look_hud_images

/datum/unit_test/dq_look_hud_images/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(length(look_forms_on_plane(H, PLANE_CH_HEALTH)), 1, "the health HUD image is on the body")
	var/image/health = H.grab_hud(HEALTH_HUD)
	TEST_ASSERT_NOTNULL(health, "the slot holds its image")
	var/was = length(H.overlays)
	health.icon_state = "hudbrain"
	refresh_flush()
	TEST_ASSERT(!("hudbrain" in look_forms_on_plane(H, PLANE_CH_HEALTH)), "an edit nobody published is not shown")
	H.apply_hud(HEALTH_HUD, health)
	refresh_flush()
	TEST_ASSERT_EQUAL(jointext(look_forms_on_plane(H, PLANE_CH_HEALTH), ","), "hudbrain", "the published edit replaces the copy")
	TEST_ASSERT_EQUAL(length(H.overlays), was, "and leaves no stale layer")

/// A mimic wears the other atom's icon, state and layers, and follows it when it is redrawn.
/datum/unit_test/dq_look_mimic

/datum/unit_test/dq_look_mimic/Run()
	var/turf/T = test_floor()
	var/obj/item/pen/original = allocate(/obj/item/pen, T)
	var/obj/item/pen/copy = allocate(/obj/item/pen, T)
	original.set_icon_state("fix")
	var/datum/look/shows = new
	shows.overlay(look_appearance('icons/mob/hud.dmi', "hudhealthy"))
	shows.apply_to(original)
	var/datum/look/wears = new
	wears.mimic(original)
	TEST_ASSERT(wears.watched_looks?[OWN_KEY(original)] != null, "the copy hears of the original's look")
	TEST_ASSERT_EQUAL(wears.icon_state, "fix", "it takes the state")
	wears.apply_to(copy)
	TEST_ASSERT_EQUAL(copy.icon, original.icon, "and the icon")
	var/matches = 0
	for(var/layer in copy.overlays)
		var/mutable_appearance/MA = new(layer)
		if(MA.icon_state == "hudhealthy")
			matches++
	TEST_ASSERT_EQUAL(matches, 1, "and each layer the original shows")
	var/datum/look/nothing = new
	nothing.mimic(null)
	TEST_ASSERT(nothing.touched && isnull(nothing.icon), "a null original copies nothing")

/// A flashed image is a layer of the holder's look for its time, then takes itself back through the timer.
/datum/unit_test/dq_look_flash_image

/datum/unit_test/dq_look_flash_image/Run()
	var/obj/item/pen/pen = allocate(/obj/item/pen, test_floor())
	refresh_flush()
	var/base_count = length(pen.overlays)
	var/image/bubble = image('icons/effects/effects.dmi', "thought_bubble")
	bubble.plane = PLANE_RUNECHAT
	look_flash(pen, bubble, 5 SECONDS)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(pen.overlays), base_count + 1, "the flashed image is a layer of the look")
	var/datum/cap_engine_state/engine = cap_engine_state_of(pen)
	look_flash_end(pen, bubble, engine.look_flash_tokens[bubble], FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(pen.overlays), base_count, "the end of its time takes it back")

/// A limb shows the layers it was built from over its own icon, through its draw.
/datum/unit_test/dq_limb_shown_layers

/datum/unit_test/dq_limb_shown_layers/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT_NOTNULL(arm, "the body has the limb")
	arm.get_icon()
	refresh_flush()
	var/base_count = length(arm.overlays)
	var/icon/layer = icon('icons/mob/human_face.dmi', "bald_s")
	arm.set_shown_layers(list(layer))
	refresh_flush()
	TEST_ASSERT_EQUAL(length(arm.overlays), base_count + 1, "a layer set on the limb is drawn")
	arm.set_shown_layers(null)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(arm.overlays), base_count, "and taken back when it is gone")
