// Real machinery admission reads must refresh their menus without a tracked setter or a later tick.
/datum/unit_test/read_once_machinery_admission
	parent_type = /datum/unit_test/dq_hc_struct
	abstract_type = /datum/unit_test/read_once_machinery_admission

/datum/unit_test/read_once_machinery_admission/New()
	..()
	dview(0, test_floor())

/datum/unit_test/read_once_machinery_admission/proc/find_row(list/rows, key)
	for(var/list/row as anything in rows)
		if(row["key"] == key)
			return row
	return null

/datum/unit_test/read_once_machinery_admission/helmet_customisation
/datum/unit_test/read_once_machinery_admission/helmet_customisation/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/suit_cycler/C = mach(/obj/machinery/suit_cycler, tile(3, 2))
	C.set_locked(FALSE)
	var/obj/item/clothing/head/helmet/space/void/helmet = allocate(/obj/item/clothing/head/helmet/space/void, H.loc)
	helmet.icon_override = null
	TEST_ASSERT(H.put_in_active_hand(helmet), "The real void helmet is in the actor's active hand")
	TEST_ASSERT_NULL(C.helmet, "The real cycler starts with its helmet slot empty")
	var/time_before = op_now()
	var/list/ordinary = find_row(op_menu(H, C, helmet), "cycler_insert_helmet")
	TEST_ASSERT(ordinary && ordinary["enabled"], "An ordinary compatible helmet is accepted by the actual cycler requirement")
	var/actor_gen = rx_of(H).act_gen
	var/machine_gen = rx_of(C).act_gen
	var/item_gen = rx_of(helmet).act_gen
	helmet.icon_override = CUSTOM_ITEM_MOB
	var/list/customised = find_row(op_menu(H, C, helmet), "cycler_insert_helmet")
	TEST_ASSERT_NOTNULL(customised, "Custom appearance disables rather than hides the helmet row")
	TEST_ASSERT(!customised["enabled"], "The current custom helmet cannot be refitted")
	TEST_ASSERT_EQUAL(customised["reason"], "you cannot refit a customised voidsuit", "The actual appearance restriction gives its original refusal")
	TEST_ASSERT_EQUAL(op_now(), time_before, "No later tick repaired this admission menu")
	TEST_ASSERT_EQUAL(rx_of(H).act_gen, actor_gen, "The actor did not publish a repair for the menu")
	TEST_ASSERT_EQUAL(rx_of(C).act_gen, machine_gen, "The cycler did not publish a repair for the menu")
	TEST_ASSERT_EQUAL(rx_of(helmet).act_gen, item_gen, "The plain appearance input did not publish a repair for the menu")
	var/datum/op_result/rejected = test_menu(H, C, "cycler_insert_helmet")
	TEST_ASSERT_EQUAL(rejected?.outcome, ACT_REFUSED, "The public menu pick rejects the currently customised helmet")
	TEST_ASSERT_EQUAL(H.get_active_hand(), helmet, "Refusal preserves the actual held helmet")
	TEST_ASSERT_NULL(C.helmet, "Refusal does not mutate the cycler's actual helmet slot")
	helmet.icon_override = null
	var/list/accepted = find_row(op_menu(H, C, helmet), "cycler_insert_helmet")
	TEST_ASSERT(accepted && accepted["enabled"], "Removing custom appearance re-enables the same held helmet")
	var/datum/op_result/inserted = test_menu(H, C, "cycler_insert_helmet")
	TEST_ASSERT_EQUAL(inserted?.outcome, ACT_COMMITTED, "The public menu pick inserts the compatible helmet")
	TEST_ASSERT_EQUAL(C.helmet, helmet, "The actual cycler now owns that exact helmet")
	TEST_ASSERT_EQUAL(helmet.loc, C, "The successful operation physically moves the helmet into the cycler")
	TEST_ASSERT_NULL(H.get_active_hand(), "Successful insertion vacates the actor's actual hand")

