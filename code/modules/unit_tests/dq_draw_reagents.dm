// The reagent, food and hydroponics draws: what a container shows follows the volume, colour and contents its holder tracks, and what a machine or
// tray shows follows the state it writes through setters. No test calls update_icon() or changed(): the write is the redraw.

/// The overlay (or underlay) appearances of `A`.
/proc/dq_dr_layers(atom/A, under = FALSE)
	. = list()
	for(var/layer in (under ? A.underlays : A.overlays))
		. += new /mutable_appearance(layer)

/// The overlay (or underlay) of `A` that shows `state`, or null.
/proc/dq_dr_find(atom/A, state, under = FALSE)
	for(var/mutable_appearance/MA as anything in dq_dr_layers(A, under))
		if(MA.icon_state == state)
			return MA
	return null

/// The first seven characters of a colour, upper case: the hue without the alpha an appearance may drop.
/proc/dq_dr_hue(colour)
	return uppertext(copytext("[colour]", 1, 8))

// ---- the holder tracks what a look shows ----

/datum/unit_test/dq_draw_reagents_holder_tracks_volume_colour_and_master

/datum/unit_test/dq_draw_reagents_holder_tracks_volume_colour_and_master/Run()
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	var/datum/reagents/R = B.reagents
	TEST_ASSERT_EQUAL(R.total_volume, 0, "an empty beaker holds nothing")
	TEST_ASSERT_NULL(R.master_id, "and has no main reagent")
	R.add_reagent(REAGENT_ID_WATER, 20)
	TEST_ASSERT_EQUAL(R.total_volume, 20, "the total follows an addition")
	TEST_ASSERT_EQUAL(R.master_id, REAGENT_ID_WATER, "the main reagent is the one there is most of")
	TEST_ASSERT_EQUAL(R.tint, R.get_color(), "the tint is the colour of the mix")
	R.add_reagent(REAGENT_ID_BLOOD, 30)
	TEST_ASSERT_EQUAL(R.master_id, REAGENT_ID_BLOOD, "more of another reagent makes it the main one")
	TEST_ASSERT_EQUAL(R.tint, R.get_color(), "and the tint follows the mix")
	R.clear_reagents()
	TEST_ASSERT_EQUAL(R.total_volume, 0, "clearing empties it")
	TEST_ASSERT_NULL(R.master_id, "and takes its main reagent")

// ---- a beaker's fill overlay follows volume and colour ----

/datum/unit_test/dq_draw_reagents_beaker_fill_follows_volume_and_colour

/datum/unit_test/dq_draw_reagents_beaker_fill_follows_volume_and_colour/Run()
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	refresh_flush()
	for(var/mutable_appearance/MA as anything in dq_dr_layers(B))
		TEST_ASSERT(!findtext(MA.icon_state, "beaker-"), "an empty beaker shows no filling: [MA.icon_state]")
	B.reagents.add_reagent(REAGENT_ID_WATER, 15)
	refresh_flush()
	var/mutable_appearance/low = dq_dr_find(B, "beaker-20")
	TEST_ASSERT_NOTNULL(low, "a quarter full shows the 20 filling")
	TEST_ASSERT_EQUAL(dq_dr_hue(low.color), dq_dr_hue(B.reagents.tint), "in the colour of what it holds")
	B.reagents.add_reagent(REAGENT_ID_WATER, 20)
	refresh_flush()
	TEST_ASSERT_NULL(dq_dr_find(B, "beaker-20"), "the old filling is gone")
	var/mutable_appearance/mid = dq_dr_find(B, "beaker-40")
	TEST_ASSERT_NOTNULL(mid, "more of it shows the next filling")
	// The same amount of something else: only the colour moved.
	var/before = dq_dr_hue(mid.color)
	B.reagents.clear_reagents()
	B.reagents.add_reagent(REAGENT_ID_BLOOD, 35)
	refresh_flush()
	var/mutable_appearance/other = dq_dr_find(B, "beaker-40")
	TEST_ASSERT_NOTNULL(other, "the same level is still drawn")
	TEST_ASSERT_EQUAL(dq_dr_hue(other.color), dq_dr_hue(B.reagents.tint), "in the colour of the new contents")
	TEST_ASSERT(dq_dr_hue(other.color) != before, "which is not the colour it had")
	B.reagents.clear_reagents()
	refresh_flush()
	TEST_ASSERT_NULL(dq_dr_find(B, "beaker-40"), "an emptied beaker shows no filling")

/datum/unit_test/dq_draw_reagents_blood_pack_and_dropper_follow_volume

