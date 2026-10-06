// Interaction framework (roadmap I2): definitions, the resolver, the Menu,
// generated examine text and screentips, and the Maintainable domain.

// ---- Fixtures ----

/// Test interactions for resolver ordering and ties. They live only on the probe.
/datum/interaction/dq_test
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/dq_interaction_probe/proc/note_interaction

/datum/interaction/dq_test/high
	id = "dq_test_high"
	name = "High"
	priority = 30
	default_action = INPUT_ACTION_USE

/datum/interaction/dq_test/tie_a
	id = "dq_test_tie_a"
	name = "Tie A"
	priority = 20
	default_action = INPUT_ACTION_ALTERNATE

/datum/interaction/dq_test/tie_b
	id = "dq_test_tie_b"
	name = "Tie B"
	priority = 20
	default_action = INPUT_ACTION_ALTERNATE

/datum/interaction/dq_test/low
	id = "dq_test_low"
	name = "Low"
	priority = 5
	category = INTERACTION_CAT_LOCK

/datum/interaction/dq_test/blocked
	id = "dq_test_blocked"
	name = "Needs a knife"
	priority = 40
	default_action = INPUT_ACTION_USE
	requires = list(REQ_BECAUSE(REQ_HOLDING, "needs a knife"))

/datum/interaction/dq_test/ghostly
	id = "dq_test_ghostly"
	name = "Remote poke"
	priority = 1
	tags = list(INTERACTION_TAG_REMOTE)

/obj/dq_interaction_probe
	name = "interaction probe"
	var/list/done = list()

/obj/dq_interaction_probe/declare_interactions(list/into)
	..()
	into += list(
		/datum/interaction/dq_test/low,
		/datum/interaction/dq_test/tie_a,
		/datum/interaction/dq_test/high,
		/datum/interaction/dq_test/blocked,
		/datum/interaction/dq_test/tie_b,
		/datum/interaction/dq_test/ghostly,
	)

/obj/dq_interaction_probe/proc/note_interaction(mob/actor, obj/item/held, datum/interaction/interaction)
	LAZYADD(done, interaction.id)
	return TRUE

/// A machine with every Maintainable flag, no waits, and a recorded dismantle.
/obj/machinery/dq_maint_probe
	name = "maintenance probe"
	maintenance_flags = MACHINE_MAINT_PANEL | MACHINE_MAINT_FRAME | MACHINE_MAINT_WRENCH | MACHINE_MAINT_WELDER_REPAIR
	maintenance_wrench_time = 0
	maintenance_weld_time = 0
	use_power = USE_POWER_OFF
	anchored = TRUE
	var/dismantled = 0

/obj/machinery/dq_maint_probe/dismantle()
	dismantled++
	return TRUE

/// The ids in a resolution, as "available|blocked:reason,...".
/// An interaction id as snapshots record it: a generic id's collision suffix (the md5 that
/// dq_interaction_from_spec() adds) is dropped, since which of two same-named specs gets the plain
/// id depends on which type was declared first, i.e. on which tests ran before.
/proc/dq_snapshot_id(id)
	var/static/regex/suffix = regex(@"^(gen_.+)_[0-9a-f]{32}$")
	if(suffix.Find(id))
		return suffix.group[1]
	return id

/proc/dq_resolution_text(datum/interaction_resolution/resolution)
	var/list/available = list()
	for(var/datum/interaction/interaction as anything in resolution.available)
		available += dq_snapshot_id(interaction.id)
	var/list/blocked = list()
	for(var/datum/interaction/interaction as anything in resolution.blocked)
		blocked += "[dq_snapshot_id(interaction.id)]:[resolution.blocked[interaction]]"
	return "[jointext(available, ",")]|[jointext(blocked, ",")]"