/datum/unit_test/read_once_machinery_admission/suit_customisation
/datum/unit_test/read_once_machinery_admission/suit_customisation/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/suit_cycler/C = mach(/obj/machinery/suit_cycler, tile(3, 2))
	C.set_locked(FALSE)
	var/obj/item/clothing/suit/space/void/suit = allocate(/obj/item/clothing/suit/space/void, H.loc)
	suit.icon_override = null
	TEST_ASSERT(H.put_in_active_hand(suit), "The real voidsuit is in the actor's active hand")
	TEST_ASSERT_NULL(C.suit, "The real cycler starts with its suit slot empty")
	var/time_before = op_now()
	var/list/ordinary = find_row(op_menu(H, C, suit), "cycler_insert_suit")
	TEST_ASSERT(ordinary && ordinary["enabled"], "An ordinary compatible voidsuit is accepted")
	var/actor_gen = rx_of(H).act_gen
	var/machine_gen = rx_of(C).act_gen
	var/item_gen = rx_of(suit).act_gen
	suit.icon_override = CUSTOM_ITEM_MOB
	var/list/customised = find_row(op_menu(H, C, suit), "cycler_insert_suit")
	TEST_ASSERT_NOTNULL(customised, "Custom appearance keeps the disabled voidsuit row visible")
	TEST_ASSERT(!customised["enabled"], "The current custom voidsuit cannot be refitted")
	TEST_ASSERT_EQUAL(customised["reason"], "you cannot refit a customised voidsuit", "The real customised suit has its original refusal")
	TEST_ASSERT_EQUAL(op_now(), time_before, "The same-tick suit admission is refreshed")
	TEST_ASSERT_EQUAL(rx_of(H).act_gen, actor_gen, "The actor generation is unchanged")
	TEST_ASSERT_EQUAL(rx_of(C).act_gen, machine_gen, "The machine generation is unchanged")
	TEST_ASSERT_EQUAL(rx_of(suit).act_gen, item_gen, "The item generation is unchanged")
	var/datum/op_result/rejected = test_menu(H, C, "cycler_insert_suit")
	TEST_ASSERT_EQUAL(rejected?.outcome, ACT_REFUSED, "A public pick cannot insert the currently customised suit")
	TEST_ASSERT_EQUAL(H.get_active_hand(), suit, "Refusal preserves the actual held suit")
	TEST_ASSERT_NULL(C.suit, "Refusal leaves the actual suit slot empty")
	suit.icon_override = null
	var/list/accepted = find_row(op_menu(H, C, suit), "cycler_insert_suit")
	TEST_ASSERT(accepted && accepted["enabled"], "The same voidsuit is accepted after its custom appearance is removed")
	var/datum/op_result/inserted = test_menu(H, C, "cycler_insert_suit")
	TEST_ASSERT_EQUAL(inserted?.outcome, ACT_COMMITTED, "The public operation inserts the actual compatible suit")
	TEST_ASSERT_EQUAL(C.suit, suit, "The actual cycler owns the exact accepted suit")
	TEST_ASSERT_EQUAL(suit.loc, C, "The suit physically moves into the cycler")
	TEST_ASSERT_NULL(H.get_active_hand(), "Insertion empties the original hand")

/datum/unit_test/read_once_machinery_admission/camera_injury_kind
/datum/unit_test/read_once_machinery_admission/camera_injury_kind/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/camera/C = mach(/obj/machinery/camera, tile(3, 2))
	var/obj/item/weapon = allocate(/obj/item, H.loc)
	weapon.force = 20
	weapon.injury_kinds = null
	weapon.injury_kind = INJURY_PAIN
	TEST_ASSERT(H.put_in_active_hand(weapon), "The real damaging item is held")
	TEST_ASSERT_NULL(weapon.obj_damage_type(), "The initial injury kind genuinely cannot harm an object")
	var/time_before = op_now()
	var/list/harmless = find_row(op_menu(H, C, weapon), "camera_bash")
	TEST_ASSERT(harmless && !harmless["enabled"], "The harmless injury kind retains the original disabled attack row")
	TEST_ASSERT_EQUAL(harmless["reason"], "not possible right now", "The disabled attack has its actual refusal")
	var/actor_gen = rx_of(H).act_gen
	var/machine_gen = rx_of(C).act_gen
	var/item_gen = rx_of(weapon).act_gen
	weapon.injury_kind = INJURY_BLUNT
	TEST_ASSERT_EQUAL(weapon.obj_damage_type(), BRUTE, "The new injury kind genuinely harms objects")
	var/list/bash = find_row(op_menu(H, C, weapon), "camera_bash")
	TEST_ASSERT(bash && bash["enabled"], "Changing the same held item's injury kind exposes the actual attack row")
	TEST_ASSERT_EQUAL(op_now(), time_before, "No later tick repairs the camera menu")
	TEST_ASSERT_EQUAL(rx_of(H).act_gen, actor_gen, "The actor generation is unchanged")
	TEST_ASSERT_EQUAL(rx_of(C).act_gen, machine_gen, "The camera generation is unchanged")
	TEST_ASSERT_EQUAL(rx_of(weapon).act_gen, item_gen, "The injury-kind input has no generated setter publication")
	weapon.injury_kind = INJURY_PAIN
	harmless = find_row(op_menu(H, C, weapon), "camera_bash")
	TEST_ASSERT(harmless && !harmless["enabled"], "The attack row becomes disabled when the same item stops harming objects")
	TEST_ASSERT_EQUAL(harmless["reason"], "not possible right now", "Current harmless admission retains the exact refusal")
	var/integrity_before = C.get_integrity()
	var/datum/op_result/rejected = test_menu(H, C, "camera_bash")
	TEST_ASSERT_EQUAL(rejected?.outcome, ACT_REFUSED, "The public attack pick rejects the current harmless injury kind")
	TEST_ASSERT_EQUAL(C.get_integrity(), integrity_before, "Rejected admission cannot damage the actual camera")
	weapon.injury_kind = INJURY_BLUNT
	var/datum/op_result/attacked = test_menu(H, C, "camera_bash")
	TEST_ASSERT_EQUAL(attacked?.outcome, ACT_COMMITTED, "The public menu pick runs the admitted camera attack")
	TEST_ASSERT(C.get_integrity() < integrity_before, "The admitted attack actually damages the camera")

