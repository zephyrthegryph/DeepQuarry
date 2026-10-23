// stored_refs conversions (doc/rewrite/proposals/reference_storage.md): each family's references are declared relations, so a deleted target
// leaves the holder's var by itself, and a deleted holder neither keeps nor deletes what it only names.

/// The view vars on machines and items: set through the relation, cleared when the target dies, and a dying holder leaves the target alone.
/datum/unit_test/stored_refs_view_vars

/datum/unit_test/stored_refs_view_vars/Run()
	var/obj/machinery/suspension_gen/gen = allocate(/obj/machinery/suspension_gen)
	var/obj/item/card/id/card = allocate(/obj/item/card/id)
	TEST_ASSERT_EQUAL(rel_kind(gen, nameof(gen.auth_card)), OWNK_REL, "auth_card is a declared relation")
	rel_set(gen, nameof(gen.auth_card), card)
	TEST_ASSERT_EQUAL(gen.auth_card, card, "the card is held")
	qdel(card)
	TEST_ASSERT_NULL(gen.auth_card, "a deleted card leaves the generator")
	var/obj/item/card/id/second = allocate(/obj/item/card/id)
	rel_set(gen, nameof(gen.auth_card), second)
	qdel(gen)
	TEST_ASSERT(!QDELETED(second), "a deleted generator leaves the card it only named")
	var/obj/item/shield_projector/projector = allocate(/obj/item/shield_projector)
	var/obj/effect/directional_shield/shield = allocate(/obj/effect/directional_shield)
	TEST_ASSERT_EQUAL(rel_kind(shield, nameof(shield.projector)), OWNK_REL, "a shield's projector is a declared relation")
	rel_set(shield, nameof(shield.projector), projector)
	TEST_ASSERT_EQUAL(shield.projector, projector, "the projector is held")
	qdel(projector)
	TEST_ASSERT_NULL(shield.projector, "a deleted projector leaves its shield")
	var/obj/item/radio/integrated/module = allocate(/obj/item/radio/integrated)
	TEST_ASSERT_EQUAL(rel_kind(module, nameof(module.active)), OWNK_REL, "the active bot is a declared relation")
	var/obj/belly/special/teleporter/belly = allocate(/obj/belly/special/teleporter)
	TEST_ASSERT_EQUAL(rel_kind(belly, nameof(belly.target)), OWNK_REL, "a teleporter belly's target is a declared relation")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	rel_set(belly, nameof(belly.target), pen)
	TEST_ASSERT_EQUAL(belly.target, pen, "the target is held")
	qdel(pen)
	TEST_ASSERT_NULL(belly.target, "a deleted target leaves the belly")

/// The scripting engine: the interpreter owns its two stacks and the parser its block stack; a block's statements are a many that drops dead ones.
/datum/unit_test/stored_refs_scripting

/datum/unit_test/stored_refs_scripting/Run()
	var/datum/n_Interpreter/interpreter = new
	var/datum/stack/scopes = interpreter.scopes
	var/datum/stack/functions = interpreter.functions
	TEST_ASSERT(istype(scopes) && istype(functions), "the interpreter made both stacks")
	TEST_ASSERT_EQUAL(rel_kind(interpreter, nameof(interpreter.scopes)), OWNK_OWN, "the scope stack is owned")
	qdel(interpreter)
	TEST_ASSERT(QDELETED(scopes) && QDELETED(functions), "a deleted interpreter takes its stacks")
	var/datum/n_Parser/nS_Parser/parser = new(list(), null)
	var/datum/node/BlockDefinition/GlobalBlock/global_block = parser.global_block
	var/datum/stack/blocks = parser.blocks
	TEST_ASSERT(istype(global_block) && istype(blocks), "the parser made its global block and block stack")
	TEST_ASSERT_EQUAL(parser.curBlock(), global_block, "the parser starts in the global block")
	qdel(parser)
	TEST_ASSERT(QDELETED(blocks), "a deleted parser takes its block stack")
	TEST_ASSERT(!QDELETED(global_block), "a deleted parser leaves the tree it built")
	var/datum/node/statement/ReturnStatement/statement = new
	var/datum/node/statement/ReturnStatement/other = new
	global_block.add_statement(statement)
	global_block.add_statement(other)
	TEST_ASSERT_EQUAL(length(global_block.statements), 2, "statements keep their order")
	TEST_ASSERT_EQUAL(global_block.statements[1], statement, "first statement first")
	qdel(statement)
	TEST_ASSERT_EQUAL(length(global_block.statements), 1, "a deleted statement leaves its block")
	TEST_ASSERT_EQUAL(global_block.statements[1], other, "the rest keep their place")
	qdel(global_block)
	qdel(other)

/// A firedoor is in the door list of every area it guards; the list drops it when it goes.
/datum/unit_test/stored_refs_area_doors

/datum/unit_test/stored_refs_area_doors/Run()
	var/obj/machinery/door/firedoor/door = allocate(/obj/machinery/door/firedoor)
	var/area/here = get_area(door)
	TEST_ASSERT(istype(here), "the door stands in an area")
	TEST_ASSERT(door in here.all_doors, "the door joined its area's list")
	qdel(door)
	TEST_ASSERT(!(door in here.all_doors), "a deleted door left the list")

/// A radio's channel connections are a keyed many: set and cleared by channel name, and a dying radio leaves the shared frequency alone.
/datum/unit_test/stored_refs_radio_channels

/datum/unit_test/stored_refs_radio_channels/Run()
	var/obj/item/radio/radio = allocate(/obj/item/radio)
	var/datum/radio_frequency/frequency = SSradio.add_object(radio, PUB_FREQ, RADIO_CHAT)
	TEST_ASSERT(istype(frequency), "the radio service gave a frequency")
	rel_add(radio, nameof(radio.secure_radio_connections), frequency, "stored_refs_test")
	TEST_ASSERT_EQUAL(radio.secure_radio_connections["stored_refs_test"], frequency, "read back by channel name")
	rel_add(radio, nameof(radio.secure_radio_connections), null, "stored_refs_test")
	TEST_ASSERT_NULL(radio.secure_radio_connections["stored_refs_test"], "emptying the key clears it")
	rel_add(radio, nameof(radio.secure_radio_connections), frequency, "stored_refs_test")
	rel_clear(radio, nameof(radio.secure_radio_connections))
	TEST_ASSERT_NULL(radio.secure_radio_connections?["stored_refs_test"], "clearing the var empties every key")
	rel_add(radio, nameof(radio.secure_radio_connections), frequency, "stored_refs_test")
	qdel(radio)
	TEST_ASSERT(!QDELETED(frequency), "a deleted radio leaves the frequency the service owns")

/// The power grid registry's id index is a keyed many next to the list that owns the grids.
/datum/unit_test/stored_refs_power_grid_index

/datum/unit_test/stored_refs_power_grid_index/Run()
	var/id = 987654
	var/datum/power_grid/grid = power_grid(id)
	var/datum/power_grid_registry/registry = power_grid_registry()
	TEST_ASSERT_EQUAL(registry.lookup(id), grid, "the grid is found by id")
	registry.drop(id)
	TEST_ASSERT_NULL(registry.lookup(id), "a dropped id finds nothing")
	var/datum/power_grid/second = power_grid(id)
	TEST_ASSERT_EQUAL(registry.lookup(id), second, "the id can be taken again")
	registry.clear()