/datum/unit_test/proc/dq_lit_welder(turf/T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	welder.set_welding(TRUE)
	return welder

// ---- Definitions ----

/// Every interaction definition is well formed, and each has a test.
/datum/unit_test/dq_interaction_definitions
	/// Ids with a dedicated test below. Add yours when you add a definition.
	var/static/list/tested_ids = list(
		"machine_panel", "machine_deconstruct", "machine_anchor", "machine_repair",
		"lattice_item", // dq_interaction_lattice_item: a lattice only exists over open space
		"dq_test_high", "dq_test_tie_a", "dq_test_tie_b", "dq_test_low", "dq_test_blocked", "dq_test_ghostly",
		"dq_actor_observe", "dq_actor_handless", "dq_actor_tool", // dq_actor_adapter_tests.dm
		// Combat mode (dq_combat_mode_tests.dm): the Disarm and Grab interactions and its fixtures.
		"disarm", "grab", "dq_combat_friendly", "dq_combat_hostile", "dq_combat_needs_combat", "dq_combat_needs_peace",
		"dq_tool_weld", "dq_tool_dig", // dq_tool_tests.dm
		// Construction (dq_construction_tests.dm and its per-domain files). Graph edges are checked there, not here.
		"wall_burn_rot", "wall_light_thermite", "wall_repair", "mecha_fix_temperature", "mecha_weld_repair", "mecha_weld_repair_disarm", "mecha_weld_repair_grab", "mecha_weld_strike",
		"robot_pry_help", "robot_pry_disarm", "robot_pry_grab", "robot_weld_repair_help", "robot_weld_repair_disarm", "robot_weld_repair_grab", // dq_interaction_robot_tool_stances below
		"mecha_seal_tank", "mecha_fix_wiring", "mecha_extinguish", "mecha_paste_repair", "mecha_recalibrate", // dq_mech_body_tests.dm mech_repair_interactions
		"ai_slipper_toggle_lock", // code/game/machinery/ai_slipper.dm: no dedicated test or snapshot yet
		"shadekin_phase_shift", "shadekin_dark_respite", "shadekin_regenerate_other", "shadekin_create_shade", // dq_ability_tests.dm
		"shadekin_dark_maw", "shadekin_clear_dark_maws", "shadekin_dark_tunneling", // dq_ability_tests.dm
		"robot_toggle_lights", "robot_pick_name", "robot_customize_appearance", "robot_toggle_glowy_stomach",
		"robot_spark_plug", "robot_toggle_grabbability", "robot_purge_nutrition", "robot_toggle_decals",
		"robot_sensor_mode", "robot_recolour", "robot_toggle_vtec", // dq_ability_tests.dm
		"robot_pick_shell", "robot_set_mail_tag", "robot_eject_cargo", // dq_ability_tests.dm
		"robot_nom", "robot_mount", "robot_toggle_module_1", "robot_toggle_module_2", "robot_toggle_module_3", // dq_ability_tests.dm
		"ship_emote_beyond", // dq_interaction_ship_emote_beyond below
		"unit_test_secondary_wrench", // interaction_tests.dm: the secondary-dispatch fixture
		"stacking_console_use", // code/modules/mining/machinery/machine_stacking.dm: needs a linked machine on the map, excluded from dq_i7_bulk_capture.dm's snapshot
		// I7: verb-category and drag/enter ids without an `entry`, so the snapshot-coverage
		// check (which requires `entry`) never sees them even when a snapshot exists.
		"aiupload_access_internals", "card_eject_id", "cash_register_open_box_verb", "centrifuge_isolate_reagents", "centrifuge_isolate_reagents_bottle", "centrifuge_isolate_reagents_canisters", "cryopod_eject", "cryopod_enter", "disposal_force_eject", "distillery_toggle_mixing", "distillery_toggle_power", "drill_unload", "faxmachine_remove_card", "faxmachine_request_roles", "firework_launcher_eject", "food_replicator_eject_beaker", "guestpass_eject_id", "implantchair_get_out", "implantchair_move_inside", "material_furnace_eject_contents", "mixer_set_rotation", "nuclearbomb_make_deployable", "papershredder_empty", "pod_syndicate_open_ui", "processor_eject", "reagent_filter_flip", "reagent_filter_set_filter", "reagent_furnace_flip", "reagent_furnace_set_filter", "reagent_refinery_set_transfer_amount", "recharge_station_eject", "recharge_station_enter", "secure_data_eject_id", "security_station_map", "suit_cycler_leave", "suit_storage_get_out", "suit_storage_move_inside", "teleporter_computer_set_id", "transportpod_eject", "transportpod_enter", "vr_sleeper_alien_eject", "vr_sleeper_climb_in", "vr_sleeper_eject", "washing_machine_climb_out", "washing_machine_start_washing", "wheel_of_fortune_setinterval",
	)

/// Type-local entries: stance-declared interactions run from the one proc that names them
/// (windowdoor.dm and robot.dm keep the defines file-local; the airlock's ctrl entries are capability entries).
/datum/unit_test/dq_interaction_definitions/var/static/list/type_local_entries = list("windoor_weld", "robot_crowbar", "robot_welder")

/datum/unit_test/dq_interaction_definitions/Run()
	var/list/seen = list()
	var/list/untested = list()
	for(var/path in GLOB.interactions_by_type)
		var/datum/interaction/interaction = GLOB.interactions_by_type[path]
		TEST_ASSERT(istext(interaction.id) && length(interaction.id), "[path] has an id")
		TEST_ASSERT(!(interaction.id in seen), "interaction id [interaction.id] is unique")
		seen += interaction.id
		TEST_ASSERT(istext(interaction.name) && length(interaction.name), "[interaction.id] has a name")
		TEST_ASSERT(interaction.effect || istype(interaction, /datum/interaction/emag), "[interaction.id] has an effect") // the emag runs its own run_effect()
		TEST_ASSERT(isnull(interaction.category) || (interaction.category in INTERACTION_CATEGORIES) || (interaction.category in ABILITY_CATEGORIES), "[interaction.id] has a known category")
		TEST_ASSERT(isnull(interaction.default_action) || (interaction.default_action in list(INPUT_ACTION_USE, INPUT_ACTION_ALTERNATE)), "[interaction.id] answers Use, Alternate or nothing")
		TEST_ASSERT(isnull(interaction.entry) || (interaction.entry in list(INTERACTION_ENTRY_ITEM, INTERACTION_ENTRY_HAND, INTERACTION_ENTRY_SELF, INTERACTION_ENTRY_ALT, INTERACTION_ENTRY_DRAG)) || (interaction.entry in type_local_entries), "[interaction.id] has a known entry")
		var/datum/predicate/selector = interaction.selector()
		if(selector)
			TEST_ASSERT(!selector.errors, "[interaction.id] selector compiles: [jointext(selector.errors || list(), "; ")]")
		var/datum/predicate/pred = interaction.predicate()
		if(pred)
			TEST_ASSERT(!pred.errors, "[interaction.id] requirements compile: [jointext(pred.errors || list(), "; ")]")
		if(!((interaction.id in tested_ids) || (interaction.entry && dq_snapshot_covered_ids()[dq_snapshot_id(interaction.id)]) || findtext(interaction.id, "dq_entry_") == 1))
			untested += interaction.id
		TEST_ASSERT_EQUAL(INTERACTION_BY_ID(interaction.id), interaction, "[interaction.id] is found by id")
	// Listed together so one run names every uncovered id.
	TEST_ASSERT(!length(untested), "[length(untested)] interaction(s) have no test (add each to tested_ids with one, or record a converted domain's snapshot): [jointext(untested, ", ")]")

/// A lattice deletes itself off open space, so the structures snapshot can't hold it: build one
/// over space next to the test floor, offer it rods, and let the rods make it a catwalk.
/datum/unit_test/dq_interaction_lattice_item

/datum/unit_test/dq_interaction_lattice_item/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/neighbor = get_step(T, EAST)
	TEST_ASSERT_NOTNULL(neighbor, "no turf beside the test floor")
	var/old_type = neighbor.type
	var/turf/space/gap = neighbor.ChangeTurf(/turf/space)
	var/obj/structure/lattice/lattice = allocate(/obj/structure/lattice, gap)
	TEST_ASSERT(!QDELETED(lattice), "a lattice over space should stay")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/stack/rods/rods = allocate(/obj/item/stack/rods, T, 5)
	test_op_handler(lattice, "interaction_item", H, rods) // the lattice's rods op (CAPABILITIES): its effect, as the engine runs it
	var/obj/structure/catwalk/catwalk = locate_within(gap, /obj/structure/catwalk)
	TEST_ASSERT_NOTNULL(own(catwalk), "rods should turn the lattice into a catwalk")
	TEST_ASSERT_EQUAL(rods.get_amount(), 4, "the upgrade should use one rod")
	qdel(catwalk)
	gap.ChangeTurf(old_type)

/// Open and close the maintenance panel.
/datum/unit_test/dq_interaction_machine_panel

/datum/unit_test/dq_interaction_machine_panel/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/datum/interaction/panel = INTERACTION(/datum/interaction/maintainable/panel)

	TEST_ASSERT_EQUAL(panel.why_not(H, machine, null), "needs a screwdriver", "without a screwdriver")
	TEST_ASSERT_NULL(panel.why_not(H, machine, screwdriver), "with a screwdriver, adjacent")
	TEST_ASSERT_EQUAL(panel.display_name(H, machine), "Open maintenance panel", "named for a closed panel")
	TEST_ASSERT(panel.perform(H, machine, screwdriver), "opening the panel runs")
	TEST_ASSERT(machine.panel_open, "the panel is open")
	TEST_ASSERT_EQUAL(panel.display_name(H, machine), "Close maintenance panel", "named for an open panel")
	TEST_ASSERT(panel.perform(H, machine, screwdriver), "closing the panel runs")
	TEST_ASSERT(!machine.panel_open, "the panel is closed again")

	machine.maintenance_flags = NONE
	TEST_ASSERT(!panel.applies_to(machine), "not offered without MACHINE_MAINT_PANEL")

/// Deconstruct needs a crowbar and an open panel.
/datum/unit_test/dq_interaction_machine_deconstruct

/datum/unit_test/dq_interaction_machine_deconstruct/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	var/datum/interaction/deconstruct = INTERACTION(/datum/interaction/maintainable/deconstruct)

	TEST_ASSERT_EQUAL(deconstruct.why_not(H, machine, crowbar), "the maintenance panel is closed", "a closed panel blocks it")
	TEST_ASSERT(!deconstruct.perform(H, machine, crowbar), "blocked, it does nothing")
	TEST_ASSERT_EQUAL(machine.dismantled, 0, "not dismantled while blocked")
	machine.set_panel_open(TRUE)
	TEST_ASSERT(deconstruct.perform(H, machine, crowbar), "with the panel open it runs")
	TEST_ASSERT_EQUAL(machine.dismantled, 1, "dismantled once")

/// Secure and unsecure need a wrench and a closed panel.
/datum/unit_test/dq_interaction_machine_anchor

/datum/unit_test/dq_interaction_machine_anchor/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/datum/interaction/anchor = INTERACTION(/datum/interaction/maintainable/anchor)

	TEST_ASSERT_EQUAL(anchor.display_name(H, machine), "Unsecure", "an anchored machine is unsecured")
	TEST_ASSERT(anchor.perform(H, machine, wrench), "unsecuring runs")
	TEST_ASSERT(!machine.anchored, "unsecured")
	TEST_ASSERT_EQUAL(anchor.display_name(H, machine), "Secure", "a loose machine is secured")
	machine.set_panel_open(TRUE)
	TEST_ASSERT_EQUAL(anchor.why_not(H, machine, wrench), "the maintenance panel is open", "an open panel blocks it")
	machine.set_panel_open(FALSE)
	TEST_ASSERT(anchor.perform(H, machine, wrench), "securing runs")
	TEST_ASSERT(machine.anchored, "secured")
	machine.maintenance_wrench_time = 2 SECONDS
	wrench.toolspeed = 0.5
	TEST_ASSERT_EQUAL(anchor.duration_for(H, machine, wrench), 1 SECOND, "the wait is the machine's wrench time scaled by the tool's speed")

/// Weld repair needs a lit welder and damage.
/datum/unit_test/dq_interaction_machine_repair

/datum/unit_test/dq_interaction_machine_repair/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	var/datum/interaction/repair = INTERACTION(/datum/interaction/maintainable/repair)

	TEST_ASSERT_EQUAL(repair.why_not(H, machine, welder), "it isn't damaged", "an intact machine needs no repair")
	machine.take_damage(machine.max_integrity / 2, BRUTE, MELEE, FALSE)
	TEST_ASSERT(machine.get_integrity() < machine.max_integrity, "the probe took damage")
	TEST_ASSERT_EQUAL(repair.why_not(H, machine, welder), "the welding tool must be on", "an unlit welder is refused")
	welder.set_welding(TRUE)
	TEST_ASSERT(repair.perform(H, machine, welder), "repair runs")
	TEST_ASSERT_EQUAL(machine.get_integrity(), machine.max_integrity, "fully repaired")
	TEST_ASSERT_EQUAL(repair.category, INTERACTION_CAT_REPAIR, "repair is in the Repair category")

// ---- Resolver ----

/// Ordering by priority, blocked reasons, ties opening the Menu, and actor adapters.
/datum/unit_test/dq_interaction_resolver

/datum/unit_test/dq_interaction_resolver/Run()
	var/turf/T = test_floor()
	var/obj/dq_interaction_probe/probe = allocate(/obj/dq_interaction_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/interaction_resolution/resolution = interactions_for(H, probe, null)
	TEST_ASSERT_EQUAL(dq_resolution_text(resolution), "dq_test_high,dq_test_tie_a,dq_test_tie_b,dq_test_low,dq_test_ghostly|dq_test_blocked:needs a knife", "sorted by priority, stable among equals, blocked with its reason")
	TEST_ASSERT_EQUAL(length(resolution.best_for_action(INPUT_ACTION_USE)), 1, "one best for Use")
	TEST_ASSERT_EQUAL(length(resolution.best_for_action(INPUT_ACTION_ALTERNATE)), 2, "Alternate ties")

	TEST_ASSERT_EQUAL(try_interaction(H, probe, null, INPUT_ACTION_USE), INTERACTION_TRY_RAN, "Use runs the top interaction")
	TEST_ASSERT_EQUAL(jointext(probe.done, ","), "dq_test_high", "the top Use interaction ran")
	TEST_ASSERT_EQUAL(try_interaction(H, probe, null, INPUT_ACTION_ALTERNATE), INTERACTION_TRY_MENU, "a tie opens the Menu")
	TEST_ASSERT_EQUAL(length(probe.done), 1, "nothing ran on a tie")

	var/obj/item/dq_input_probe_item/knife = allocate(/obj/item/dq_input_probe_item, T)
	resolution = interactions_for(H, probe, knife)
	TEST_ASSERT_EQUAL(resolution.available[1], INTERACTION(/datum/interaction/dq_test/blocked), "holding something unblocks the higher one, which now leads")

	TEST_ASSERT(try_interaction_category(H, probe, INTERACTION_CAT_LOCK), "a category key runs the best of its category")
	TEST_ASSERT_EQUAL(probe.done[length(probe.done)], "dq_test_low", "the Lock category's interaction ran")

	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(ghost, probe, null)), "|", "ghosts are offered nothing")
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	AI.forceMove(T) // in sight of the probe (I3: the AI needs camera sight)
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(AI, probe, null)), "dq_test_ghostly|", "the AI is offered only remote interactions")

	var/obj/plain = allocate(/obj, T)
	TEST_ASSERT_NULL(try_interaction(H, plain, null, INPUT_ACTION_USE), "no interactions means the legacy fallback")

