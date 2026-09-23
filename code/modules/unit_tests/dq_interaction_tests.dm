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
	done += interaction.id
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
/proc/dq_resolution_text(datum/interaction_resolution/resolution)
	var/list/available = list()
	for(var/datum/interaction/interaction as anything in resolution.available)
		available += interaction.id
	var/list/blocked = list()
	for(var/datum/interaction/interaction as anything in resolution.blocked)
		blocked += "[interaction.id]:[resolution.blocked[interaction]]"
	return "[jointext(available, ",")]|[jointext(blocked, ",")]"

/datum/unit_test/proc/dq_lit_welder(turf/T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	welder.welding = TRUE
	return welder

// ---- Definitions ----

/// Every interaction definition is well formed, and each has a test.
/datum/unit_test/dq_interaction_definitions
	/// Ids with a dedicated test below. Add yours when you add a definition.
	var/static/list/tested_ids = list(
		"machine_panel", "machine_deconstruct", "machine_anchor", "machine_repair",
		"dq_test_high", "dq_test_tie_a", "dq_test_tie_b", "dq_test_low", "dq_test_blocked", "dq_test_ghostly",
		"dq_actor_observe", "dq_actor_handless", "dq_actor_tool", // dq_actor_adapter_tests.dm
		// Combat mode (dq_combat_mode_tests.dm): the Disarm and Grab interactions and its fixtures.
		"disarm", "grab", "dq_combat_friendly", "dq_combat_hostile", "dq_combat_needs_combat", "dq_combat_needs_peace",
	)

/datum/unit_test/dq_interaction_definitions/Run()
	var/list/seen = list()
	for(var/path in GLOB.interactions_by_type)
		var/datum/interaction/interaction = GLOB.interactions_by_type[path]
		TEST_ASSERT(istext(interaction.id) && length(interaction.id), "[path] has an id")
		TEST_ASSERT(!(interaction.id in seen), "interaction id [interaction.id] is unique")
		seen += interaction.id
		TEST_ASSERT(istext(interaction.name) && length(interaction.name), "[interaction.id] has a name")
		TEST_ASSERT(interaction.effect, "[interaction.id] has an effect")
		TEST_ASSERT(isnull(interaction.category) || (interaction.category in INTERACTION_CATEGORIES), "[interaction.id] has a known category")
		TEST_ASSERT(isnull(interaction.default_action) || (interaction.default_action in list(INPUT_ACTION_USE, INPUT_ACTION_ALTERNATE)), "[interaction.id] answers Use, Alternate or nothing")
		var/datum/predicate/pred = interaction.predicate()
		if(pred)
			TEST_ASSERT(!pred.errors, "[interaction.id] requirements compile: [jointext(pred.errors || list(), "; ")]")
		TEST_ASSERT(interaction.id in tested_ids, "[interaction.id] has a test (add it to tested_ids with one)")
		TEST_ASSERT_EQUAL(INTERACTION_BY_ID(interaction.id), interaction, "[interaction.id] is found by id")

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
	machine.panel_open = TRUE
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
	machine.panel_open = TRUE
	TEST_ASSERT_EQUAL(anchor.why_not(H, machine, wrench), "the maintenance panel is open", "an open panel blocks it")
	machine.panel_open = FALSE
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
	welder.welding = TRUE
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
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T)
	AI.forceMove(T) // in sight of the probe (I3: the AI needs camera sight)
	TEST_ASSERT_EQUAL(dq_resolution_text(interactions_for(AI, probe, null)), "dq_test_ghostly|", "the AI is offered only remote interactions")

	var/obj/dq_input_probe/plain = allocate(/obj/dq_input_probe, T)
	TEST_ASSERT_NULL(try_interaction(H, plain, null, INPUT_ACTION_USE), "no interactions means the legacy fallback")

/// Use through the router, end to end, on a real converted machine.
/datum/unit_test/dq_interaction_use_end_to_end

/datum/unit_test/dq_interaction_use_end_to_end/Run()
	var/turf/T = test_floor()
	var/obj/machinery/autolathe/lathe = allocate(/obj/machinery/autolathe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)

	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds a crowbar")
	H.next_click = 0
	GLOB.input_router.route_click(H, lathe, "left=1")
	TEST_ASSERT(!QDELETED(lathe), "a crowbar on a closed panel is blocked, not a deconstruction")
	var/start_integrity = lathe.get_integrity()
	TEST_ASSERT_EQUAL(start_integrity, lathe.max_integrity, "and it didn't fall through to hitting the machine")

	H.drop_from_inventory(crowbar, T)
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds a screwdriver")
	H.next_click = 0
	GLOB.input_router.route_click(H, lathe, "left=1")
	TEST_ASSERT(lathe.panel_open, "Use with a screwdriver opens the panel")

	H.drop_from_inventory(screwdriver, T)
	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds the crowbar again")
	H.next_click = 0
	GLOB.input_router.route_click(H, lathe, "left=1")
	TEST_ASSERT(QDELETED(lathe), "Use with a crowbar on an open panel deconstructs")
	for(var/obj/structure/frame/frame in T)
		qdel(frame)
	for(var/obj/item/item in T)
		if(!(item in allocated))
			qdel(item)

