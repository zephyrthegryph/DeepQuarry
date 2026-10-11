// Type traits (code/engine/declare/type_traits.dm) through the machine power trait, uses_power() (code/game/machinery/machinery_power.dm):
// per-type data declared in CAPABILITIES, read with no instance cost, inherited and configure()d, and overridden per instance at run time.

/obj/machinery/dq_power_trait_probe
	name = "power trait probe"

CAPABILITIES(/obj/machinery/dq_power_trait_probe)
	configure(uses_power(channel = ENVIRON, idle = 7, active = 70))

/// Inherits the channel and the idle draw, changes the active draw only.
/obj/machinery/dq_power_trait_probe/child

CAPABILITIES(/obj/machinery/dq_power_trait_probe/child)
	configure(uses_power(active = 140))

/datum/unit_test/dq_type_trait
	abstract_type = /datum/unit_test/dq_type_trait

/datum/unit_test/dq_type_trait/declared_and_inherited
/datum/unit_test/dq_type_trait/override_is_per_instance

/// The declared values, a subtype's configure() over them, and the base defaults.
/datum/unit_test/dq_type_trait/declared_and_inherited/Run()
	var/datum/type_trait/power/base = power_of_type(/obj/machinery)
	TEST_ASSERT_EQUAL(base.channel, EQUIP, "a machine draws on the equipment channel by default")
	TEST_ASSERT_EQUAL(base.idle, 0, "and draws nothing idle")
	var/datum/type_trait/power/probe = power_of_type(/obj/machinery/dq_power_trait_probe)
	TEST_ASSERT_EQUAL(probe.channel, ENVIRON, "the type's own declaration")
	TEST_ASSERT_EQUAL(probe.idle, 7, "its idle draw")
	TEST_ASSERT_EQUAL(probe.active, 70, "its active draw")
	var/datum/type_trait/power/child = power_of_type(/obj/machinery/dq_power_trait_probe/child)
	TEST_ASSERT_EQUAL(child.active, 140, "a subtype's configure() changes what it names")
	TEST_ASSERT_EQUAL(child.idle, 7, "and inherits what it does not")
	TEST_ASSERT_EQUAL(child.channel, ENVIRON, "the channel too")
	var/obj/machinery/dq_power_trait_probe/M = allocate(/obj/machinery/dq_power_trait_probe, test_floor())
	TEST_ASSERT_EQUAL(power_of(M), probe, "an instance reads its type's one shared trait")

/// A run-time write gives that machine its own values and publishes the key; its siblings keep the type's.
/datum/unit_test/dq_type_trait/override_is_per_instance/Run()
	var/obj/machinery/dq_power_trait_probe/A = allocate(/obj/machinery/dq_power_trait_probe, test_floor())
	var/obj/machinery/dq_power_trait_probe/B = allocate(/obj/machinery/dq_power_trait_probe, test_floor())
	TEST_ASSERT(A.update_active_power_usage(500), "the write takes")
	TEST_ASSERT_EQUAL(power_of(A).active, 500, "the machine reads its own value")
	TEST_ASSERT_EQUAL(power_of(A).idle, 7, "and keeps the rest of its type's")
	TEST_ASSERT_EQUAL(power_of(B).active, 70, "a sibling keeps the type's")
	TEST_ASSERT_EQUAL(power_of_type(/obj/machinery/dq_power_trait_probe).active, 70, "and the type's declaration is unchanged")
	TEST_ASSERT(!A.update_active_power_usage(500), "writing the value it has changes nothing")
	A.update_power_channel(LIGHT)
	TEST_ASSERT_EQUAL(power_of(A).channel, LIGHT, "the channel moves")
	TEST_ASSERT(A.draws_light(null) && !A.draws_environ(null), "and the draw follows it")

/datum/unit_test/dq_type_trait/item_sounds_declared

/// The item sounds trait: the base's defaults, a subtype's configure() and TRAIT_NONE silencing an inherited sound; a run-time write is the item's own.
/datum/unit_test/dq_type_trait/item_sounds_declared/Run()
	var/datum/type_trait/item_sounds/base = sounds_of_type(/obj/item)
	TEST_ASSERT_EQUAL(base.pickup, SFX_GENERIC_PICKUP, "an item picks up with the generic sound")
	TEST_ASSERT_EQUAL(base.hit, SFX_SWING_HIT, "and strikes with the swing")
	var/datum/type_trait/item_sounds/card = sounds_of_type(/obj/item/card)
	TEST_ASSERT_EQUAL(card.pickup, SFX_ITEMS_PICKUP_CARD, "a card has its own pickup sound")
	TEST_ASSERT_EQUAL(card.hit, SFX_SWING_HIT, "and inherits the strike")
	var/datum/type_trait/item_sounds/knife = sounds_of_type(/obj/item/material/butterfly)
	TEST_ASSERT_NULL(knife.hit, "TRAIT_NONE silences an inherited sound")
	var/obj/item/card/A = allocate(/obj/item/card, test_floor())
	var/obj/item/card/B = allocate(/obj/item/card, test_floor())
	TEST_ASSERT(A.set_drop_sound(SFX_GENERIC_DROP), "a run-time write takes")
	TEST_ASSERT_EQUAL(sounds_of(A).drop, SFX_GENERIC_DROP, "the item reads its own")
	TEST_ASSERT_EQUAL(sounds_of(B).drop, card.drop, "a sibling keeps the type's")
