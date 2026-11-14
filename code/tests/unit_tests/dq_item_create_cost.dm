// The cost of making one item, per type, into a closet (what a closet fill step does). Each type is its own test so --profile-tests gives a profile of
// that type's construction alone. Two passes per type: the first times the items with the boot phase timers off (ITEM_COST median and worst lines, logged),
// the second turns them on and counts the atoms each item's construction initializes (asserted: a count does not move with the load on the machine,
// a millisecond does). The per-item phase rows are logged too.

/// Items made per type per pass; the first of the timed pass is a warm-up.
#define ITEM_COST_ROUNDS 30

/datum/unit_test/dq_item_cost_one
	abstract_type = /datum/unit_test/dq_item_cost_one
	/// The type made.
	var/item_path
	/// The atoms one item of the type initializes: itself, its cell, its contents. 0: not asserted, only logged (a container with a rolled or long fill).
	var/atoms_per_item = 1

/datum/unit_test/dq_item_cost_one/Run()
	var/obj/structure/closet/C = allocate(/obj/structure/closet)
	C.set_storage_capacity(100000)
	var/list/times = list()
	for(var/i in 1 to ITEM_COST_ROUNDS + 1)
		var/stamp = TICK_USAGE_REAL
		var/atom/movable/made = new item_path(C)
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		own(made)
		if(i > 1)
			times += ms
	var/list/sorted = sortTim(times.Copy(), GLOBAL_PROC_REF(cmp_numeric_asc))
	var/series = ""
	for(var/ms in times)
		series += " [round(ms, 0.1)]"
	log_test("ITEM_COST: [item_path] median [round(sorted[round(length(sorted) / 2)], 0.001)] ms, worst [round(sorted[length(sorted)], 0.01)] ms over [ITEM_COST_ROUNDS] items; series (ms):[series]")

	// The counted pass: the phase timers count what each item's construction runs.
	GLOB.boot_phase_on = TRUE
	GLOB.boot_phase_us = list()
	GLOB.boot_phase_calls = list()
	GLOB.boot_phase_type_us = list()
	GLOB.boot_phase_first_us = list()
	for(var/i in 1 to ITEM_COST_ROUNDS)
		own(new item_path(C))
	GLOB.boot_phase_on = FALSE
	var/list/phases = sortTim(GLOB.boot_phase_us.Copy(), GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	for(var/i in 1 to min(30, length(phases)))
		var/phase = phases[i]
		log_test("ITEM_COST: [item_path] phase [phase]: [round(phases[phase] / ITEM_COST_ROUNDS, 1)] us per item, [round(GLOB.boot_phase_calls[phase] / ITEM_COST_ROUNDS, 0.1)] calls per item")
	var/atoms_made = GLOB.boot_phase_calls["InitAtom: Initialize (includes decls, caps_init, nested inits) (obj)"] / ITEM_COST_ROUNDS
	log_test("ITEM_COST: [item_path] initializes [atoms_made] atom(s) per item")
	if(atoms_per_item)
		TEST_ASSERT_EQUAL(atoms_made, atoms_per_item, "[item_path] initializes [atoms_made] atoms per item, expected [atoms_per_item]")

/datum/unit_test/dq_item_cost_one/tank
	item_path = /obj/item/tank/emergency/oxygen

/datum/unit_test/dq_item_cost_one/tank_double
	item_path = /obj/item/tank/emergency/oxygen/double

/datum/unit_test/dq_item_cost_one/mask
	item_path = /obj/item/clothing/mask/breath

/datum/unit_test/dq_item_cost_one/suit
	item_path = /obj/item/clothing/suit/space/emergency

/// A helmet whose lamp is off makes no overlay light (up to three more atoms).
/datum/unit_test/dq_item_cost_one/helmet
	item_path = /obj/item/clothing/head/helmet/space/emergency

/// The cooler and the cell it holds.
/datum/unit_test/dq_item_cost_one/cooling
	item_path = /obj/item/suit_cooling_unit/emergency
	atoms_per_item = 2

/datum/unit_test/dq_item_cost_one/crowbar
	item_path = /obj/item/tool/crowbar

/// The emergency toolbox and its tools.
/datum/unit_test/dq_item_cost_one/toolbox
	item_path = /obj/item/storage/toolbox/emergency
	atoms_per_item = 0

/// The first aid kit with its autoinjectors and pill bottles with their pills: the heaviest fill an emergency closet makes.
/datum/unit_test/dq_item_cost_one/firstaid
	item_path = /obj/item/storage/firstaid/o2
	atoms_per_item = 0

/// An item does not write its embed chance at construction (that took a private copy of its combat trait): the chance is worked out when asked.
/datum/unit_test/dq_item_embed_chance_not_written

/datum/unit_test/dq_item_embed_chance_not_written/Run()
	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar)
	TEST_ASSERT_EQUAL(combat_of(bar).embed_chance, -1, "the declared size default is left as it is")
	TEST_ASSERT(bar.embed_chance_now() >= 5, "and the chance asked for is the one its weight and edge give")

