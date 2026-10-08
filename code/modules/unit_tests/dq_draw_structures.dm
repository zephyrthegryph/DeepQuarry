// The structures, effects and HUD buttons that draw themselves from tracked state: closets and crates, the gun cabinet's contents, the vehicle cage, the cliff,
// the railing, the janitorial cart, the bonfire's fuel, blood and its kin, and the ability buttons. Each test moves the state a look reads and checks the look,
// with no update_icon() or changed() in between.

/// The icon_state of each overlay `A` shows now (a janitor mark, a gun, a door).
/datum/unit_test/proc/dq_structure_overlays(atom/A)
	. = list()
	for(var/overlay in A.overlays)
		var/mutable_appearance/MA = new(overlay)
		. += "[MA.icon_state]"

/// How many of `list` are `entry`.
/datum/unit_test/proc/dq_count_of(list/entries, entry)
	. = 0
	for(var/found in entries)
		if(found == entry)
			.++

// ---- closets and crates ----

/// A closet opening and closing: the door state follows the tracked `opened`, and a weld shows on the shut one.
/datum/unit_test/dq_draw_closet_opening_redraws

/datum/unit_test/dq_draw_closet_opening_redraws/Run()
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(closet.icon_state, "closed_unlocked", "a shut closet draws its shut state")
	TEST_ASSERT(closet.icon != initial(closet.icon), "from the icon of its decal decl, not the mapped one")
	TEST_ASSERT(closet.open(), "the closet opens")
	refresh_flush()
	TEST_ASSERT_EQUAL(closet.icon_state, "open", "an open closet draws its open state with no update_icon() call")
	TEST_ASSERT(closet.close(), "the closet shuts")
	refresh_flush()
	TEST_ASSERT_EQUAL(closet.icon_state, "closed_unlocked", "and shut again")
	set_welded(closet, TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(closet.icon_state, "closed_unlocked_welded", "a welded closet draws the welded state")

/// A secure crate locking and unlocking: the lock key is the one state there is, and a broken lock shows emagged.
/datum/unit_test/dq_draw_secure_crate_lock_redraws

/datum/unit_test/dq_draw_secure_crate_lock_redraws/Run()
	var/obj/structure/closet/crate/secure/crate = allocate(/obj/structure/closet/crate/secure, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(crate.icon_state, "closed_locked", "a crate starts locked")
	crate.force_lock(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(crate.icon_state, "closed_unlocked", "unlocking it draws the unlocked state")
	crate.force_lock(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(crate.icon_state, "closed_locked", "and locking it draws the locked one again")
	crate.set_broken(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(crate.icon_state, "closed_emagged", "a broken lock shows emagged")

/// The secure locker draws the lock the same way, and the egg draws its own states.
/datum/unit_test/dq_draw_locker_and_egg_states

/datum/unit_test/dq_draw_locker_and_egg_states/Run()
	var/obj/structure/closet/secure_closet/locker = allocate(/obj/structure/closet/secure_closet, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(locker.icon_state, "closed_locked", "a locker starts locked")
	locker.force_lock(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(locker.icon_state, "closed_unlocked", "and unlocking it draws it")
	var/obj/structure/closet/secure_closet/egg/egg = allocate(/obj/structure/closet/secure_closet/egg/unathi, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(egg.icon_state, egg.icon_closed, "an egg draws its shut state")
	egg.set_opened(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(egg.icon_state, egg.icon_opened, "and its open one")

// ---- the gun cabinet ----

/// The cabinet draws its contents without making them: declared guns are counted from the slot and none of them is materialized.
/datum/unit_test/dq_draw_guncabinet_shows_declared_guns_unmade

/datum/unit_test/dq_draw_guncabinet_shows_declared_guns_unmade/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/secure_closet/guncabinet/sidearm/cabinet = allocate(/obj/structure/closet/secure_closet/guncabinet/sidearm, T)
	refresh_flush()
	var/made_before = length(cabinet.contents)
	var/list/overlays_now = dq_structure_overlays(cabinet)
	TEST_ASSERT_EQUAL(dq_count_of(overlays_now, "laser"), 3, "four declared energy guns show three laser guns on the shelf: [json_encode(overlays_now)]")
	TEST_ASSERT_EQUAL(dq_count_of(overlays_now, "projectile"), 0, "and no projectile gun")
	TEST_ASSERT("door" in overlays_now, "behind a shut door")
	TEST_ASSERT("locked" in overlays_now, "that shows locked")
	TEST_ASSERT_EQUAL(length(cabinet.contents), made_before, "the draw made no gun")
	var/list/kinds = cabinet.slot_kinds(CONTAINER_SLOT_INTERIOR, /obj/item/gun)
	TEST_ASSERT_EQUAL(length(kinds), 4, "the slot answers four guns by type: [json_encode(kinds)]")
	cabinet.latent_discard()

/// A gun going in or out redraws the cabinet through the slot's occupancy, and opening it shows only the open door.
/datum/unit_test/dq_draw_guncabinet_follows_its_slot

/datum/unit_test/dq_draw_guncabinet_follows_its_slot/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/secure_closet/guncabinet/cabinet = allocate(/obj/structure/closet/secure_closet/guncabinet, T)
	refresh_flush()
	var/list/overlays_now = dq_structure_overlays(cabinet)
	TEST_ASSERT_EQUAL(dq_count_of(overlays_now, "laser") + dq_count_of(overlays_now, "projectile"), 0, "an empty cabinet shows no gun: [json_encode(overlays_now)]")
	var/obj/item/gun/energy/gun/laser_gun = allocate(/obj/item/gun/energy/gun, T)
	TEST_ASSERT(move_into(cabinet, null, laser_gun), "an energy gun goes in")
	refresh_flush()
	overlays_now = dq_structure_overlays(cabinet)
	TEST_ASSERT_EQUAL(dq_count_of(overlays_now, "laser"), 1, "the cabinet shows it: [json_encode(overlays_now)]")
	var/obj/item/gun/projectile/shotgun/pump/rifle/rifle = allocate(/obj/item/gun/projectile/shotgun/pump/rifle, T)
	TEST_ASSERT(move_into(cabinet, null, rifle), "a projectile gun goes in")
	refresh_flush()
	overlays_now = dq_structure_overlays(cabinet)
	TEST_ASSERT_EQUAL(dq_count_of(overlays_now, "projectile"), 1, "and shows beside it: [json_encode(overlays_now)]")
	cabinet.force_lock(FALSE)
	refresh_flush()
	TEST_ASSERT(("open" in dq_structure_overlays(cabinet)), "the unlocked cabinet shows its open lamp")
	TEST_ASSERT(cabinet.open(), "the unlocked cabinet opens")
	refresh_flush()
	overlays_now = dq_structure_overlays(cabinet)
	TEST_ASSERT(("door_open" in overlays_now), "an open cabinet shows its open door: [json_encode(overlays_now)]")
	TEST_ASSERT_EQUAL(dq_count_of(overlays_now, "laser") + dq_count_of(overlays_now, "projectile"), 0, "and no gun")

/// A declared gun added to a cabinet that holds nothing made redraws it too: the latent entry publishes the slot's occupancy.
/datum/unit_test/dq_draw_guncabinet_hears_a_latent_entry

/datum/unit_test/dq_draw_guncabinet_hears_a_latent_entry/Run()
	var/obj/structure/closet/secure_closet/guncabinet/cabinet = allocate(/obj/structure/closet/secure_closet/guncabinet, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(dq_count_of(dq_structure_overlays(cabinet), "laser"), 0, "an empty cabinet shows no gun")
	var/datum/latent_entry/entry = cabinet.latent_add(/obj/item/gun/energy/gun, 2)
	if(!entry)
		return // the gun cannot be held declared here: the real-gun test covers the redraw
	refresh_flush()
	TEST_ASSERT_EQUAL(dq_count_of(dq_structure_overlays(cabinet), "laser"), 2, "two declared guns are two laser guns on the shelf without making any: [json_encode(dq_structure_overlays(cabinet))]")
	TEST_ASSERT_EQUAL(cabinet.latent_count(CONTAINER_SLOT_INTERIOR), 2, "and both are still declared")

/// look.contents_of(): the types held, real and declared, filtered by type, with nothing made.
/datum/unit_test/dq_draw_slot_kinds_count_declared_and_real

/datum/unit_test/dq_draw_slot_kinds_count_declared_and_real/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/secure_closet/guncabinet/sidearm/cabinet = allocate(/obj/structure/closet/secure_closet/guncabinet/sidearm, T)
	var/list/before = cabinet.slot_kinds(CONTAINER_SLOT_INTERIOR, /atom/movable)
	TEST_ASSERT_EQUAL(length(before), 4, "a cabinet that has not been asked yet answers from its declared guns: [json_encode(before)]")
	var/obj/item/gun/projectile/shotgun/pump/rifle/rifle = allocate(/obj/item/gun/projectile/shotgun/pump/rifle, T)
	TEST_ASSERT(move_into(cabinet, null, rifle), "a real gun goes in")
	var/list/after = cabinet.slot_kinds(CONTAINER_SLOT_INTERIOR, /obj/item/gun/projectile)
	TEST_ASSERT_EQUAL(length(after), 1, "and the real one is counted by its type, the declared ones filtered out: [json_encode(after)]")
	TEST_ASSERT_EQUAL(length(cabinet.slot_kinds(CONTAINER_SLOT_INTERIOR, /obj/item/gun/energy)), 4, "the energy guns are still the declared four")
	cabinet.latent_discard()

// ---- the vehicle cage ----

/// The cage's frame follows the vehicle's paint, and the caged vehicle is drawn behind it.
/datum/unit_test/dq_draw_vehicle_cage_follows_paint_and_vehicle

/datum/unit_test/dq_draw_vehicle_cage_follows_paint_and_vehicle/Run()
	var/obj/structure/vehiclecage/cage = allocate(/obj/structure/vehiclecage, test_floor())
	refresh_flush()
	var/before = cage.rx?.look_key
	TEST_ASSERT(before, "the cage drew")
	cage.set_paint_color("#ff0000")
	refresh_flush()
	TEST_ASSERT(cage.rx?.look_key != before, "a new paint colour redraws the frame")
	before = cage.rx?.look_key
	var/obj/vehicle/bike/bike = allocate(/obj/vehicle/bike, get_step(test_floor(), NORTH))
	bike.forceMove(cage)
	refresh_flush()
	TEST_ASSERT(cage.rx?.look_key != before, "a vehicle going into the cage redraws it with the vehicle shown")

// ---- the cliff, the railing, the cart ----

/// A cliff is drawn from its facing and kind: turning it or picking its variant draws another state with no call.
/datum/unit_test/dq_draw_cliff_follows_dir_and_variant

/datum/unit_test/dq_draw_cliff_follows_dir_and_variant/Run()
	var/obj/structure/cliff/cliff = allocate(/obj/structure/cliff, test_floor())
	cliff.set_dir(EAST)
	cliff.set_icon_variant("b")
	refresh_flush()
	TEST_ASSERT_EQUAL(cliff.icon_state, "cliff-[EAST]b", "the state names the facing and the variant")
	cliff.set_dir(WEST)
	refresh_flush()
	TEST_ASSERT_EQUAL(cliff.icon_state, "cliff-[WEST]b", "turning it draws the other state")
	cliff.set_corner(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(cliff.icon_state, "cliff-[WEST]b-corner", "a corner adds its suffix")

/// A railing joins a railing beside it: the joined sides are drawn, and one leaving takes them back.
/datum/unit_test/dq_draw_railing_joins_neighbours

/datum/unit_test/dq_draw_railing_joins_neighbours/Run()
	var/turf/T = test_floor()
	var/obj/structure/railing/rail = allocate(/obj/structure/railing, T)
	rail.set_dir(NORTH)
	var/turf/beside = get_step(T, turn(NORTH, 90))
	var/obj/structure/railing/neighbour = allocate(/obj/structure/railing, beside)
	neighbour.set_dir(NORTH)
	refresh_flush()
	TEST_ASSERT_EQUAL(rail.icon_state, "railing1", "a railing facing the same way beside it joins: it draws the joined state")
	var/before = rail.rx?.look_key
	neighbour.set_anchored(FALSE)
	refresh_flush()
	TEST_ASSERT(rail.rx?.look_key != before, "the neighbour coming loose redraws it")
	TEST_ASSERT_EQUAL(rail.icon_state, "railing0", "and it is plain again")

/// The janitorial cart shows what hangs on it: gear arriving through a relation and the signs counter both redraw.
/datum/unit_test/dq_draw_janitorial_cart_shows_its_gear

/datum/unit_test/dq_draw_janitorial_cart_shows_its_gear/Run()
	var/turf/T = test_floor()
	var/obj/structure/janitorialcart/cart = allocate(/obj/structure/janitorialcart, T)
	refresh_flush()
	TEST_ASSERT(!("cart_mop" in dq_structure_overlays(cart)), "a bare cart has no mop")
	var/obj/item/mop/mop = allocate(/obj/item/mop, T)
	rel_set(cart, nameof(cart.mymop), mop)
	refresh_flush()
	TEST_ASSERT(("cart_mop" in dq_structure_overlays(cart)), "a mop on it is drawn")
	cart.set_signs(2)
	refresh_flush()
	TEST_ASSERT(("cart_sign2" in dq_structure_overlays(cart)), "two signs draw their state")
	rel_take(cart, nameof(cart.mymop))
	refresh_flush()
	TEST_ASSERT(!("cart_mop" in dq_structure_overlays(cart)), "taking the mop off takes it from the picture")

// ---- the bonfire's fuel ----

/// The bonfire burns what is in its fuel slot: logs going in redraw it from warm to hot with no call.
/datum/unit_test/dq_draw_bonfire_follows_its_fuel

/datum/unit_test/dq_draw_bonfire_follows_its_fuel/Run()
	var/turf/T = test_floor()
	var/obj/structure/bonfire/fire = allocate(/obj/structure/bonfire, T)
	fire.set_burning(TRUE)
	refresh_flush()
	TEST_ASSERT(("bonfire_warm" in dq_structure_overlays(fire)), "a burning fire with no fuel is warm: [json_encode(dq_structure_overlays(fire))]")
	for(var/i in 1 to 6)
		var/obj/item/stack/material/log/log = allocate(/obj/item/stack/material/log, T)
		TEST_ASSERT(move_into(fire, null, log), "a log goes in")
	refresh_flush()
	TEST_ASSERT_EQUAL(fire.get_fuel_amount(), 6, "six logs are six units of fuel")
	TEST_ASSERT(("bonfire_hot" in dq_structure_overlays(fire)), "and the fire is hot: [json_encode(dq_structure_overlays(fire))]")

// ---- blood and the other cleanable decals ----

/// Blood is drawn in its colour; a new colour redraws it, drying darkens it and gives it its dried name.
/datum/unit_test/dq_draw_blood_follows_colour_and_drying

/datum/unit_test/dq_draw_blood_follows_colour_and_drying/Run()
	var/obj/effect/decal/cleanable/blood/blood = allocate(/obj/effect/decal/cleanable/blood, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(lowertext(blood.color), lowertext(blood.basecolor), "blood is its colour")
	TEST_ASSERT(("janhud[blood.hud_variant]" in dq_structure_overlays(blood)), "with its janitor HUD mark")
	blood.set_basecolor("#00ff00")
	refresh_flush()
	TEST_ASSERT_EQUAL(blood.color, "#00ff00", "a new colour is drawn at once")
	blood.set_synthblood(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(blood.name, "synthetic blood", "synthetic blood goes by its name")
	blood.dry()
	refresh_flush()
	TEST_ASSERT_EQUAL(blood.name, blood.dryname, "dried blood goes by the dried name")
	TEST_ASSERT(blood.color != "#00ff00", "and is darker")

/// Gibs are tinted by the blood with the flesh over them in its own colour.
/datum/unit_test/dq_draw_gibs_show_blood_and_flesh

/datum/unit_test/dq_draw_gibs_show_blood_and_flesh/Run()
	var/obj/effect/decal/cleanable/blood/gibs/gibs = allocate(/obj/effect/decal/cleanable/blood/gibs, test_floor())
	refresh_flush()
	var/list/overlays_now = dq_structure_overlays(gibs)
	TEST_ASSERT(("[gibs.icon_state]_flesh" in overlays_now), "the flesh is an overlay: [json_encode(overlays_now)]")
	var/before = gibs.rx?.look_key
	gibs.set_fleshcolor("#123456")
	refresh_flush()
	TEST_ASSERT(gibs.rx?.look_key != before, "a new flesh colour redraws the gibs")
	before = gibs.rx?.look_key
	gibs.set_basecolor("#654321")
	refresh_flush()
	TEST_ASSERT_EQUAL(gibs.color, "#654321", "and a new blood colour tints them")
	TEST_ASSERT(gibs.rx?.look_key != before, "and redraws them")

// ---- the ability buttons ----

/// The ability master shows open or closed from its tracked flag, and hides while it has no abilities.
/datum/unit_test/dq_draw_ability_master_follows_showing

/datum/unit_test/dq_draw_ability_master_follows_showing/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/atom/movable/screen/movable/ability_master/master = allocate(/atom/movable/screen/movable/ability_master, user)
	refresh_flush()
	TEST_ASSERT(master.closed_state in dq_structure_overlays(master), "a closed master shows its closed state")
	TEST_ASSERT_EQUAL(master.invisibility, INVISIBILITY_ABSTRACT, "and is hidden with nothing to show")
	master.set_showing(TRUE)
	refresh_flush()
	TEST_ASSERT(master.open_state in dq_structure_overlays(master), "an opened one shows its open state with no update_icon() call")
	var/atom/movable/screen/ability/button = allocate(/atom/movable/screen/ability, null)
	button.set_ability_icon_state("ling_revive")
	rel_add(master, nameof(master.ability_objects), button)
	refresh_flush()
	TEST_ASSERT_EQUAL(master.invisibility, INVISIBILITY_NONE, "an ability makes the master visible")
	refresh_flush()
	TEST_ASSERT(("ling_revive" in dq_structure_overlays(button)), "and the button draws its ability icon")
