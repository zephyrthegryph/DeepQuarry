// The simple mob and robot looks over tracked state: fullness follows the bellies, pounce shifts and resets, eyes follow the life state, and a
// robot's panel, sprite and module state redraw it with no call.

/mob/living/simple_mob/dq_draw_pred
	name = "draw pred"
	icon = 'icons/mob/animal.dmi'
	icon_state = "mouse_gray"
	icon_living = "mouse_gray"
	icon_dead = "mouse_gray_dead"
	has_eye_glow = TRUE
	vore_active = TRUE
	vore_capacity = 2
	vore_icons = SA_ICON_LIVING
	icon_state_prepounce = "mouse_gray_pre"
	icon_state_pounce = "mouse_gray_leap"
	icon_pounce_x = 8
	icon_pounce_y = 4

/// The overlay states (icon_state of each overlay) the mob shows now.
/datum/unit_test/proc/dq_overlay_states(atom/A)
	. = list()
	for(var/overlay in A.overlays)
		var/mutable_appearance/MA = new(overlay)
		. += "[MA.icon_state]"

/// Fullness is recomputed from the belly contents: prey entering or leaving redraws the mob, nobody calls a redraw.
/datum/unit_test/dq_draw_mob_fullness_follows_belly_contents

/datum/unit_test/dq_draw_mob_fullness_follows_belly_contents/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/dq_draw_pred/pred = allocate(/mob/living/simple_mob/dq_draw_pred, T)
	pred.init_vore(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(pred.vore_fullness, 0, "an empty belly shows nothing")
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray", "and the plain living state")
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human, T)
	var/obj/belly/belly = pred.vore_selected
	TEST_ASSERT(belly.belly_insert(prey, pred), "prey goes into the belly")
	refresh_flush()
	TEST_ASSERT_EQUAL(pred.vore_fullness, 1, "the belly's content is the mob's tracked fullness without a hand call")
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray-1", "the fullness state is drawn")
	prey.forceMove(T)
	refresh_flush()
	TEST_ASSERT_EQUAL(pred.vore_fullness, 0, "prey leaving empties it again")
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray", "and the plain state is back")

/// Pounce state is tracked: the crouch and the leap draw their states, the leap shifts the sprite, and ending it gives the offset back.
/datum/unit_test/dq_draw_mob_pounce_offset_resets

