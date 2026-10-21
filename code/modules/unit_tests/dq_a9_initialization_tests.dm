// Real constructors expose completed native equipment setup to their callers.
/datum/unit_test/dq_a9_initialization
	abstract_type = /datum/unit_test/dq_a9_initialization

/datum/unit_test/dq_a9_initialization/New()
	. = ..()
	dview(0, test_floor())

/datum/unit_test/dq_a9_initialization/proc/scope_setup()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)

/obj/item/mecha_parts/component/dq_a9_damaged
	start_damaged = TRUE
	max_integrity = 120
	integrity_danger_mod = 0.25

/datum/unit_test/dq_a9_initialization/component_damage/Run()
	scope_setup()
	var/obj/item/mecha_parts/component/C = allocate(/obj/item/mecha_parts/component/dq_a9_damaged, test_floor())
	TEST_ASSERT_EQUAL(C.get_integrity(), 30, "The constructor applies the configured danger integrity")
	var/obj/item/mecha_parts/component/F = allocate(/obj/item/mecha_parts/component, test_floor())
	TEST_ASSERT_EQUAL(F.get_integrity(), F.max_integrity, "An undamaged component retains its full integrity")

/datum/unit_test/dq_a9_initialization/macrobattery/Run()
	scope_setup()
	var/obj/item/ammo_casing/macrobattery/B = allocate(/obj/item/ammo_casing/macrobattery, test_floor())
	TEST_ASSERT_EQUAL(B.charge, B.max_charge, "A real macrobattery starts charged through its setter")
	TEST_ASSERT(!B.charge_short, "Its repeat gate agrees with the full initial charge")

/datum/unit_test/dq_a9_initialization/pneumatic_hopper/Run()
	scope_setup()
	var/obj/item/gun/launcher/pneumatic/G = allocate(/obj/item/gun/launcher/pneumatic, test_floor())
	TEST_ASSERT_NOTNULL(G.item_storage, "The actual launcher owns its hopper before setup")
	TEST_ASSERT_EQUAL(G.item_storage.name, "hopper", "The declared child is named as the hopper")
	TEST_ASSERT_EQUAL(G.item_storage.max_storage_space, G.max_storage_space, "The real hopper receives launcher capacity")
	TEST_ASSERT(isnull(G.item_storage.use_sound), "Opening the hopper does not inherit a generic storage sound")

/datum/unit_test/dq_a9_initialization/magic_charge/Run()
	scope_setup()
	var/obj/item/gun/magic/G = allocate(/obj/item/gun/magic, test_floor())
	TEST_ASSERT_EQUAL(G.charges, G.max_charges, "A real magic gun returns fully charged")

/datum/unit_test/dq_a9_initialization/shield_configuration/Run()
	scope_setup()
	var/obj/item/mecha_parts/mecha_equipment/combat_shield/E = allocate(/obj/item/mecha_parts/mecha_equipment/combat_shield, test_floor())
	TEST_ASSERT_NOTNULL(E.my_shield, "The actual equipment has its declared projector")
	TEST_ASSERT_EQUAL(E.my_shield.shield_regen_delay, E.equip_cooldown, "Projector regen follows equipment cooldown")
	TEST_ASSERT_EQUAL(E.my_shield.my_tool, E, "The projector links back to the exact owning equipment")
