// A radial choice must reach a client: the ring's image shows every slice (an /image has no vis_add path of a movable), each choice has a picture with a real icon
// state, and a ring that cannot be shown ends the question instead of leaving it open. A test mob has no client, so the holder is built without one.

/datum/unit_test/dq_p2_engine/radial_ring_holder_shows_every_part

/datum/unit_test/dq_p2_engine/radial_ring_holder_shows_every_part/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/radial_menu/menu = new
	rel_set(menu, nameof(menu.anchor), H)
	menu.set_choices(list("switch" = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_use"), "dial" = image(icon = 'icons/mob/radial.dmi', icon_state = "radial_temp")), FALSE, FALSE)
	var/shown = menu.build_holder()
	TEST_ASSERT_EQUAL(shown, length(menu.elements) + 1, "the ring's image shows every slice and the centre button")
	TEST_ASSERT_EQUAL(length(menu.menu_holder.vis_contents), shown, "the parts are in the image's vis_contents")
	var/list/states = icon_states_fast('icons/mob/radial.dmi')
	for(var/state in list("radial_slice", "radial_slice_focus", "radial_center", "radial_use", "radial_temp", "radial_eject_input"))
		TEST_ASSERT(state in states, "radial.dmi has the state [state]")
	TEST_ASSERT_EQUAL(length(menu.choices_icons), 2, "each choice has a picture")
	for(var/id in menu.choices_icons)
		var/mutable_appearance/MA = menu.choices_icons[id]
		TEST_ASSERT(MA.icon == 'icons/mob/radial.dmi' && (MA.icon_state in states), "the picture of [id] names a real state ([MA.icon_state])")
	var/shown_slices = 0
	for(var/atom/movable/screen/radial/slice/slice in menu.elements)
		if(slice.alpha == 255 && slice.choice)
			shown_slices++
	TEST_ASSERT_EQUAL(shown_slices, 2, "a slice per choice is visible")
	qdel(menu)

/datum/unit_test/dq_p2_engine/radial_ring_without_a_client_says_so

/datum/unit_test/dq_p2_engine/radial_ring_without_a_client_says_so/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/radial_menu/menu = new
	rel_set(menu, nameof(menu.anchor), H)
	menu.set_choices(list("a" = null, "b" = null), FALSE, FALSE)
	TEST_ASSERT(!menu.show_to(H), "a ring with no client to show it to reports that it was not shown")
	qdel(menu)

/datum/unit_test/dq_p2_engine/radial_prompt_timeout_zero_is_the_default_not_instant

/datum/unit_test/dq_p2_engine/radial_prompt_timeout_zero_is_the_default_not_instant/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/p2_asker_item/I = allocate(/obj/item/p2_asker_item)
	var/datum/prompt/choice/asked = open_request(I, /datum/prompt/choice, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, choices = list("a", "b"), radial = TRUE, timeout = 0)
	TEST_ASSERT_NOTNULL(asked, "the request opens")
	test_time(1 SECOND)
	TEST_ASSERT(asked.is_open(), "timeout 0 means the default timeout, not an instant one")
	test_answer(H, "a")
	TEST_ASSERT_EQUAL(I.seen_answer, "a", "it can still be answered")