// ---- Snapshots ----

/**
 * Interaction snapshots: for each recorded converted type, the resolved list
 * for a standard set of actors and held items. A change shows up here in review.
 * Format: "type|actor|held => available|blocked:reason,...".
 */
/datum/unit_test/dq_interaction_snapshots
	var/static/list/snapshot_types = list(
		/obj/machinery/autolathe,
		/obj/machinery/washing_machine,
		/obj/machinery/pipelayer,
		/obj/machinery/vending,
		/obj/machinery/dq_maint_probe,
	)
	var/static/list/expected = list(
		"/obj/machinery/autolathe|human|none => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar",
		"/obj/machinery/autolathe|human|screwdriver => machine_panel|machine_deconstruct:needs a crowbar",
		"/obj/machinery/autolathe|human|crowbar => |machine_panel:needs a screwdriver,machine_deconstruct:the maintenance panel is closed",
		"/obj/machinery/autolathe|human|wrench => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar",
		"/obj/machinery/autolathe|human|welder => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar",
		"/obj/machinery/autolathe|robot|screwdriver => machine_panel|machine_deconstruct:needs a crowbar",
		"/obj/machinery/autolathe|ghost|screwdriver => |",
		"/obj/machinery/autolathe|ai|none => |",
		"/obj/machinery/washing_machine|human|none => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench",
		"/obj/machinery/washing_machine|human|screwdriver => machine_panel|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench",
		"/obj/machinery/washing_machine|human|crowbar => |machine_panel:needs a screwdriver,machine_deconstruct:the maintenance panel is closed,machine_anchor:needs a wrench",
		"/obj/machinery/washing_machine|human|wrench => machine_anchor|machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar",
		"/obj/machinery/washing_machine|human|welder => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench",
		"/obj/machinery/washing_machine|robot|screwdriver => machine_panel|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench",
		"/obj/machinery/washing_machine|ghost|screwdriver => |",
		"/obj/machinery/washing_machine|ai|none => |",
		"/obj/machinery/pipelayer|human|none => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|human|screwdriver => machine_panel|",
		"/obj/machinery/pipelayer|human|crowbar => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|human|wrench => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|human|welder => |machine_panel:needs a screwdriver",
		"/obj/machinery/pipelayer|robot|screwdriver => machine_panel|",
		"/obj/machinery/pipelayer|ghost|screwdriver => |",
		"/obj/machinery/pipelayer|ai|none => |",
		"/obj/machinery/vending|human|none => |machine_anchor:needs a wrench",
		"/obj/machinery/vending|human|screwdriver => |machine_anchor:needs a wrench",
		"/obj/machinery/vending|human|crowbar => |machine_anchor:needs a wrench",
		"/obj/machinery/vending|human|wrench => machine_anchor|",
		"/obj/machinery/vending|human|welder => |machine_anchor:needs a wrench",
		"/obj/machinery/vending|robot|screwdriver => |machine_anchor:needs a wrench",
		"/obj/machinery/vending|ghost|screwdriver => |",
		"/obj/machinery/vending|ai|none => |",
		"/obj/machinery/dq_maint_probe|human|none => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|screwdriver => machine_panel|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|crowbar => |machine_panel:needs a screwdriver,machine_deconstruct:the maintenance panel is closed,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|wrench => machine_anchor|machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|human|welder => |machine_panel:needs a screwdriver,machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:it isn't damaged",
		"/obj/machinery/dq_maint_probe|robot|screwdriver => machine_panel|machine_deconstruct:needs a crowbar,machine_anchor:needs a wrench,machine_repair:needs a welder",
		"/obj/machinery/dq_maint_probe|ghost|screwdriver => |",
		"/obj/machinery/dq_maint_probe|ai|none => |",
	)

/datum/unit_test/dq_interaction_snapshots/Run()
	var/turf/T = test_floor()
	var/list/actors = list(
		"human" = allocate(/mob/living/carbon/human, T),
		"robot" = allocate(/mob/living/silicon/robot, T),
		"ghost" = allocate(/mob/observer/dead, T),
		"ai" = allocate(/mob/living/silicon/ai, T),
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
		for(var/list/combination as anything in combinations)
			var/datum/interaction_resolution/resolution = interactions_for(actors[combination[1]], target, held_items[combination[2]])
			actual += "[type]|[combination[1]]|[combination[2]] => [dq_resolution_text(resolution)]"
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
	// The converted types' hand-written hints are gone: examine generates them.
	var/checked = 0
	for(var/obj/machinery/path as anything in typesof(/obj/machinery))
		if(!initial(path.maintenance_flags))
			continue
		checked++
		var/description = initial(path.description_info)
		if(description)
			for(var/word in list("screwdriver", "crowbar", "maintenance panel"))
				TEST_ASSERT(!findtext(description, word), "[path]'s description_info repeats the generated maintenance hints ('[word]')")
	TEST_ASSERT(checked > 50, "found the Maintainable machine types ([checked])")

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
	var/obj/dq_input_probe/plain = allocate(/obj/dq_input_probe, T)
	TEST_ASSERT_NULL(interaction_examine_lines(H, plain), "no section for things without interactions")

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
