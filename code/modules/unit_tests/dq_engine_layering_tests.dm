// Regression boundaries between the generic space engine and physical inventory adapters.
/obj/engine_layering_bay
	var/obj/item/cell/cell

CAPABILITIES(/obj/engine_layering_bay)
	owns_one(nameof(cell), /obj/item/cell)
	cell_bay(nameof(cell))

/datum/unit_test/dq_engine_layering_cell_delivery/Run()
	var/obj/engine_layering_bay/bay = allocate(/obj/engine_layering_bay)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/mob/living/silicon/robot/robot = allocate(/mob/living/silicon/robot)
	var/obj/item/gripper/omni/carrier = allocate(/obj/item/gripper/omni, robot)
	TEST_ASSERT_NOTNULL(carrier, "The actual cyborg gripper initializes")
	var/obj/item/cell/for_carrier = allocate(/obj/item/cell, bay)
	rel_set(bay, nameof(bay.cell), for_carrier)
	TEST_ASSERT(carrier.can_carry(for_carrier, actor), "Setup leaves the real carrier available")
	TEST_ASSERT_EQUAL(varslot_take(bay, nameof(bay.cell), actor, carrier), for_carrier, "The bay releases the exact cell")
	TEST_ASSERT_EQUAL(carrier.get_wrapped_item(), for_carrier, "The carrier gets first choice ahead of the actor's empty hands")
	TEST_ASSERT(for_carrier.loc in carrier.pockets, "The cell actually enters a real gripper pocket")
	TEST_ASSERT_NULL(bay.cell, "Carrier delivery empties the owned bay")
	carrier.gripper_in_use = TRUE
	var/obj/item/cell/for_hand = allocate(/obj/item/cell, bay)
	rel_set(bay, nameof(bay.cell), for_hand)
	TEST_ASSERT(!carrier.can_carry(for_hand, actor), "Setup makes the carrier unavailable")
	TEST_ASSERT_EQUAL(varslot_take(bay, nameof(bay.cell), actor, carrier), for_hand, "The next exact cell is released")
	TEST_ASSERT_EQUAL(for_hand.loc, actor, "The actor receives the cell when the carrier refuses it")
	TEST_ASSERT_EQUAL(carrier.get_wrapped_item(), for_carrier, "Fallback preserves the carrier's original cell")
	var/obj/item/tool/crowbar/blocker = allocate(/obj/item/tool/crowbar)
	TEST_ASSERT(actor.put_in_hands(blocker), "Setup fills the actor's other hand")
	TEST_ASSERT(actor.get_active_hand() && actor.get_inactive_hand(), "Both actor hands are occupied")
	var/obj/item/cell/for_floor = allocate(/obj/item/cell, bay)
	rel_set(bay, nameof(bay.cell), for_floor)
	TEST_ASSERT_EQUAL(varslot_take(bay, nameof(bay.cell), actor, carrier), for_floor, "The full-inventory extraction still returns the exact cell")
	TEST_ASSERT_EQUAL(for_floor.loc, run_loc_floor_bottom_left, "When carrier and hands refuse, the cell lands on the floor")
	TEST_ASSERT_NULL(bay.cell, "Floor delivery empties the owned bay")
	TEST_ASSERT(!QDELETED(for_floor), "Floor fallback preserves the cell")

/datum/unit_test/dq_engine_layering_movable_input_record/Run()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/obj/engine_layering_bay/target = allocate(/obj/engine_layering_bay)
	var/obj/effect/held = allocate(/obj/effect)
	TEST_ASSERT(!istype(held, /obj/item), "The held fixture is a generic movable, not an item")
	var/datum/input_event/menu/menu = allocate(/datum/input_event/menu, actor, target, "record_only", held)
	TEST_ASSERT_EQUAL(menu.held, held, "The menu constructor preserves a generic movable's exact identity")
	TEST_ASSERT_EQUAL(menu.actor, actor, "The same record preserves its actor")
	TEST_ASSERT_EQUAL(menu.target, target, "The same record preserves its target")
	TEST_ASSERT_EQUAL(menu.op_key, "record_only", "The same record preserves its selected key")
	var/datum/input_event/click/click = allocate(/datum/input_event/click, actor, target)
	click.held = held
	TEST_ASSERT_EQUAL(click.held, held, "A driver click record also preserves the generic movable")

/datum/unit_test/dq_engine_layering_size_requirement/Run()
	var/datum/entry/part/req/size_is/fits = size_is(ITEMSIZE_NORMAL)
	var/datum/act/op/A = allocate(/datum/act/op)
	var/obj/item/cell/cell = allocate(/obj/item/cell)
	A.held = cell
	cell.w_class = ITEMSIZE_NORMAL
	TEST_ASSERT(fits.holds(A), "The exact declared size fits")
	cell.w_class = ITEMSIZE_SMALL
	TEST_ASSERT(!fits.holds(A), "A smaller actual item fails the minimum")
	TEST_ASSERT_EQUAL(fits.refusal(A), /datum/msg/slot/too_small, "A smaller item gives the small-item reason")
	cell.w_class = ITEMSIZE_HUGE
	TEST_ASSERT(!fits.holds(A), "A larger actual item fails the maximum")
	TEST_ASSERT_EQUAL(fits.refusal(A), /datum/msg/slot/too_large, "A larger item gives the large-item reason")

/datum/engine_layering_actor_probe
	var/mob/observed

/datum/engine_layering_actor_probe/proc/capture()
	observed = input_actor()
	return observed

/datum/engine_layering_actor_probe/proc/fail_after_capture()
	observed = input_actor()
	throw EXCEPTION("Expected actor shim regression probe")