/datum/unit_test/dq_draw_reagents_blood_pack_and_dropper_follow_volume/Run()
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/blood/empty/pack = allocate(/obj/item/reagent_containers/blood/empty, T)
	var/obj/item/reagent_containers/dropper/dropper = allocate(/obj/item/reagent_containers/dropper, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(pack.icon_state, "empty", "an empty pack shows empty")
	TEST_ASSERT_EQUAL(dropper.icon_state, "dropper0", "an empty dropper shows empty")
	pack.reagents.add_reagent(REAGENT_ID_BLOOD, pack.volume)
	dropper.reagents.add_reagent(REAGENT_ID_WATER, 1)
	refresh_flush()
	TEST_ASSERT_EQUAL(pack.icon_state, "full", "a full pack shows full")
	TEST_ASSERT_EQUAL(dropper.icon_state, "dropper1", "a dropper with something in it shows it")

// ---- a syringe follows its fill and its mode ----

/datum/unit_test/dq_draw_reagents_syringe_follows_fill_and_mode

/datum/unit_test/dq_draw_reagents_syringe_follows_fill_and_mode/Run()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "capped", "a new syringe is capped")
	S.set_mode(NEEDLE_DRAW)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "0", "uncapped and empty it shows empty")
	S.reagents.add_reagent(REAGENT_ID_WATER, S.reagents.maximum_volume)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(S, "filler[S.reagents.maximum_volume]"), "a full syringe shows its filling")
	TEST_ASSERT_EQUAL(S.icon_state, "[S.reagents.maximum_volume]", "and its level")
	S.set_mode(NEEDLE_BROKEN)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "broken", "a broken one shows broken")

/datum/unit_test/dq_draw_reagents_autoinjector_spent_follows_its_content

/datum/unit_test/dq_draw_reagents_autoinjector_spent_follows_its_content/Run()
	var/obj/item/reagent_containers/hypospray/autoinjector/A = allocate(/obj/item/reagent_containers/hypospray/autoinjector, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "[initial(A.icon_state)]1", "a loaded autoinjector shows loaded")
	A.reagents.clear_reagents()
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "[initial(A.icon_state)]0", "an emptied one shows spent")

// ---- a glass follows its contents ----

/datum/unit_test/dq_draw_reagents_glass_follows_its_contents

/datum/unit_test/dq_draw_reagents_glass_follows_its_contents/Run()
	var/obj/item/reagent_containers/food/drinks/glass2/square/G = allocate(/obj/item/reagent_containers/food/drinks/glass2/square, test_floor())
	refresh_flush()
	var/empty_name = G.name
	TEST_ASSERT(!findtext(empty_name, " of "), "an empty glass is named for nothing: [empty_name]")
	TEST_ASSERT_EQUAL(length(G.underlays), 0, "and shows nothing under it")
	G.reagents.add_reagent(REAGENT_ID_WATER, 20)
	refresh_flush()
	TEST_ASSERT(findtext(G.name, "glass of"), "a glass of something is named for it: [G.name]")
	TEST_ASSERT(length(G.underlays) >= 1, "and shows its filling beneath it")
	var/found = FALSE
	for(var/mutable_appearance/MA as anything in dq_dr_layers(G, TRUE))
		if(dq_dr_hue(MA.color) == dq_dr_hue(G.reagents.tint) && findtext(MA.icon_state, G.base_icon))
			found = TRUE
	TEST_ASSERT(found, "in the colour of the drink")
	G.reagents.clear_reagents()
	refresh_flush()
	TEST_ASSERT_EQUAL(G.name, empty_name, "an emptied glass is what it was")
	TEST_ASSERT_EQUAL(length(G.underlays), 0, "with nothing under it")

// ---- a cooked item redraws ----

/datum/unit_test/dq_draw_reagents_cooked_item_redraws_with_its_size

/datum/unit_test/dq_draw_reagents_cooked_item_redraws_with_its_size/Run()
	var/obj/item/reagent_containers/food/snacks/variable/cookie/C = allocate(/obj/item/reagent_containers/food/snacks/variable/cookie, test_floor())
	refresh_flush()
	C.reagents.add_reagent(REAGENT_ID_NUTRIMENT, C.size)
	refresh_flush()
	var/small = C.transform.a
	TEST_ASSERT(abs(small - C.scale_for(C.reagents.total_volume)) < 0.01, "a cookie of its normal amount is drawn at the scale of that amount: [small]")
	C.reagents.add_reagent(REAGENT_ID_NUTRIMENT, C.size * 7)
	refresh_flush()
	TEST_ASSERT(C.transform.a > small + 0.1, "more in it draws it larger: [small] to [C.transform.a]")
	TEST_ASSERT(abs(C.transform.a - C.scale_for(C.reagents.total_volume)) < 0.01, "at the scale of what it holds")
	var/old_name = C.name
	C.settle_size()
	TEST_ASSERT(C.name != old_name, "a finished dish takes its size word: [C.name]")

