// Constructor regressions for declared clothing setup and ancestor order.
/datum/unit_test/dq_a7_initialization
	abstract_type = /datum/unit_test/dq_a7_initialization

/datum/unit_test/dq_a7_initialization/New()
	. = ..()
	dview(0, test_floor())

/datum/unit_test/dq_a7_initialization/proc/scope_setup()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)

/datum/unit_test/dq_a7_initialization/ranger_ancestor_order/Run()
	scope_setup()
	var/obj/item/clothing/shoes/boots/ranger/B = allocate(/obj/item/clothing/shoes/boots/ranger/green, test_floor())
	TEST_ASSERT_EQUAL(B.name, "green ranger boots", "The real subtype supplies its colour before setup finishes")
	TEST_ASSERT_EQUAL(length(B.inside_emotes), 4, "The ancestor supplies every shoe movement emote")
	for(var/emote in B.inside_emotes)
		TEST_ASSERT(findtext(emote, "ranger boots"), "The emote contains the constructor shoe name")
		TEST_ASSERT(!findtext(emote, "green ranger boots"), "Ancestor emotes capture the old name before the child adds its colour")

/datum/unit_test/dq_a7_initialization/material_identity/Run()
	scope_setup()
	var/obj/item/clothing/accessory/bracelet/material/B = allocate(/obj/item/clothing/accessory/bracelet/material/wood, test_floor())
	var/obj/item/clothing/accessory/ring/material/R = allocate(/obj/item/clothing/accessory/ring/material/gold, test_floor())
	TEST_ASSERT_NOTNULL(B.material, "The actual bracelet constructor resolves its forced material")
	TEST_ASSERT_EQUAL(B.name, "[B.material.display_name] bracelet", "Bracelet setup follows material resolution")
	TEST_ASSERT_EQUAL(lowertext(B.color), lowertext(B.material.icon_colour), "The bracelet has its material colour when returned")
	TEST_ASSERT_NOTNULL(R.material, "The actual ring constructor resolves its forced material")
	TEST_ASSERT_EQUAL(R.name, "[R.material.display_name] ring", "Ring setup follows material resolution")
	TEST_ASSERT_EQUAL(lowertext(R.color), lowertext(R.material.icon_colour), "The ring has its material colour when returned")

/datum/unit_test/dq_a7_initialization/datajack_storage/Run()
	scope_setup()
	var/obj/item/rig_module/datajack/A = allocate(/obj/item/rig_module/datajack, test_floor())
	var/obj/item/rig_module/datajack/B = allocate(/obj/item/rig_module/datajack, test_floor())
	TEST_ASSERT(islist(A.stored_research) && islist(B.stored_research), "Both real modules finish their per-instance storage setup")
	A.stored_research["probe"] = TRUE
	TEST_ASSERT(!B.stored_research["probe"], "Independent modules do not share mutable research storage")

/datum/unit_test/dq_a7_initialization/rig_systems/Run()
	scope_setup()
	var/obj/item/rig/R = allocate(/obj/item/rig, test_floor())
	TEST_ASSERT_NOTNULL(R.power_system, "The actual rig owns its power subsystem before setup")
	TEST_ASSERT_NOTNULL(R.component_registry, "The actual rig owns its component registry before setup")
	TEST_ASSERT_EQUAL(R.power_system.thermostat, R.thermostat, "Power settings are copied before callers receive the rig")
	TEST_ASSERT_EQUAL(R.power_system.offline_slowdown, R.offline_slowdown, "The durable offline setting reaches the subsystem")
	TEST_ASSERT(!R.locked, "A rig without access requirements starts unlocked")
	TEST_ASSERT_NOTNULL(R.chest, "The registry creates the configured real chest")
	TEST_ASSERT_NOTNULL(R.cell, "The registry creates the configured real cell")
	TEST_ASSERT_EQUAL(R.chest.name, "[R.suit_type] [initial(R.chest.name)]", "Piece naming follows rig setup")

/datum/unit_test/dq_a7_initialization/helmet_refit/Run()
	scope_setup()
	var/obj/item/clothing/head/helmet/space/H = allocate(/obj/item/clothing/head/helmet/space, test_floor())
	TEST_ASSERT_EQUAL(H.sprite_sheets[SPECIES_TESHARI], 'icons/inventory/head/mob_teshari.dmi', "The exact base helmet receives its refitted sprite")

