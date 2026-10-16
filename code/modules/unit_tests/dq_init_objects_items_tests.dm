// Native item initialization: real state, rejection and destruction paths.
/datum/unit_test/dq_init_objects_items

/datum/unit_test/dq_init_objects_items/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/pipe_painter/P = allocate(/obj/item/pipe_painter, T)
	TEST_ASSERT(length(P.modes) > 0, "the real pipe-colour catalogue is populated")
	TEST_ASSERT(P.mode in P.modes, "the initial native roll chooses a real pipe colour")
	var/obj/item/kit/suit/rig/debug/K = allocate(/obj/item/kit/suit/rig/debug, T)
	TEST_ASSERT_EQUAL(K.new_name, "debug suit", "the debug kit retains its initial replacement name")
	TEST_ASSERT_EQUAL(K.new_desc, "This is a test", "the debug kit retains its initial replacement description")
	TEST_ASSERT_EQUAL(K.new_icon, "debug", "the debug kit retains its replacement sprite")
	TEST_ASSERT_EQUAL(K.new_icon_file, CUSTOM_ITEM_OBJ, "the debug kit retains its object sprite sheet")
	TEST_ASSERT_EQUAL(K.new_icon_override_file, CUSTOM_ITEM_MOB, "the debug kit retains its worn sprite sheet")
	var/obj/item/owner = allocate(/obj/item, T)
	var/obj/item/storage/internal/S = allocate(/obj/item/storage/internal, owner)
	TEST_ASSERT(!QDELETED(S), "an actual item owner keeps its internal storage")
	TEST_ASSERT_EQUAL(S.master_item(), owner, "native setup binds the exact typed owner")
	TEST_ASSERT_EQUAL(S.name, owner.name, "native setup inherits the actual owner name")
	var/obj/item/storage/internal/invalid = allocate(/obj/item/storage/internal, T)
	TEST_ASSERT(QDELETED(invalid), "a turf-owned internal storage is rejected without binding an invalid typed link")
	qdel(owner)
	TEST_ASSERT(QDELETED(S), "deleting the owner deletes its real contained storage")
	var/obj/item/commcard/head/card = allocate(/obj/item/commcard/head, T)
	TEST_ASSERT_EQUAL(GLOB.radio_listen_tuned[card], 1435, "the head cartridge listens on the historical display frequency")
	qdel(card)
	TEST_ASSERT(!(card in GLOB.radio_listen_tuned), "destruction removes the cartridge's native radio subscription")

/datum/unit_test/dq_init_objects_radio

/datum/unit_test/dq_init_objects_radio/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/radio/headset/headset_eng/H = allocate(/obj/item/radio/headset/headset_eng, T)
	TEST_ASSERT_NOTNULL(H.keyslot2, "declared headset keys exist before channel setup")
	TEST_ASSERT(length(H.keyslot2.channels) > 0, "the real engineering key declares channels")
	for(var/channel in H.keyslot2.channels)
		TEST_ASSERT(channel in H.channels, "setup includes every actual engineering key channel")
		TEST_ASSERT_EQUAL(H.channels[channel], H.keyslot2.channels[channel], "setup retains each key channel's access value")
	TEST_ASSERT(H.radio_connection, "materialization registers the main radio after initial setup")
	TEST_ASSERT(length(H.secure_radio_connections) > 0, "materialization registers the prepared secure channels")
	var/obj/item/radio/dq_init_low/low = allocate(/obj/item/radio/dq_init_low, T)
	TEST_ASSERT_EQUAL(low.frequency, sanitize_frequency(RADIO_LOW_FREQ - 2, RADIO_LOW_FREQ, RADIO_HIGH_FREQ), "initial derivation preserves low-frequency sanitization")
	var/obj/item/radio/dq_init_high/high = allocate(/obj/item/radio/dq_init_high, T)
	TEST_ASSERT_EQUAL(high.frequency, sanitize_frequency(RADIO_HIGH_FREQ + 2, RADIO_LOW_FREQ, RADIO_HIGH_FREQ), "initial derivation preserves high-frequency sanitization")

/obj/item/radio/dq_init_low
	frequency = RADIO_LOW_FREQ - 2

/obj/item/radio/dq_init_high
	frequency = RADIO_HIGH_FREQ + 2

/datum/unit_test/dq_init_objects_device_setup

/datum/unit_test/dq_init_objects_device_setup/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/gps/G = allocate(/obj/item/gps, H)
	TEST_ASSERT_EQUAL(G.holder_ref(), H, "initial setup subscribes a GPS created inside its actual mob holder")
	TEST_ASSERT_NOTNULL(G.compass, "the compass exists before holder setup")
	TEST_ASSERT(observer_count(H, /datum/notice/movable_attempted_move) > 0, "the GPS subscribes to its real holder's movement")
	var/before = observer_count(H, /datum/notice/movable_attempted_move)
	qdel(G)
	TEST_ASSERT_EQUAL(observer_count(H, /datum/notice/movable_attempted_move), before - 1, "deletion releases exactly the GPS movement observer")
	var/obj/item/perfect_tele/P = allocate(/obj/item/perfect_tele, T)
	TEST_ASSERT(P.beacons_left > 0, "the real translocator starts with deployable beacons")
	TEST_ASSERT("New Beacon" in P.radial_images, "initial setup builds the actual deploy-beacon radial entry")
	TEST_ASSERT(istype(P.radial_images["New Beacon"], /image), "the radial entry is a real presentation image")

