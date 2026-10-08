// The draw framework forms (doc/rewrite/final_api.html section 13): look.effect(), look.watch(), the look's single emissive blocker, and the mob look helpers (look.hat(), look.life_state()).

// ---- look.effect(): the work a look does besides drawing ----

/obj/dq_draw_effect
	name = "draw effect"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/mode = 0
	var/mirror = 0
	var/effects_seen = 0
	var/last_effect_value

TRACKED(/obj/dq_draw_effect, mode)
TRACKED(/obj/dq_draw_effect, mirror)

/obj/dq_draw_effect/draw(datum/look/look)
	..()
	look.overlay("mode-[mode]")
	look.effect(PROC_REF(note_effect), mode)

/obj/dq_draw_effect/proc/note_effect(value)
	effects_seen++
	last_effect_value = value
	set_mirror(value) // an effect may write tracked state: it runs outside the output

/datum/unit_test/dq_draw_effect_runs_when_the_look_applies

/datum/unit_test/dq_draw_effect_runs_when_the_look_applies/Run()
	var/turf/T = test_floor()
	var/obj/dq_draw_effect/A = allocate(/obj/dq_draw_effect, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.effects_seen, 1, "the first look applied runs its effect once")
	TEST_ASSERT_EQUAL(A.last_effect_value, 0, "with the arguments the draw gave it")
	TEST_ASSERT_EQUAL(A.mirror, 0, "an effect writes through a setter")
	changed(A)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.effects_seen, 1, "a redraw whose look did not change runs no effect")
	A.set_mode(2)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.effects_seen, 2, "a changed look runs it again")
	TEST_ASSERT_EQUAL(A.last_effect_value, 2, "with the new value")
	TEST_ASSERT_EQUAL(A.mirror, 2, "and the write it made stands")
	TEST_ASSERT(("mode-2" in A.look_overlays), "the draw's own layer is applied: [json_encode(A.look_overlays)]")

// ---- look.watch(): a draw that reads another entity ----

/obj/dq_draw_watched
	name = "draw watched"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/shown = 0

TRACKED(/obj/dq_draw_watched, shown)

/obj/dq_draw_watcher
	name = "draw watcher"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/obj/dq_draw_watched/other

/obj/dq_draw_watcher/draw(datum/look/look)
	..()
	look.watch(other)
	if(other)
		look.overlay("other-[other.shown]")

/datum/unit_test/dq_draw_watch_redraws_on_the_other_end

/datum/unit_test/dq_draw_watch_redraws_on_the_other_end/Run()
	var/turf/T = test_floor()
	var/obj/dq_draw_watched/B = allocate(/obj/dq_draw_watched, T)
	var/obj/dq_draw_watcher/A = allocate(/obj/dq_draw_watcher, T)
	refresh_flush()
	A.other = B
	changed(A)
	refresh_flush()
	TEST_ASSERT(("other-0" in A.look_overlays), "the draw read the other end: [json_encode(A.look_overlays)]")
	B.set_shown(3)
	refresh_flush()
	TEST_ASSERT(("other-3" in A.look_overlays), "a change on the other end redraws this one: [json_encode(A.look_overlays)]")
	A.other = null
	changed(A)
	refresh_flush()
	TEST_ASSERT(!length(B.rel_watchers), "a draw that stops reading the other end stops hearing it")
	TEST_ASSERT(!length(cap_engine_state_of(A)?.look_watching), "and keeps no subscription of its own")
	A.other = null

// ---- the look owns one emissive blocker ----

/proc/dq_draw_blocker_count(atom/A)
	. = 0
	for(var/layer in A.overlays)
		var/mutable_appearance/MA = new(layer)
		if(MA.plane == PLANE_EMISSIVE)
			.++

/datum/unit_test/dq_draw_lightpost_has_one_blocker

/datum/unit_test/dq_draw_lightpost_has_one_blocker/Run()
	var/turf/T = test_floor()
	var/obj/structure/lightpost/A = allocate(/obj/structure/lightpost, T)
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_draw_blocker_count(A), 1, "the first draw does not stack a second blocker")
	A.set_lit(FALSE)
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_draw_blocker_count(A), 1, "a redraw keeps the one blocker")
	A.set_festive(TRUE)
	A.set_lit(TRUE)
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_draw_blocker_count(A), 1, "and so does every change after")
	TEST_ASSERT(A.light_range > 0, "a lit lightpost lights")
	A.set_lit(FALSE)
	appearance_flush()
	TEST_ASSERT_EQUAL(A.light_range, 0, "an unlit one does not")

// ---- the mob look helpers ----

/datum/unit_test/dq_draw_mob_hat_is_drawn_from_the_hat

/datum/unit_test/dq_draw_mob_hat_is_drawn_from_the_hat/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/hyena/H = allocate(/mob/living/simple_mob/animal/hyena, T)
	var/obj/item/clothing/head/sombrero/hat = allocate(/obj/item/clothing/head/sombrero, T)
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_draw_hat_layers(H), 0, "a hyena with no hat draws no hat")
	rel_set(H, nameof(H.hat), hat)
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_draw_hat_layers(H), 1, "the hat it is given is drawn from the head icon")
	rel_take(H, nameof(H.hat))
	appearance_flush()
	TEST_ASSERT_EQUAL(dq_draw_hat_layers(H), 0, "and goes when it is taken off")