// ---- a pizza box follows its lid and its pizza ----

/datum/unit_test/dq_draw_reagents_pizza_box_follows_lid_pizza_and_stack

/datum/unit_test/dq_draw_reagents_pizza_box_follows_lid_pizza_and_stack/Run()
	var/turf/T = test_floor()
	var/obj/item/pizzabox/margherita/P = allocate(/obj/item/pizzabox/margherita, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "pizzabox1", "a shut box shows shut")
	TEST_ASSERT_NOTNULL(dq_dr_find(P, "pizzabox_tag"), "with the tag it carries")
	P.set_open(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "pizzabox_open", "an open box shows open")
	TEST_ASSERT(findtext(P.desc, "inside"), "and says what is in it: [P.desc]")
	P.set_ismessy(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "pizzabox_messy", "a box that held a pizza is messy")
	P.set_open(FALSE)
	var/obj/item/pizzabox/other = allocate(/obj/item/pizzabox, T)
	rel_add(P, nameof(P.boxes), other)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "pizzabox2", "a box with another on it shows two high")
	TEST_ASSERT(findtext(P.desc, "pile"), "and says so: [P.desc]")
	other.set_boxtag("tagged")
	refresh_flush()
	TEST_ASSERT(findtext(P.desc, "tagged"), "the tag of the top box reads in the pile's description: [P.desc]")

// ---- machines ----

/datum/unit_test/dq_draw_reagents_microwave_follows_operating_dirt_and_breakage

/datum/unit_test/dq_draw_reagents_microwave_follows_operating_dirt_and_breakage/Run()
	var/obj/machinery/microwave/M = allocate(/obj/machinery/microwave, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(M.icon_state, "mw", "idle and clean")
	M.set_operating(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(M.icon_state, "mw1", "running")
	M.set_operating(FALSE)
	M.set_dirty(100) // the most dirt a microwave takes (MAX_MICROWAVE_DIRTINESS, which its file keeps to itself)
	refresh_flush()
	TEST_ASSERT_EQUAL(M.icon_state, "mwbloody0", "filthy")
	M.set_broken(2) // really broken
	refresh_flush()
	TEST_ASSERT_EQUAL(M.icon_state, "mwb", "broken")

/datum/unit_test/dq_draw_reagents_oven_follows_its_door

/datum/unit_test/dq_draw_reagents_oven_follows_its_door/Run()
	var/obj/machinery/appliance/cooker/oven/O = allocate(/obj/machinery/appliance/cooker/oven, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(O.icon_state, "ovenclosed_off", "a shut oven that is off shows it")
	O.set_open(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(O.icon_state, "ovenopen", "an open one shows its door open")
	TEST_ASSERT_NOTNULL(dq_dr_find(O, "light_off"), "and its status light")

/datum/unit_test/dq_draw_reagents_alembic_follows_what_is_in_it

/datum/unit_test/dq_draw_reagents_alembic_follows_what_is_in_it/Run()
	var/obj/machinery/alembic/A = allocate(/obj/machinery/alembic, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "alembic", "empty")
	A.set_base_reagent(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "alembic-base", "with only its base in it")
	A.set_potion_reagent(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "alembic-full", "with both")
	A.set_bubbling(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "alembic-bubble", "and boiling")

/datum/unit_test/dq_draw_reagents_beehive_follows_its_frames

/datum/unit_test/dq_draw_reagents_beehive_follows_its_frames/Run()
	var/turf/T = test_floor()
	var/obj/machinery/beehive/H = allocate(/obj/machinery/beehive, T)
	var/obj/item/honey_frame/F = allocate(/obj/item/honey_frame, T)
	refresh_flush()
	TEST_ASSERT_NULL(dq_dr_find(H, "empty1"), "no frame, none drawn")
	F.forceMove(H)
	rel_add(H, nameof(H.frames), F)
	TEST_ASSERT_EQUAL(length(H.frames), 1, "the relation holds the frame: [length(H.frames)]")
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(H, "empty1"), "a frame in it is drawn")
	rel_remove(H, nameof(H.frames), F)
	refresh_flush()
	TEST_ASSERT_NULL(dq_dr_find(H, "empty1"), "and gone when it is taken out")

// ---- a tray shows its plant's growth stage ----

/datum/unit_test/dq_draw_reagents_tray_shows_its_plants_growth_stage

/datum/unit_test/dq_draw_reagents_tray_shows_its_plants_growth_stage/Run()
	var/turf/T = test_floor()
	TEST_ASSERT(SSplants && SSplants.initialized, "the plant service is initialized")
	var/datum/seed/seed = SSplants.seeds[PLANT_GLOWSHROOM]
	TEST_ASSERT_NOTNULL(seed, "the canonical seed is registered")
	seed.update_growth_stages()
	var/stages = seed.growth_stages
	TEST_ASSERT(stages > 1, "it has stages to grow through: [stages]")
	var/plant_icon = seed.get_trait(TRAIT_PLANT_ICON)
	var/maturation = seed.get_trait(TRAIT_MATURATION)
	var/obj/machinery/portable_atmospherics/hydroponics/tray = allocate(/obj/machinery/portable_atmospherics/hydroponics, T)
	refresh_flush()
	TEST_ASSERT_NULL(dq_dr_find(tray, "[plant_icon]-1"), "an empty tray shows no plant")
	proto_set(tray, nameof(tray.seed), seed)
	tray.set_health(seed.get_trait(TRAIT_ENDURANCE))
	tray.set_age(1)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(tray, "[plant_icon]-1"), "a seedling shows its first stage")
	TEST_ASSERT(findtext(tray.name, seed.seed_name), "and the tray is named for it: [tray.name]")
	tray.set_age(maturation)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(tray, "[plant_icon]-[stages]"), "a mature plant shows its last stage")
	TEST_ASSERT_NULL(dq_dr_find(tray, "[plant_icon]-1"), "and not its first")
	tray.set_harvest(1)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(tray, "over_harvest3"), "a plant ready to pick lights its alert")
	tray.set_waterlevel(0)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(tray, "over_lowwater3"), "a dry tray lights its water alert")
	tray.set_dead(1)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(tray, "[plant_icon]-dead"), "a dead plant shows dead")
	tray.set_closed_system(TRUE)
	refresh_flush()
	TEST_ASSERT_NOTNULL(dq_dr_find(tray, "hydrocover"), "a closed tray shows its cover")