/datum/unit_test/dq_init_objects_uav_trail

/datum/unit_test/dq_init_objects_uav_trail/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/uav/U = allocate(/obj/item/uav, T)
	var/datum/effect/effect/system/ion_trail_follow/trail = U.ion_trail
	TEST_ASSERT_NOTNULL(trail, "native ownership creates the actual UAV trail")
	TEST_ASSERT_EQUAL(trail.holder, U, "the trail's existing constructor attaches it to its exact UAV")
	TEST_ASSERT_EQUAL(trail.oldposition(), T, "the existing constructor records its initial turf")
	TEST_ASSERT(!trail.on && !trail.processing, "the new UAV's trail remains stopped without scheduling work")
	qdel(U)
	TEST_ASSERT(QDELETED(trail), "native ownership destroys the trail with its UAV")

/datum/unit_test/dq_init_objects_spectral_goggles

/datum/unit_test/dq_init_objects_spectral_goggles/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/clothing/glasses/ghost/G = allocate(/obj/item/clothing/glasses/ghost)
	TEST_ASSERT_NOTNULL(GLOB.global_hud.heavy_whitense, "the real shared spectral overlay exists")
	TEST_ASSERT_EQUAL(G.overlay(), GLOB.global_hud.heavy_whitense, "ordinary spectral goggles retain their exact shared HUD overlay")
	TEST_ASSERT_NULL(G.overlay, "the native HUD profile does not store a redundant shared-screen reference")
	var/obj/item/clothing/glasses/ghost/advanced/A = allocate(/obj/item/clothing/glasses/ghost/advanced)
	TEST_ASSERT_NULL(A.overlay(), "advanced spectral goggles retain their clear-view subtype behavior")
	qdel(G)
	TEST_ASSERT(!QDELETED(GLOB.global_hud.heavy_whitense), "deleting glasses never destroys the shared HUD overlay")

/datum/unit_test/dq_init_objects_cigarette_brand

/datum/unit_test/dq_init_objects_cigarette_brand/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/storage/fancy/cigarettes/packet = allocate(/obj/item/storage/fancy/cigarettes)
	var/count = 0
	for(var/obj/item/clothing/mask/smokable/cigarette/C in packet.slot_contents(CONTAINER_SLOT_STORAGE))
		count++
		TEST_ASSERT_EQUAL(C.brand, packet.brand, "setup applies the pack brand to each actual starting cigarette")
		TEST_ASSERT(findtext(C.desc, " This one is "), "each actual starting cigarette gets its brand description")
	TEST_ASSERT_EQUAL(count, 6, "the real pack retains exactly its six branded starting cigarettes")

/datum/unit_test/dq_init_objects_mre

/datum/unit_test/dq_init_objects_mre/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/storage/box/tgmc_mre/meal = allocate(/obj/item/storage/box/tgmc_mre, T)
	var/components = 0
	for(var/obj/item/reagent_containers/food/snacks/tgmc_mre_component/C in contents_of(meal))
		components++
		TEST_ASSERT(C.flavor, "each actual meal component retains its constructor flavour")
		TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(C.seasoning), 1, "each actual meal component receives its one unit of seasoning")
	TEST_ASSERT_EQUAL(components, 4, "the meal creates exactly its entree, side, snack and dessert")
	var/obj/item/reagent_containers/food/snacks/tgmc_mre_component/dessert = allocate(/obj/item/reagent_containers/food/snacks/tgmc_mre_component, T, "choco bar")
	TEST_ASSERT_EQUAL(dessert.flavor, "choco bar", "native params apply the exact supplied flavour before seasoning")
	TEST_ASSERT_EQUAL(dessert.reagents.get_reagent_amount(REAGENT_ID_SUGAR), 1, "the supplied dessert receives exactly its initial sugar unit")

/datum/unit_test/dq_init_objects_shield_generator