/proc/dq_draw_hat_layers(atom/A)
	. = 0
	for(var/layer in A.overlays)
		var/mutable_appearance/MA = new(layer)
		if(findtext("[MA.icon]", "head/mob.dmi"))
			.++

/datum/unit_test/dq_draw_life_state_follows_stat

/datum/unit_test/dq_draw_life_state_follows_stat/Run()
	var/turf/T = test_floor()
	var/mob/living/simple_mob/animal/hyena/H = allocate(/mob/living/simple_mob/animal/hyena, T)
	var/datum/look/look = new
	TEST_ASSERT_EQUAL(look.life_state(H, "live", "rest", "dead"), "live", "a conscious mob shows the living state")
	H.stat = UNCONSCIOUS
	TEST_ASSERT_EQUAL(look.life_state(H, "live", "rest", "dead"), "rest", "an unconscious one shows the resting state")
	TEST_ASSERT_EQUAL(look.life_state(H, "live", null, "dead"), initial(H.icon_state), "with no resting sprite it keeps its own")
	H.stat = DEAD
	TEST_ASSERT_EQUAL(look.life_state(H, "live", "rest", "dead"), "dead", "a dead one shows the dead state")
	H.stat = CONSCIOUS

// ---- dir: a draw that reads dir redraws when set_dir() changes it; look.offset() ----

/obj/dq_draw_facing
	name = "draw facing"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"

/obj/dq_draw_facing/draw(datum/look/look)
	..()
	look.overlay("facing-[dir]")
	if(dir == NORTH)
		look.offset(0, -32)

/datum/unit_test/dq_draw_dir_read_redraws_on_set_dir

/datum/unit_test/dq_draw_dir_read_redraws_on_set_dir/Run()
	var/turf/T = test_floor()
	var/obj/dq_draw_facing/A = allocate(/obj/dq_draw_facing, T)
	refresh_flush()
	A.set_dir(SOUTH)
	refresh_flush()
	TEST_ASSERT(("facing-[SOUTH]" in A.look_overlays), "the draw read the dir: [json_encode(A.look_overlays)]")
	A.set_dir(EAST)
	refresh_flush()
	TEST_ASSERT(("facing-[EAST]" in A.look_overlays), "a change of dir through set_dir() redraws: [json_encode(A.look_overlays)]")
	TEST_ASSERT(!("facing-[SOUTH]" in A.look_overlays), "and the old facing is gone")
	A.setDir(WEST)
	refresh_flush()
	TEST_ASSERT(("facing-[WEST]" in A.look_overlays), "setDir() is the same path: [json_encode(A.look_overlays)]")

/datum/unit_test/dq_draw_offset_follows_the_look

/datum/unit_test/dq_draw_offset_follows_the_look/Run()
	var/turf/T = test_floor()
	var/obj/dq_draw_facing/A = allocate(/obj/dq_draw_facing, T)
	refresh_flush()
	A.set_dir(NORTH)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.pixel_y, -32, "look.offset() moves the holder")
	A.set_dir(SOUTH)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.pixel_y, initial(A.pixel_y), "a draw that stops naming the offset gives the mapped one back")

/datum/unit_test/dq_draw_wall_bin_sits_in_its_wall

/datum/unit_test/dq_draw_wall_bin_sits_in_its_wall/Run()
	var/turf/T = test_floor()
	var/obj/machinery/disposal/wall/A = allocate(/obj/machinery/disposal/wall, T)
	refresh_flush()
	A.set_dir(NORTH)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.pixel_y, -32, "a wall bin facing north is offset into the wall")
	A.set_dir(EAST)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.pixel_x, -32, "turning it moves it to the wall it faces now")
	TEST_ASSERT_EQUAL(A.pixel_y, 0, "and out of the first one")

// ---- look.watch() and the proof types: the medical stand, the furnace ----

/datum/unit_test/dq_draw_medical_stand_follows_its_beaker

/datum/unit_test/dq_draw_medical_stand_follows_its_beaker/Run()
	var/turf/T = test_floor()
	var/obj/structure/medical_stand/S = allocate(/obj/structure/medical_stand, T)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, T)
	refresh_flush()
	rel_set(S, nameof(S.beaker), B)
	refresh_flush()
	TEST_ASSERT(("beaker" in S.look_overlays), "the beaker is drawn: [json_encode(S.look_overlays)]")
	TEST_ASSERT(("line" in S.look_overlays), "with the line not attached")
	var/before = S.look_key
	B.reagents.add_reagent(REAGENT_ID_WATER, 30)
	refresh_flush()
	TEST_ASSERT(S.look_key != before, "filling the beaker redraws the stand through the watch")
	rel_take(S, nameof(S.beaker))
	refresh_flush()
	TEST_ASSERT(!("beaker" in S.look_overlays), "and it goes when the beaker is taken")

/datum/unit_test/dq_draw_furnace_flip_and_turn_redraw

/datum/unit_test/dq_draw_furnace_flip_and_turn_redraw/Run()
	var/turf/T = test_floor()
	var/obj/machinery/reagent_refinery/furnace/F = allocate(/obj/machinery/reagent_refinery/furnace, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "furnace_l", "a furnace sinters to its left")
	F.set_filter_side(1)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "furnace_r", "the tracked side redraws it")
	var/before = F.look_key
	F.set_dir(EAST)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.dir, EAST, "it turned")
	TEST_ASSERT(F.look_key != before || !F.reagents.total_volume, "a turn redraws a furnace that shows a filling")