/datum/unit_test/dq_a7_initialization/fishing_slogan/Run()
	scope_setup()
	var/obj/item/clothing/head/fishing/H = allocate(/obj/item/clothing/head/fishing, test_floor())
	TEST_ASSERT(length(H.slogan) > 0, "The real constructor rolls a nonempty fishing slogan")
	TEST_ASSERT(H.hatsize >= 0 && H.hatsize <= 10, "The correlated slogan roll supplies the configured size")
	TEST_ASSERT(H.colourtype in list("green", "red", "blue", "yellow", "purple", "orange", "grey"), "The same roll supplies a valid hat hue")
	TEST_ASSERT_EQUAL(H.name, "\improper '[H.slogan]' hat", "Ordered setup names the hat after its actual slogan")
	TEST_ASSERT_EQUAL(H.desc, "A peaked cap with text reading '[H.slogan]'.", "The description agrees with the same rolled slogan")
	TEST_ASSERT_EQUAL(H.icon_state, "[H.colourtype]soft[H.hatsize]", "The initialized icon uses the correlated hue and size")
	TEST_ASSERT_EQUAL(H.item_state_slots[slot_head_str], H.icon_state, "The actual worn state matches the constructor icon")

/datum/unit_test/dq_a7_initialization/dark_glow/proc/restore_tile(x, y, z, original_type)
	var/turf/current = locate(x, y, z)
	if(current && current.type != original_type)
		current.ChangeTurf(original_type)

/datum/unit_test/dq_a7_initialization/dark_glow/Run()
	scope_setup()
	var/turf/T = test_floor()
	var/x = T.x
	var/y = T.y
	var/z = T.z
	var/original_type = T.type
	defer_cleanup(src, PROC_REF(restore_tile), x, y, z, original_type)
	// This dark tile has no flooring or dirty roll, and its parent initialization has no RNG draws.
	// Select real RNG seeds for both sides of the original 5% gate, then replay them through construction.
	for(var/should_glow in list(FALSE, TRUE))
		var/seed
		for(var/candidate in 1 to 1000)
			rand_seed(candidate)
			if(!!prob(5) == should_glow)
				seed = candidate
				break
		TEST_ASSERT(seed, "A deterministic seed exercises the requested real glow branch")
		rand_seed(seed)
		var/turf/current = locate(x, y, z)
		var/turf/simulated/floor/weird_things/dark/D = current.ChangeTurf(/turf/simulated/floor/weird_things/dark)
		TEST_ASSERT_EQUAL(length(D.overlays), should_glow ? 1 : 0, "Real initialization preserves the conditional glow effect")
		restore_tile(x, y, z, original_type)

/datum/unit_test/dq_a7_initialization/vision_modes/Run()
	scope_setup()
	var/obj/item/rig_module/vision/A = allocate(/obj/item/rig_module/vision, test_floor())
	var/obj/item/rig_module/vision/B = allocate(/obj/item/rig_module/vision, test_floor())
	var/obj/item/rig_module/vision/meson/M = allocate(/obj/item/rig_module/vision/meson, test_floor())
	TEST_ASSERT_EQUAL(length(A.vision_modes), 3, "The real visor constructs its three configured modes")
	TEST_ASSERT_EQUAL(A.vision_index, 1, "The constructor selects the first configured mode")
	TEST_ASSERT_EQUAL(A.vision, A.vision_modes[1], "The selected mode is the actual first owned datum")
	TEST_ASSERT(istype(A.vision, /datum/rig_vision/nvg), "The first configured mode retains its original type and order")
	TEST_ASSERT_NOTNULL(A.vision.glasses, "Mode construction creates its actual night-vision glasses")
	TEST_ASSERT(A.vision != B.vision, "Separate modules never share their mutable mode datums")
	TEST_ASSERT_EQUAL(length(M.vision_modes), 1, "A single-mode subtype constructs only its configured mode")
	TEST_ASSERT_EQUAL(M.vision, M.vision_modes[1], "The subtype selects its own actual mode datum")
	TEST_ASSERT(istype(M.vision, /datum/rig_vision/meson), "The subtype's configured mode remains a meson scanner")
	for(var/datum/rig_vision/V as anything in A.vision_modes)
		TEST_ASSERT_NOTNULL(V.glasses, "Every configured mode finishes its real owned-glasses construction")