/// Use through the input inbox (a player's click), end to end, on a real converted machine.
/datum/unit_test/dq_interaction_use_end_to_end

/datum/unit_test/dq_interaction_use_end_to_end/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/machinery/autolathe/lathe = allocate(/obj/machinery/autolathe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)

	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds a crowbar")
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, lathe, null, null, "left=1"))
	test_time(1)
	TEST_ASSERT(!QDELETED(lathe), "a crowbar on a closed panel is blocked, not a deconstruction")
	var/start_integrity = lathe.get_integrity()
	TEST_ASSERT_EQUAL(start_integrity, lathe.max_integrity, "and it didn't fall through to hitting the machine")

	H.drop_from_inventory(crowbar, T)
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds a screwdriver")
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, lathe, null, null, "left=1"))
	test_time(1)
	TEST_ASSERT(panel_open(lathe), "Use with a screwdriver opens the panel")

	H.drop_from_inventory(screwdriver, T)
	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds the crowbar again")
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, lathe, null, null, "left=1"))
	test_time(1)
	TEST_ASSERT(QDELETED(lathe), "Use with a crowbar on an open panel deconstructs")
	for(var/obj/structure/frame/frame in turf_contents_of_type(T, /obj/structure/frame))
		qdel(frame)
	for(var/obj/item/item in turf_contents_of_type(T, /obj/item))
		if(!(item in allocated))
			qdel(item)
	test_driver_end()