/datum/unit_test/dq_init_objects_shield_generator/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/personal_shield_generator/loaded/P = allocate(/obj/item/personal_shield_generator/loaded, T)
	var/obj/item/cell/cell = P.bcell
	var/obj/item/gun/energy/gun/generator/gun = P.active_weapon
	TEST_ASSERT_NOTNULL(cell, "the loaded shield generator creates its real cell")
	TEST_ASSERT_NOTNULL(gun, "the native child factory creates its actual generator gun")
	TEST_ASSERT_EQUAL(gun.loc, P, "the real gun starts inside its generator")
	TEST_ASSERT_EQUAL(gun.shield_generator(), P, "the gun receives the exact generator constructor argument")
	TEST_ASSERT_EQUAL(gun.power_supply, cell, "post-parent setup shares the exact preexisting generator cell")
	TEST_ASSERT_EQUAL(P.bcell, cell, "gun initialization never replaces or deletes the generator cell")
	qdel(gun)
	TEST_ASSERT_NULL(P.active_weapon, "deleting the native owned gun clears its generator's link")
	TEST_ASSERT(!QDELETED(cell), "deleting the gun never deletes its borrowed generator cell")
	qdel(P)
	TEST_ASSERT(QDELETED(cell), "deleting the generator deletes its owned cell")
	var/obj/item/personal_shield_generator/empty = allocate(/obj/item/personal_shield_generator, T)
	TEST_ASSERT_NOTNULL(empty.active_weapon, "the empty generator still creates its gun")
	TEST_ASSERT_NULL(empty.active_weapon.power_supply, "an empty generator gun borrows no phantom cell")
	var/obj/item/gun/energy/gun/generator/empty_gun = empty.active_weapon
	qdel(empty)
	TEST_ASSERT(QDELETED(empty_gun), "deleting a generator deletes its actual native owned gun")
	var/obj/item/personal_shield_generator/belt/belt = allocate(/obj/item/personal_shield_generator/belt, T)
	TEST_ASSERT_NULL(belt.active_weapon, "the no-weapon belt subtype creates no gun")
	var/obj/item/personal_shield_generator/dq_init_custom/custom = allocate(/obj/item/personal_shield_generator/dq_init_custom, T)
	TEST_ASSERT(istype(custom.active_weapon, /obj/item/gun/energy/gun/generator/dq_init_custom), "the factory preserves a supplied gun subtype path")
	TEST_ASSERT_EQUAL(custom.active_weapon.shield_generator(), custom, "a supplied gun subtype receives the exact constructor owner")

/obj/item/personal_shield_generator/dq_init_custom
	active_weapon = /obj/item/gun/energy/gun/generator/dq_init_custom

/obj/item/gun/energy/gun/generator/dq_init_custom

/datum/unit_test/dq_init_objects_sandbags

/datum/unit_test/dq_init_objects_sandbags/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/stack/sandbags/S = allocate(/obj/item/stack/sandbags, run_loc_floor_bottom_left, 20)
	TEST_ASSERT_EQUAL(S.get_amount(), 20, "the stack parent applies the real constructor amount before setup")
	TEST_ASSERT_EQUAL(S.slowdown, 2, "setup derives initial slowdown from the completed stack amount")
	TEST_ASSERT_EQUAL(S.recipes, GLOB.sandbag_recipes, "the bag retains its exact shared recipe table")
	TEST_ASSERT(length(S.recipes) > 0, "the real shared recipe table is populated")
	S.set_amount(10)
	TEST_ASSERT_EQUAL(S.slowdown, 1, "the existing amount setter still updates slowdown after creation")

/datum/unit_test/dq_init_objects_stack_amounts

/datum/unit_test/dq_init_objects_stack_amounts/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/stack/sandbags/full = allocate(/obj/item/stack/sandbags, T, -1)
	TEST_ASSERT_EQUAL(full.amount, full.max_amount, "a negative constructor amount still creates a full bounded stack")
	var/obj/item/stack/sandbags/zero = allocate(/obj/item/stack/sandbags, T, 0)
	TEST_ASSERT(!QDELETED(zero), "an explicitly zero constructor amount keeps the original no-limits semantics")
	TEST_ASSERT_EQUAL(zero.amount, 0, "the constructor retains an explicit zero")
	var/obj/item/stack/unbounded = allocate(/obj/item/stack, T, -1)
	TEST_ASSERT_EQUAL(unbounded.amount, 1, "negative construction on an unbounded base stack falls back to one")
	TEST_ASSERT_EQUAL(unbounded.stacktype, /obj/item/stack, "the default stack merge type is its actual concrete type")
	TEST_ASSERT_EQUAL(unbounded.sellable_type, /datum/sellable/material_stack, "the initial stack sale profile is retained")
	var/obj/item/stack/material/phoron/material_stack = allocate(/obj/item/stack/material/phoron, T, 7)
	TEST_ASSERT_NOTNULL(material_stack.material, "the real material parent resolves its material after amount application")
	TEST_ASSERT_EQUAL(material_stack.amount, 7, "the real material stack retains the constructor amount")
	TEST_ASSERT_EQUAL(material_stack.stacktype, material_stack.material.stack_type, "descendant material initialization retains its own merge type after the one-time default")
	TEST_ASSERT_EQUAL(material_stack.item_state, initial(material_stack.icon_state), "a variant stack retains the plain initial in-hand sprite")
	var/obj/item/stack/dq_init_defaults/mapped = allocate(/obj/item/stack/dq_init_defaults, T, 3)
	TEST_ASSERT_EQUAL(mapped.item_state, "mapped-hand", "a no-variants stack preserves its supplied in-hand default")
	TEST_ASSERT_EQUAL(mapped.stacktype, /obj/item/stack/sandbags, "a supplied merge type survives initial derivation")
	TEST_ASSERT_EQUAL(mapped.sellable_type, /datum/sellable, "a supplied sale profile still wins over the stack fallback")

/obj/item/stack/dq_init_defaults
	max_amount = 10
	item_state = "mapped-hand"
	stacktype = /obj/item/stack/sandbags
	sellable_type = /datum/sellable