// ---- the builder draws underlays ----

/obj/dq_draw_underlay
	name = "draw underlay"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/mode = 0

TRACKED(/obj/dq_draw_underlay, mode)

/obj/dq_draw_underlay/draw(datum/look/look)
	..()
	look.underlay("under-[mode]", when = mode > 0)
	look.overlay("over-[mode]")

/datum/unit_test/dq_draw_reagents_builder_draws_and_takes_back_underlays

/datum/unit_test/dq_draw_reagents_builder_draws_and_takes_back_underlays/Run()
	var/obj/dq_draw_underlay/A = allocate(/obj/dq_draw_underlay, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(length(A.underlays), 0, "a draw that asks for none has none")
	A.set_mode(2)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(A.underlays), 1, "an underlay it asks for is drawn beneath")
	TEST_ASSERT_NOTNULL(dq_dr_find(A, "under-2", TRUE), "the state it named")
	A.set_mode(3)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(A.underlays), 1, "a new look replaces it")
	TEST_ASSERT_NOTNULL(dq_dr_find(A, "under-3", TRUE), "with the new one")
	A.set_mode(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(A.underlays), 0, "a look without it takes it back")

// ---- a draw that throws does not leave the engine inside an output ----

/obj/dq_draw_throws
	name = "draw throws"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/boom = FALSE

TRACKED(/obj/dq_draw_throws, boom)

/obj/dq_draw_throws/draw(datum/look/look)
	..()
	if(boom)
		CRASH("dq_draw_throws: drawn on purpose")
	look.overlay("over-fine")

/datum/unit_test/dq_draw_reagents_a_throwing_draw_leaves_the_next_output_working

/datum/unit_test/dq_draw_reagents_a_throwing_draw_leaves_the_next_output_working/Run()
	var/obj/dq_draw_throws/A = allocate(/obj/dq_draw_throws, test_floor())
	var/obj/dq_draw_throws/B = allocate(/obj/dq_draw_throws, test_floor())
	refresh_flush()
	A.boom = TRUE
	var/threw = FALSE
	try
		refresh_look(A)
	catch(var/exception/fault)
		threw = TRUE
	TEST_ASSERT(threw, "the draw's runtime reaches the caller")
	TEST_ASSERT_EQUAL(GLOB.derived_evaluating, 0, "and the engine is not left inside an output")
	TEST_ASSERT(!OP_PURE_ACTIVE, "so a write after it is not reported as made inside one")
	A.boom = FALSE
	TEST_ASSERT_NOTNULL(refresh_look(B), "the next output evaluates")
	TEST_ASSERT_NOTNULL(refresh_look(A), "and the one that threw draws again once it stops")