// ---- Snapshots ----

/**
 * Interaction snapshots: for each recorded converted type, the resolved list
 * for a standard set of actors and held items. A change shows up here in review.
 * Format: "type|actor|held => available|blocked:reason,...".
 */
/datum/unit_test/dq_interaction_snapshots
	var/static/list/snapshot_types = list(
		/obj/machinery/washing_machine,
		/obj/machinery/pipelayer,
		/obj/machinery/dq_maint_probe,
	)
	var/static/list/expected = list(
		"/obj/machinery/washing_machine|human|none => washing_machine_use_item,washing_machine_start,washing_machine_start_washing,washing_machine_use|machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,washing_machine_climb_out:you aren't inside it",
		"/obj/machinery/washing_machine|human|screwdriver => machine_panel,washing_machine_use_item,washing_machine_start,washing_machine_start_washing,washing_machine_use|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,washing_machine_climb_out:you aren't inside it",
		"/obj/machinery/washing_machine|human|crowbar => washing_machine_use_item,washing_machine_start,washing_machine_start_washing,washing_machine_use|machine_panel:needs a screwdriver,machine_deconstruct:the maintenance panel is closed,machine_anchor:needs a wrench,washing_machine_climb_out:you aren't inside it",
		"/obj/machinery/washing_machine|human|wrench => machine_anchor,washing_machine_use_item,washing_machine_start,washing_machine_start_washing,washing_machine_use|machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,washing_machine_climb_out:you aren't inside it",
		"/obj/machinery/washing_machine|human|welder => washing_machine_use_item,washing_machine_start,washing_machine_start_washing,washing_machine_use|machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,washing_machine_climb_out:you aren't inside it",
		"/obj/machinery/washing_machine|robot|screwdriver => machine_panel,washing_machine_use_item,washing_machine_start,washing_machine_start_washing,washing_machine_use|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,gen_robot_interaction_swallow:not possible right now,washing_machine_climb_out:you aren't inside it",
		"/obj/machinery/washing_machine|ghost|screwdriver => |",
		"/obj/machinery/washing_machine|ai|none => |",
		"/obj/machinery/pipelayer|human|none => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|human|screwdriver => machine_panel|",
		"/obj/machinery/pipelayer|human|crowbar => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|human|wrench => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|human|welder => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|robot|screwdriver => machine_panel|gen_robot_interaction_swallow:not possible right now",
		"/obj/machinery/pipelayer|ghost|screwdriver => |",
		"/obj/machinery/pipelayer|ai|none => |",
		"/obj/machinery/dq_maint_probe|human|none => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|screwdriver => machine_panel|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|crowbar => |machine_panel:needs a screwdriver,machine_deconstruct:the maintenance panel is closed,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|wrench => machine_anchor|machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|welder => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:it isn't damaged",
		"/obj/machinery/dq_maint_probe|robot|screwdriver => machine_panel|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:needs a welder,gen_robot_interaction_swallow:not possible right now",
		"/obj/machinery/dq_maint_probe|ghost|screwdriver => |",
		"/obj/machinery/dq_maint_probe|ai|none => |",
	)