// A real custodian override: occupancy alone cannot express its mutable release policy.
/mob/living/carbon/human/read_once_floor_light_actor
	var/custody_blocked = FALSE
	var/static/custody_refusal = "fixture custody prevents release"

/mob/living/carbon/human/read_once_floor_light_actor/release_refusal(atom/movable/thing, mob/user)
	if(custody_blocked && istype(thing, /obj/item/floor_light))
		return custody_refusal
	return ..()

/datum/unit_test/read_once_machinery_admission/floor_light_custody
/datum/unit_test/read_once_machinery_admission/floor_light_custody/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/turf/T = tile(2, 2)
	var/mob/living/carbon/human/read_once_floor_light_actor/H = allocate(/mob/living/carbon/human/read_once_floor_light_actor, T)
	H.enable_godmode()
	var/obj/item/floor_light/kit = allocate(/obj/item/floor_light, T)
	TEST_ASSERT(H.put_in_active_hand(kit), "The actual floor-light kit enters a real working hand")
	TEST_ASSERT_EQUAL(kit.loc, H, "The real actor is the kit's custodian")
	var/lights_before = length(contents_of(T, /obj/machinery/floor_light))
	H.custody_blocked = TRUE
	TEST_ASSERT_EQUAL(H.release_refusal(kit, H), H.custody_refusal, "The actual custodian override refuses release")
	var/time_before = op_now()
	var/list/denied = find_row(op_menu(H, kit, kit), "install")
	TEST_ASSERT_NOTNULL(denied, "Custody refusal keeps the installation row visible")
	TEST_ASSERT(!denied["enabled"], "The installation requirement samples the actual custody refusal")
	TEST_ASSERT_EQUAL(denied["reason"], H.custody_refusal, "The row preserves the real custodian's refusal")
	var/actor_gen = rx_of(H).act_gen
	var/kit_gen = rx_of(kit).act_gen
	var/datum/op_result/refused = test_menu(H, kit, "install")
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "The public installation pick respects current custody")
	TEST_ASSERT(!consume(kit, H), "The atomic consume also consults the actual custodian override")
	TEST_ASSERT(!QDELETED(kit), "Custody refusal preserves the actual kit")
	TEST_ASSERT_EQUAL(H.get_active_hand(), kit, "Custody refusal preserves the original active hand")
	TEST_ASSERT_EQUAL(kit.loc, H, "Custody refusal leaves the kit with its original custodian")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/machinery/floor_light)), lights_before, "Refused installation creates no floor light")
	H.custody_blocked = FALSE
	TEST_ASSERT_NULL(H.release_refusal(kit, H), "The same real custodian now permits release")
	var/list/allowed = find_row(op_menu(H, kit, kit), "install")
	TEST_ASSERT(allowed && allowed["enabled"], "Changing only custody policy refreshes the same kit's menu admission")
	TEST_ASSERT_EQUAL(op_now(), time_before, "No time elapsed to repair custody admission")
	TEST_ASSERT_EQUAL(rx_of(H).act_gen, actor_gen, "The custodian policy change did not publish an actor generation")
	TEST_ASSERT_EQUAL(rx_of(kit).act_gen, kit_gen, "The actual kit generation did not repair the menu")
	var/datum/op_result/installed = test_menu(H, kit, "install")
	TEST_ASSERT_EQUAL(installed?.outcome, ACT_COMMITTED, "The public installation pick commits once custody allows release")
	TEST_ASSERT(QDELETED(kit), "Successful installation consumes the exact original kit")
	TEST_ASSERT_NULL(H.get_active_hand(), "Successful installation vacates the original hand")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/machinery/floor_light)), lights_before + 1, "Successful installation creates exactly one actual floor light")