/datum/unit_test/dq_draw_mob_pounce_offset_resets/Run()
	var/mob/living/simple_mob/dq_draw_pred/pred = allocate(/mob/living/simple_mob/dq_draw_pred, test_floor())
	refresh_flush()
	var/base_x = pred.pixel_x
	var/base_y = pred.pixel_y
	pred.set_pouncing(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray_pre", "a pounce being readied draws the crouch")
	TEST_ASSERT_EQUAL(pred.pixel_x, base_x, "without a shift")
	pred.set_status_flags(pred.status_flags | LEAPING)
	refresh_flush()
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray_leap", "the leap draws the leap state")
	TEST_ASSERT_EQUAL(pred.pixel_x, 8, "shifted in x")
	TEST_ASSERT_EQUAL(pred.pixel_y, 4, "and y")
	pred.set_status_flags(pred.status_flags & ~LEAPING)
	pred.set_pouncing(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(pred.pixel_x, base_x, "the offset is given back in x")
	TEST_ASSERT_EQUAL(pred.pixel_y, base_y, "and y")
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray", "and the living state is back")

/// The eye layer is a look layer: shown while awake, gone with the life state, back when revived.
/datum/unit_test/dq_draw_mob_eyes_follow_state

/datum/unit_test/dq_draw_mob_eyes_follow_state/Run()
	var/mob/living/simple_mob/dq_draw_pred/pred = allocate(/mob/living/simple_mob/dq_draw_pred, test_floor())
	refresh_flush()
	TEST_ASSERT(("mouse_gray-eyes" in dq_overlay_states(pred)), "an awake mob with eye glow shows its eyes: [json_encode(dq_overlay_states(pred))]")
	pred.set_stat(DEAD)
	refresh_flush()
	TEST_ASSERT(!("mouse_gray-eyes" in dq_overlay_states(pred)), "a dead one does not")
	TEST_ASSERT_EQUAL(pred.icon_state, "mouse_gray_dead", "it shows the dead state")
	TEST_ASSERT_EQUAL(pred.return_from_death("unit test", src, REVIVE_HEAL), TRUE, "it comes back")
	refresh_flush()
	TEST_ASSERT(("mouse_gray-eyes" in dq_overlay_states(pred)), "revived, the eyes are back")

/// A robot's cover, sprite and active module types are tracked: changing them redraws it.
/datum/unit_test/dq_draw_robot_state_redraws

/datum/unit_test/dq_draw_robot_state_redraws/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	refresh_flush()
	TEST_ASSERT(R.sprite_datum, "the robot resolved a sprite")
	TEST_ASSERT_EQUAL(R.icon, R.sprite_datum.sprite_icon, "it is drawn from its sprite datum")
	TEST_ASSERT(!("openpanel_nc" in dq_overlay_states(R)) && !("openpanel_c" in dq_overlay_states(R)), "the cover is closed")
	R.set_opened(TRUE)
	refresh_flush()
	var/list/states = dq_overlay_states(R)
	TEST_ASSERT((("openpanel_nc" in states) || ("openpanel_c" in states) || ("openpanel_w" in states) || R.sprite_datum.has_custom_open_sprites), "opening the cover draws the panel: [json_encode(states)]")
	R.set_opened(FALSE)
	refresh_flush()
	TEST_ASSERT(!("openpanel_nc" in dq_overlay_states(R)) && !("openpanel_c" in dq_overlay_states(R)), "closing it takes the panel back")
	var/list/candidates = SSrobot_sprites.get_module_sprites(R.modtype, R)
	for(var/datum/robot_sprite/other in candidates)
		if(other == R.sprite_datum || other.sprite_icon == R.sprite_datum.sprite_icon)
			continue
		proto_set(R, nameof(/mob/living/silicon/robot::sprite_datum), other)
		refresh_flush()
		TEST_ASSERT_EQUAL(R.icon, other.sprite_icon, "a new sprite redraws the robot")
		TEST_ASSERT_EQUAL(R.vis_height, other.vis_height, "and what the sprite sets on the body follows it once")
		break

/// The belly lights are computed with the fullness: a belly notice recomputes them and the robot redraws with no call.
/datum/unit_test/dq_draw_robot_belly_lights_follow_fullness

/datum/unit_test/dq_draw_robot_belly_lights_follow_fullness/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	refresh_flush()
	R.update_fullness()
	TEST_ASSERT(!length(R.vore_light_states) || !R.belly_light("sleeper"), "no prey, no belly light")
	TEST_ASSERT(R.set_vore_light_states(list("sleeper" = 1)), "a changed light state is a change")
	TEST_ASSERT(!R.set_vore_light_states(list("sleeper" = 1)), "an equal one is not")
	TEST_ASSERT_EQUAL(R.belly_light("sleeper"), R.resting ? 0 : 1, "the draw reads it through belly_light()")
	R.set_vore_light_states(null)

/// A look overlay's key names pixel_w and pixel_z: a robot's hat at another offset is a different look.
/datum/unit_test/dq_draw_overlay_key_names_pixel_w_z

/datum/unit_test/dq_draw_overlay_key_names_pixel_w_z/Run()
	var/image/a = look_overlay_image('icons/obj/stock_parts.dmi', "fix", pixel_w = 1, pixel_z = 2)
	var/image/b = look_overlay_image('icons/obj/stock_parts.dmi', "fix", pixel_w = 3, pixel_z = 2)
	TEST_ASSERT(look_part_key(a) != look_part_key(b), "pixel_w differs in the key")
	TEST_ASSERT_EQUAL(a.pixel_z, 2, "pixel_z is applied")

/// Nutrition is tracked, so a turkeygirl redraws as it fills.
/datum/unit_test/dq_draw_turkeygirl_follows_nutrition

/datum/unit_test/dq_draw_turkeygirl_follows_nutrition/Run()
	var/mob/living/simple_mob/vore/turkeygirl/T = allocate(/mob/living/simple_mob/vore/turkeygirl, test_floor())
	refresh_flush()
	T.set_nutrition(0)
	refresh_flush()
	var/plain = T.icon_state
	T.set_nutrition(5000)
	refresh_flush()
	TEST_ASSERT_EQUAL(T.icon_state, "[T.icon_living]-2", "a full turkeygirl shows the fullest state (was [plain])")

/// Deleting a worm out of the world leaves no severed head behind, and deleting a blob core takes its overmind with it.
/datum/unit_test/dq_draw_destroy_leaves_nothing_behind

/datum/unit_test/dq_draw_destroy_leaves_nothing_behind/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/space/space_worm/head/worm = allocate(/mob/living/simple_mob/animal/space/space_worm/head, T)
	var/before = 0
	for(var/mob/living/simple_mob/animal/space/space_worm/head/severed/H in world)
		before++
	qdel(worm)
	var/after = 0
	for(var/mob/living/simple_mob/animal/space/space_worm/head/severed/H in world)
		after++
	TEST_ASSERT_EQUAL(after, before, "deleting a worm leaves no severed head")
	var/obj/structure/blob/core/core = allocate(/obj/structure/blob/core, T)
	refresh_flush()
	var/mob/observer/blob/overmind = core.overmind
	if(overmind)
		qdel(core)
		TEST_ASSERT(QDELETED(overmind), "the overmind goes with its core")