/// A tank makes its assembly proxy only when an assembly is taped to it.
/datum/unit_test/dq_tank_proxy_is_lazy

/datum/unit_test/dq_tank_proxy_is_lazy/Run()
	var/obj/item/tank/emergency/oxygen/plain = allocate(/obj/item/tank/emergency/oxygen)
	TEST_ASSERT_NULL(plain.proxyassembly, "an ordinary tank has no assembly proxy")
	var/obj/item/tank/oxygen/onetankbomb/bomb = allocate(/obj/item/tank/oxygen/onetankbomb)
	TEST_ASSERT_NOTNULL(bomb.proxyassembly, "a tank bomb has one")
	TEST_ASSERT_NOTNULL(bomb.proxyassembly.assembly, "holding its assembly")
	TEST_ASSERT(bomb.proxyassembly.tank == bomb, "and naming its tank")
	TEST_ASSERT(bomb.proxy() == bomb.proxyassembly, "proxy() returns the one it has")

/// A movable light makes its overlay light when it first casts, not before: a hat with no lamp makes none.
/datum/unit_test/dq_dark_light_makes_no_overlay

/datum/unit_test/dq_dark_light_makes_no_overlay/Run()
	var/obj/item/clothing/head/helmet/space/emergency/helmet = allocate(/obj/item/clothing/head/helmet/space/emergency)
	TEST_ASSERT_NULL(helmet.overlay_light, "a helmet whose lamp is off has no overlay light")
	helmet.set_light_on(TRUE)
	TEST_ASSERT_NOTNULL(helmet.overlay_light, "switching its light on makes the overlay light")
	TEST_ASSERT(helmet.overlay_light.owner == helmet, "owned by the helmet")
	var/datum/overlay_lighting/made = helmet.overlay_light
	helmet.set_light_on(FALSE)
	helmet.set_light_on(TRUE)
	TEST_ASSERT(helmet.overlay_light == made, "and later switches keep it")
	var/obj/item/flashlight/lamp = allocate(/obj/item/flashlight)
	TEST_ASSERT_NULL(lamp.overlay_light, "a flashlight that starts off has none either")
	lamp.set_light_on(TRUE)
	TEST_ASSERT_NOTNULL(lamp.overlay_light, "turned on it has one")

/// One pill: its reagent holder and what it holds.
/datum/unit_test/dq_item_cost_one/pill
	item_path = /obj/item/reagent_containers/pill/inaprovaline

/// One autoinjector: its reagent holder and what it holds.
/datum/unit_test/dq_item_cost_one/autoinjector
	item_path = /obj/item/reagent_containers/hypospray/autoinjector/oxy

/// A power cell.
/datum/unit_test/dq_item_cost_one/cell
	item_path = /obj/item/cell/high

/// A flashlight (its toggle action).
/datum/unit_test/dq_item_cost_one/flashlight
	item_path = /obj/item/flashlight
	atoms_per_item = 2

/// An item makes the action buttons its type declares when it is first held or worn, not when it is made; made straight into a mob's hands it has them at once.
/datum/unit_test/dq_item_actions_are_lazy