/datum/unit_test/dq_interaction_snapshots/Run()
	var/turf/T = test_floor()
	var/list/actors = list(
		"human" = allocate(/mob/living/carbon/human, T),
		"robot" = allocate(/mob/living/silicon/robot, T),
		"ghost" = allocate(/mob/observer/dead, T),
		"ai" = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE),
	)
	var/list/held_items = list(
		"none" = null,
		"screwdriver" = allocate(/obj/item/tool/screwdriver, T),
		"crowbar" = allocate(/obj/item/tool/crowbar, T),
		"wrench" = allocate(/obj/item/tool/wrench, T),
		"welder" = dq_lit_welder(T),
	)
	// Humans try every item; the others one representative each.
	var/list/combinations = list()
	for(var/held_name in held_items)
		combinations += list(list("human", held_name))
	combinations += list(list("robot", "screwdriver"), list("ghost", "screwdriver"), list("ai", "none"))

	var/list/actual = list()
	for(var/type in snapshot_types)
		var/atom/target = allocate(type, T)
		// See dq_snapshot_lines(): newly-allocated machinery can briefly read as
		// unpowered until the power subsystem's next tick in a full-suite run.
		if(ismachinery(target))
			var/obj/machinery/M = target
			M.stat_remove(NOPOWER|BROKEN)
		for(var/list/combination as anything in combinations)
			var/datum/interaction_resolution/resolution = interactions_for(actors[combination[1]], target, held_items[combination[2]])
			actual += "[type]|[combination[1]]|[combination[2]] => [dq_resolution_text(resolution)]"
	// On a mismatch, write the actual lines out for review and regeneration (as the domain snapshots do).
	if(length(actual ^ expected))
		var/file_name = "data/test-snapshots/[replacetext("[type]", "/", "_")].txt"
		fdel(file_name)
		text2file(jointext(actual, "\n"), file_name)
	for(var/line in actual)
		TEST_ASSERT(line in expected, "new or changed snapshot: [line]")
	for(var/line in expected)
		TEST_ASSERT(line in actual, "missing snapshot: [line]")