/datum/unit_test/dq_engine_layering_actor_restore/Run()
	var/mob/before = input_actor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/engine_layering_actor_probe/probe = allocate(/datum/engine_layering_actor_probe)
	TEST_ASSERT_EQUAL(with_actor(actor, probe, TYPE_PROC_REF(/datum/engine_layering_actor_probe, capture)), actor, "The callback executes with its explicit actor")
	TEST_ASSERT_EQUAL(input_actor(), before, "Normal completion restores the prior actor")
	probe.observed = null
	var/exception/caught
	try
		with_actor(actor, probe, TYPE_PROC_REF(/datum/engine_layering_actor_probe, fail_after_capture))
	catch(var/exception/fault)
		caught = fault
	TEST_ASSERT_NOTNULL(caught, "The intentionally throwing handler really ran")
	TEST_ASSERT_EQUAL(probe.observed, actor, "The throwing handler saw the explicit actor")
	TEST_ASSERT_EQUAL(input_actor(), before, "Exceptional completion also restores the prior actor")

// A var-slot may omit ownership, but its writes still use the tracked state contract.
/obj/engine_layering_unowned_bay
	var/atom/movable/payload
	var/notices = 0

TRACKED(/obj/engine_layering_unowned_bay, payload)

CAPABILITIES(/obj/engine_layering_unowned_bay)
	on_change(nameof(payload), ANY, then(PROC_REF(payload_changed)))

/obj/engine_layering_unowned_bay/proc/payload_changed(datum/act/A)
	notices++

/datum/unit_test/dq_engine_layering_unowned_slot_setter/Run()
	test_driver_begin()
	var/obj/engine_layering_unowned_bay/bay = allocate(/obj/engine_layering_unowned_bay)
	var/obj/item/cell/cell = allocate(/obj/item/cell, bay)
	TEST_ASSERT(!rel_kind(bay, nameof(bay.payload)), "Setup exercises a var slot with no declared ownership")
	TEST_ASSERT_EQUAL(bay.notices, 0, "No payload change has been delivered before the write")
	varslot_set(bay, nameof(bay.payload), cell)
	TEST_ASSERT_EQUAL(bay.payload, cell, "The var slot stores the exact movable through its setter")
	test_drain()
	TEST_ASSERT_EQUAL(bay.notices, 1, "Setting the var slot publishes exactly one tracked change")
	varslot_set(bay, nameof(bay.payload), null)
	test_drain()
	TEST_ASSERT_NULL(bay.payload, "Clearing the var slot empties the tracked value")
	TEST_ASSERT_EQUAL(bay.notices, 2, "Clearing publishes the second tracked change")
	TEST_ASSERT(!QDELETED(cell), "Releasing an unowned slot preserves the extracted item")

/datum/engine_layering_window_probe
	var/received_action
	var/list/received_payload
	var/datum/received_state
	var/deliveries = 0

/datum/engine_layering_window_probe/input_window_action(action, list/payload, datum/state)
	received_action = action
	received_payload = payload
	received_state = state
	deliveries++

/datum/unit_test/dq_engine_layering_window_dispatch/Run()
	var/datum/engine_layering_window_probe/window = allocate(/datum/engine_layering_window_probe)
	var/datum/state = allocate(/datum)
	var/list/payload = list("selection" = 7)
	var/datum/input_event/ui_act/event = allocate(/datum/input_event/ui_act, null, window, "choose", payload, state)
	event.resolve()
	TEST_ASSERT_EQUAL(window.deliveries, 1, "A queued window action dispatches exactly once")
	TEST_ASSERT_EQUAL(window.received_action, "choose", "The action name reaches the declared presentation hook")
	TEST_ASSERT_EQUAL(window.received_payload, payload, "The original payload reaches the hook")
	TEST_ASSERT_EQUAL(window.received_state, state, "The original presentation state reaches the hook")
	qdel(state)
	TEST_ASSERT_NULL(event.state, "Deleting the presentation state clears the queued input reference")

/obj/engine_layering_graph_bay
	parent_type = /obj/e1_assembly
	var/opened = TRUE

CAPABILITIES(/obj/engine_layering_graph_bay)
	space(SPACE_CELL, door = nameof(opened))

/datum/unit_test/dq_engine_layering_graph_protrusion/Run()
	var/obj/engine_layering_graph_bay/bay = allocate(/obj/engine_layering_graph_bay)
	var/datum/capability/construction/definition = cap_of(bay, CAP_CONSTRUCTION)
	TEST_ASSERT_NOTNULL(definition?.graph, "The real assembly has a compiled construction graph")
	var/datum/graph_edge/edge = graph_first_edge(definition.graph, STAGE_DOOR_FRAME, STAGE_DOOR_WIRED)
	TEST_ASSERT_NOTNULL(edge, "The assembly has the frame-to-wired construction edge")
	set_var(edge, "protrudes", list("space" = SPACE_CELL, "because" = /datum/msg/space/close_first))
	var/datum/act/op/A = allocate(/datum/act/op)
	A.holder = bay
	TEST_ASSERT_NULL(space_door_hold_reason(A, SPACE_CELL), "No installed edge holds the open door at the frame stage")
	TEST_ASSERT(graph_advance(bay, STAGE_DOOR_WIRED), "The actual assembly advances to the protruding stage")
	TEST_ASSERT_EQUAL(space_door_hold_reason(A, SPACE_CELL), /datum/msg/space/close_first, "The engine sees the installed graph protrusion through the library hook")
	TEST_ASSERT(graph_undo(bay), "The actual assembly removes the installed stage")
	TEST_ASSERT_NULL(space_door_hold_reason(A, SPACE_CELL), "Undo releases the door again")
