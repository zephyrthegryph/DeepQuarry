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
	TEST_ASSERT_EQUAL(B.color, B.material.icon_colour, "The bracelet has its material colour when returned")
	TEST_ASSERT_NOTNULL(R.material, "The actual ring constructor resolves its forced material")
	TEST_ASSERT_EQUAL(R.name, "[R.material.display_name] ring", "Ring setup follows material resolution")
	TEST_ASSERT_EQUAL(R.color, R.material.icon_colour, "The ring has its material colour when returned")

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