/// The Maintainable interactions follow the machine's flags, and converted types carry no hand-written maintenance hints.
/datum/unit_test/dq_interaction_maintainable_flags

/datum/unit_test/dq_interaction_maintainable_flags/Run()
	var/static/list/by_flag = list(
		"[MACHINE_MAINT_PANEL]" = /datum/interaction/maintainable/panel,
		"[MACHINE_MAINT_FRAME]" = /datum/interaction/maintainable/deconstruct,
		"[MACHINE_MAINT_WRENCH]" = /datum/interaction/maintainable/anchor,
		"[MACHINE_MAINT_WELDER_REPAIR]" = /datum/interaction/maintainable/repair,
	)
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, test_floor())
	var/list/candidates = interaction_candidates(machine)
	for(var/flag_text in by_flag)
		var/datum/interaction/maintainable/interaction = INTERACTION(by_flag[flag_text])
		TEST_ASSERT_EQUAL(interaction.maintenance_flag, text2num(flag_text), "[interaction.id] is offered by its flag")
		TEST_ASSERT(interaction in candidates, "machines declare [interaction.id]")
		machine.maintenance_flags = text2num(flag_text)
		TEST_ASSERT(interaction.applies_to(machine), "[interaction.id] applies with its flag alone")
		machine.maintenance_flags = NONE
		TEST_ASSERT(!interaction.applies_to(machine), "[interaction.id] doesn't apply without its flag")