/datum/unit_test/dq_item_actions_are_lazy/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/item/clothing/mask/breath/mask = allocate(/obj/item/clothing/mask/breath, floor)
	TEST_ASSERT_EQUAL(length(mask.actions), 0, "a mask on the floor has made no action")
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, floor)
	TEST_ASSERT(wearer.equip_to_slot_if_possible(mask, SLOT_ID_MASK), "the human wears the mask")
	TEST_ASSERT_EQUAL(length(mask.actions), length(item_rules_of(mask).actions_types), "wearing it makes the actions its type declares")
	TEST_ASSERT_EQUAL(length(mask.actions), 1, "the one adjust action")
	var/datum/action/made = mask.actions[1]
	wearer.drop_from_inventory(mask, floor)
	wearer.equip_to_slot_if_possible(mask, SLOT_ID_MASK)
	TEST_ASSERT(mask.actions[1] == made && length(mask.actions) == 1, "wearing it again makes no second action")
	var/obj/item/flashlight/held = allocate(/obj/item/flashlight, wearer)
	TEST_ASSERT_EQUAL(length(held.actions), length(item_rules_of(held).actions_types), "an item made in a mob's hands has its actions at once")

/// A fresh item of a type reads what its blend of materials works out from the type's row: the same numbers for every one, the row made once.
/datum/unit_test/dq_pristine_blueprint_effects_shared

/datum/unit_test/dq_pristine_blueprint_effects_shared/Run()
	var/turf/floor = dq_containment_floor()
	var/obj/item/tank/emergency/oxygen/first = allocate(/obj/item/tank/emergency/oxygen, floor)
	var/list/row = GLOB.pristine_blueprint_effects[first.type]
	TEST_ASSERT_NOTNULL(row, "the first tank of a type leaves its row")
	var/obj/item/tank/emergency/oxygen/second = allocate(/obj/item/tank/emergency/oxygen, floor)
	TEST_ASSERT(GLOB.pristine_blueprint_effects[second.type] == row, "the second reads the same row")
	TEST_ASSERT_EQUAL(second.max_integrity, first.max_integrity, "and ends with the same integrity")
	TEST_ASSERT_EQUAL(protection_of(second).siemens, protection_of(first).siemens, "and the same conduction")
	TEST_ASSERT_EQUAL(second.max_integrity, row["max_integrity"], "which is the row's number")

/// A pill's fill links its reagent both ways and settles the holder's total, colour and master from that one reagent; the holder and the reagent,
/// which are no atoms and are named by nothing, walk no draw hop to be told they changed.
/datum/unit_test/dq_reagent_fill_links_and_settles

/datum/unit_test/dq_reagent_fill_links_and_settles/Run()
	GLOB.boot_phase_on = TRUE
	GLOB.boot_phase_calls = list()
	var/obj/item/reagent_containers/pill/inaprovaline/pill = allocate(/obj/item/reagent_containers/pill/inaprovaline)
	GLOB.boot_phase_on = FALSE
	var/walks = 0
	for(var/phase in GLOB.boot_phase_calls)
		if(findtext(phase, "draw_hop_published: walk") == 1)
			walks += GLOB.boot_phase_calls[phase]
	TEST_ASSERT_EQUAL(walks, 0, "making a pill walked [walks] draw hop chains for its reagent and holder")
	var/datum/reagents/holder = pill.reagents
	TEST_ASSERT_EQUAL(length(holder.reagent_list), 1, "the pill holds one reagent")
	var/datum/reagent/R = holder.reagent_list[1]
	TEST_ASSERT(R.holder == holder, "the reagent names its holder")
	TEST_ASSERT(holder.reagent_by_id[R.id] == R, "the id index finds it")
	TEST_ASSERT(owner_of(R) == holder, "the holder owns it")
	TEST_ASSERT_EQUAL(holder.total_volume, R.volume, "the total is the reagent's volume")
	TEST_ASSERT_EQUAL(holder.master_id, R.id, "the master is the reagent")
	TEST_ASSERT_EQUAL(holder.tint, R.color, "the tint is the reagent's colour")
	var/before = holder.total_volume
	holder.add_reagent(R.id, 1)
	TEST_ASSERT(holder.total_volume > before || holder.total_volume == holder.maximum_volume, "a later add still settles the total")
	qdel(pill)
	TEST_ASSERT(QDELETED(R), "the reagent dies with its holder")
