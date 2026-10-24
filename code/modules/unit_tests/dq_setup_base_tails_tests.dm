// The setup(PROC_REF(x)) forms that replaced the Initialize() tails of the big shared bases: items, stacks, storage, clothing, simulated turfs and
// floors, machinery, the huge portables, the telescreens, the medigun pack, the motion tracker, the circuit memories and the biowaste tank.
// Each runs once the instance's Initialize() chain has returned, ancestors first, so every type sees its parents' work done.

/datum/unit_test/dq_setup_base_tails_item

/datum/unit_test/dq_setup_base_tails_item/Run()
	var/turf/T = dq_containment_floor()

	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, T)
	TEST_ASSERT_EQUAL(length(F.actions), length(item_rules_of(F).actions_types), "an item makes the actions its type declares")

	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	var/datum/type_trait/item_combat/combat = combat_of(P)
	var/expected = max(5, round(combat.force / (combat.sharp ? P.w_class : P.w_class * 3)))
	TEST_ASSERT_EQUAL(P.embed_chance, expected, "an item left on the default embed chance takes it from its weight and edge")

	var/obj/item/tool/crowbar/bar = allocate(/obj/item/tool/crowbar, T)
	var/obj/item/tool/crowbar/other = allocate(/obj/item/tool/crowbar, T)
	TEST_ASSERT(bar.tool_qualities == other.tool_qualities, "identical tool quality tables are shared")

// A stack takes its stack type and starting amount (a negative one is a full stack) after the item hooks; a material stack takes its material after that.
/datum/unit_test/dq_setup_base_tails_stack

/datum/unit_test/dq_setup_base_tails_stack/Run()
	var/turf/T = dq_containment_floor()

	var/obj/item/stack/material/steel/full = allocate(/obj/item/stack/material/steel, T, -1)
	TEST_ASSERT_EQUAL(full.amount, full.max_amount, "a stack made with a negative amount is a full stack")
	TEST_ASSERT_EQUAL(full.stacktype, full.material.stack_type, "and its material's stack type wins over its own type")
	TEST_ASSERT(findtext(full.name, full.material.use_name), "and it is named for its material, which needs the amount already set")

	var/obj/item/stack/material/steel/few = allocate(/obj/item/stack/material/steel, T, 3)
	TEST_ASSERT_EQUAL(few.amount, 3, "a stack made with an amount has it")

	var/obj/item/stack/material/exotic_feedstock/random/sample = allocate(/obj/item/stack/material/exotic_feedstock/random, T)
	TEST_ASSERT(sample.material, "a random feedstock rolls a material of its own")
	var/obj/item/stack/material/exotic_feedstock/random/named = allocate(/obj/item/stack/material/exotic_feedstock/random, T, null, MAT_WARD_METAL)
	TEST_ASSERT_EQUAL(named.default_type, MAT_WARD_METAL, "a random feedstock made with a material keeps it")
	TEST_ASSERT_EQUAL(named.material.name, MAT_WARD_METAL, "and is made of it")

// A storage declares (or drops) its starting contents and calibrates after the item hooks.
/datum/unit_test/dq_setup_base_tails_storage

/datum/unit_test/dq_setup_base_tails_storage/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/storage/toolbox/mechanical/box = allocate(/obj/item/storage/toolbox/mechanical, T)
	TEST_ASSERT(box.has_latent() || length(box.contents), "a toolbox declares its starting contents")
	box.make_contents_real()
	TEST_ASSERT(length(box.contents), "and they are made real when it is used")

// The simulated turf hooks run (radiation, chapel, level, planets, freelook), then the floor lays its flooring.
/datum/unit_test/dq_setup_base_tails_floor

/datum/unit_test/dq_setup_base_tails_floor/Run()
	var/turf/T = dq_containment_floor()
	var/turf/east = get_step(T, EAST)
	var/turf/simulated/floor/wood/W = east.ChangeTurf(/turf/simulated/floor/wood)
	TEST_ASSERT(W.flooring, "a floor made with a flooring lays it")
	TEST_ASSERT_EQUAL(W.flooring, get_flooring_data(W.initial_flooring), "and it is the type's own flooring")
	east.ChangeTurf(/turf/simulated/floor)

// A machine joins its power once made, faces the way it was built, and the huge portables number themselves.
/datum/unit_test/dq_setup_base_tails_machine

/datum/unit_test/dq_setup_base_tails_machine/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/dq_default_parts_probe/M = allocate(/obj/machinery/dq_default_parts_probe, T, WEST)
	TEST_ASSERT(sparse_get_or(M, power_init_complete, FALSE), "a machine has its power setup done after init")
	TEST_ASSERT_EQUAL(M.power_area, get_area(M), "and draws from its area")
	TEST_ASSERT_EQUAL(M.dir, WEST, "a machine made with a facing has it")

	var/obj/machinery/portable_atmospherics/powered/pump/huge/H = allocate(/obj/machinery/portable_atmospherics/powered/pump/huge, T)
	TEST_ASSERT(findtext(H.name, "(ID [H.id])"), "a huge pump carries its number in its name")
	var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S = allocate(/obj/machinery/portable_atmospherics/powered/scrubber/huge, T)
	TEST_ASSERT(findtext(S.name, "(ID [S.id])"), "a huge scrubber carries its number in its name")

// The circuit memories and demultiplexers say what they have once their pins are built.
/datum/unit_test/dq_setup_base_tails_circuits

/datum/unit_test/dq_setup_base_tails_circuits/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/integrated_circuit/memory/medium/chip = allocate(/obj/item/integrated_circuit/memory/medium, T)
	TEST_ASSERT_EQUAL(chip.complexity, chip.number_of_pins, "a memory chip costs a point of complexity per pin")
	var/obj/item/integrated_circuit/transfer/demultiplexer/medium/dmux = allocate(/obj/item/integrated_circuit/transfer/demultiplexer/medium, T)
	TEST_ASSERT(findtext(dmux.desc, "It has [dmux.number_of_outputs] output pins."), "a demultiplexer counts its outputs in its description")
	TEST_ASSERT(findtext(dmux.extended_desc, "from 1 to [dmux.number_of_outputs]"), "and its extended one, from its built pins")
	var/obj/item/integrated_circuit/transfer/pulsedemultiplexer/medium/pulse = allocate(/obj/item/integrated_circuit/transfer/pulsedemultiplexer/medium, T)
	TEST_ASSERT(findtext(pulse.extended_desc, "from 1 to [pulse.number_of_outputs]"), "a pulse demultiplexer counts its pulse outputs in its extended description")

// The medigun pack links its gun; the motion tracker subscribes the mob that holds it.
/datum/unit_test/dq_setup_base_tails_gear

/datum/unit_test/dq_setup_base_tails_gear/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/medigun_backpack/pack = allocate(/obj/item/medigun_backpack, T)
	var/obj/item/bork_medigun/linked/gun = pack.get_medigun()
	TEST_ASSERT(gun, "a medigun pack makes its gun")
	TEST_ASSERT_EQUAL(gun.medigun_base_unit(), pack, "and links it to itself")