// ---- Menu, examine and screentips ----

/// The Menu lists available interactions with keys, blocked ones with reasons, mob actions and verbs.
/datum/unit_test/dq_interaction_menu_data

/datum/unit_test/dq_interaction_menu_data/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds a screwdriver")

	var/list/data = interaction_menu_data(H, machine)
	TEST_ASSERT_EQUAL(data["target"], "Maintenance probe", "the Menu names its target")
	var/list/available = data["available"]
	TEST_ASSERT_EQUAL(length(available), 1, "one available interaction")
	var/list/panel = available[1]
	TEST_ASSERT_EQUAL(panel["id"], "machine_panel", "the panel is available")
	TEST_ASSERT_EQUAL(panel["name"], "Open maintenance panel", "named for its state")
	TEST_ASSERT_EQUAL(jointext(panel["keys"], ","), "Click", "reached by Click (no client, so no category keys)")
	var/list/blocked = data["blocked"]
	TEST_ASSERT_EQUAL(length(blocked), 3, "three blocked interactions")
	var/list/first_blocked = blocked[1]
	TEST_ASSERT_EQUAL(first_blocked["id"], "machine_deconstruct", "blocked are sorted by priority")
	TEST_ASSERT_EQUAL(first_blocked["reason"], "needs a crowbar", "with the reason")
	var/list/action_ids = list()
	for(var/list/entry as anything in data["actions"])
		action_ids += entry["id"]
	TEST_ASSERT_EQUAL(jointext(action_ids, ","), "[INPUT_ACTION_INSPECT],[INPUT_ACTION_PULL],[INPUT_ACTION_POINT]", "the popup's mob actions")
	TEST_ASSERT(islist(data["verbs"]), "legacy verbs are listed")

	var/list/lines = interaction_examine_lines(H, machine)
	TEST_ASSERT_EQUAL(length(lines), 5, "examine: a heading, one available and three blocked")
	TEST_ASSERT(findtext(lines[2], "Open maintenance panel (Click)"), "examine shows what you can do with its key: [lines[2]]")
	TEST_ASSERT(findtext(lines[3], "Deconstruct: needs a crowbar"), "examine shows what you can't and why: [lines[3]]")
	var/obj/plain = allocate(/obj, T) // dq_input_probe declares one interaction per actor kind now
	var/list/plain_lines = interaction_examine_lines(H, plain)
	TEST_ASSERT_NULL(plain_lines, "no section for things without interactions: [jointext(plain_lines, "; ")]")

/// Screentip text for Use and Alternate.
/datum/unit_test/dq_interaction_screentips

/datum/unit_test/dq_interaction_screentips/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dq_maint_probe/machine = allocate(/obj/machinery/dq_maint_probe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	TEST_ASSERT_EQUAL(interaction_screentip_text(H, machine, null), "Maintenance probe", "nothing to do: just the name")
	TEST_ASSERT_EQUAL(interaction_screentip_text(H, machine, wrench), "Maintenance probe\nClick: Unsecure", "Use with a wrench")
	var/obj/dq_interaction_probe/probe = allocate(/obj/dq_interaction_probe, T)
	TEST_ASSERT_EQUAL(interaction_screentip_text(H, probe, null), "Interaction probe\nClick: High\nAlt-click: choose", "Use and a tied Alternate")

/// The old Emote Beyond verb (`set src in oview(7)`): offered within sight of the helm, not past it.
/datum/unit_test/dq_interaction_ship_emote_beyond

/datum/unit_test/dq_interaction_ship_emote_beyond/Run()
	var/turf/T = test_floor()
	var/obj/machinery/computer/ship/navigation/helm = allocate(/obj/machinery/computer/ship/navigation, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(findtext(dq_resolution_text(interactions_for(H, helm, null)), "ship_emote_beyond"), "Emote Beyond is offered within sight of the helm")
	var/turf/far = locate(T.x + 8, T.y, T.z)
	if(far)
		H.forceMove(far)
		TEST_ASSERT(findtext(dq_resolution_text(interactions_for(H, helm, null)), "ship_emote_beyond:too far away"), "past seven tiles Emote Beyond is blocked as too far away")

/// i6b: a robot's crowbar and welder answer per stance outside combat mode, and strike in it.
/datum/unit_test/dq_interaction_robot_tool_stances

/datum/unit_test/dq_interaction_robot_tool_stances/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	R.locked = FALSE
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB))
		H.set_use_stance(stance)
		H.put_in_active_hand(crowbar)
		R.opened = FALSE
		TEST_ASSERT(R.crowbar_act(H, crowbar) & ITEM_INTERACT_SUCCESS, "stance [stance]: the crowbar works the chassis")
		TEST_ASSERT(R.opened, "stance [stance]: the crowbar opens the cover")
		H.drop_from_inventory(crowbar)
		H.put_in_active_hand(welder)
		R.injure(INJURY_BLUNT, 20)
		var/before = R.injury_load(INJURY_CATEGORY_PHYSICAL)
		TEST_ASSERT(before > 0, "stance [stance]: the robot is dented")
		TEST_ASSERT(R.welder_act(H, welder) & ITEM_INTERACT_SUCCESS, "stance [stance]: the welder works the chassis")
		TEST_ASSERT(R.injury_load(INJURY_CATEGORY_PHYSICAL) < before, "stance [stance]: the weld repairs dents")
		H.drop_from_inventory(welder)
	R.opened = FALSE
	H.set_use_stance(I_HURT)
	H.put_in_active_hand(crowbar)
	TEST_ASSERT(R.crowbar_act(H, crowbar) & ITEM_INTERACT_SKIP_TO_ATTACK, "combat mode: the crowbar goes on to strike")
	TEST_ASSERT(!R.opened, "combat mode: the cover stays shut")
	H.set_use_stance(I_HELP)
