// Behaviour pins for the timed actions of code/game and code/modules (worker B, wave 9), recorded on the legacy task_timed / task_start forms before
// they become ops with wait(). Same harness as dq_timed_pin_w8_behaviour.dm: every pin drives the real click path and records the duration (not done a
// second before, done a second after), the start message, what a move, a dropped held item or a lost target does, and what completion does and says.
//
// Pinned: xenoarcheaology/boulder.dm (measure, dig), food/kitchen/microwave.dm (clean).
// Unpinned, by reason:
//  unpinned: code/game/objects/structures/stasis_cage.dm: needs a simple_mob netted in an energy net and a mouse-drop path
//  unpinned: code/game/objects/structures/medical_stand.dm, watercloset.dm, alien/alien.dm, fence.dm, girders.dm: need a buckled/grabbed victim or a heavy fixture (wall stock, lock kit)
//  unpinned: code/game/objects/trash_eating.dm, overmap/ships/ship.dm, food/kitchen/gibber.dm, cooking_machines/fryer.dm, recycling/disposal_*.dm: need a vore belly, a living victim or a grab
//  unpinned: code/game/turfs/*, mining/mine_turfs.dm, mining/shelter_atoms.dm, mining/fulton.dm: need a generated turf type, a beacon or a shelter capsule fixture
//  unpinned: code/modules/clothing/spacesuits/rig/*, clothing/clothing.dm, clothing/gloves/antagonist.dm: need a worn rig, micro/macro pair or a pickpocket stance
//  unpinned: code/modules/multiz/*, ventcrawl/ventcrawl.dm: need a multi-z fixture or a vent network
//  unpinned: crafting/crafting.dm, fishing/fishing.dm, scripting/Implementations/Telecomms.dm, combat_ai/brain/brain.dm, economy/cash_register.dm: busy guards or tasks driven by a client UI or worker AI, not a click
//  unpinned: modules/client/stored_item.dm, resleeving/sleevecard.dm, eventkit/*, body/plans/nanoform.dm, materials/engineering/material_diagnostics.dm: need a client, a mind or a full subsystem fixture
//  unpinned: the remaining files of .lane/groupB.files (medical, surgery, detectivework, makeup, spells, persistence, samples, hydroponics, anomalies, redgate, artifice, reagents hose, research handler): need a tool or reagent fixture beyond one click

/datum/unit_test/dq_timed_pin_w9b
	abstract_type = /datum/unit_test/dq_timed_pin_w9b
	parent_type = /datum/unit_test/dq_timed_pin_w8

// ---- A boulder measured with a measuring tape: 1.5 seconds, then it reports its depth ----

/datum/unit_test/dq_timed_pin_w9b/boulder_measure
	duration = 1.5 SECONDS
	began = "You extend"
	finished = "has been excavated to a depth of"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w9b/boulder_measure/setup_scene()
	user = person()
	target = allocate(/obj/structure/boulder, get_step(run_loc_floor_bottom_left, NORTH))
	held = hold(/obj/item/measuring_tape)

/datum/unit_test/dq_timed_pin_w9b/boulder_measure/is_done()
	return said(user, finished)

// ---- A boulder dug with a pickaxe: as long as the pick's digspeed, and the boulder goes with a deep enough dig ----

/datum/unit_test/dq_timed_pin_w9b/boulder_dig
	began = "You start"
	finished = "You finish"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w9b/boulder_dig/setup_scene()
	user = person()
	held = hold(/obj/item/pickaxe)
	var/obj/item/pickaxe/P = held
	duration = P.digspeed
	target = allocate(/obj/structure/boulder, get_step(run_loc_floor_bottom_left, NORTH))

/datum/unit_test/dq_timed_pin_w9b/boulder_dig/is_done()
	return said(user, finished)

// ---- A dirty microwave cleaned with soap: 2 seconds, then it is clean ----

/datum/unit_test/dq_timed_pin_w9b/microwave_clean
	duration = 2 SECONDS
	began = "You start to clean"
	finished = "You have cleaned"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w9b/microwave_clean/setup_scene()
	user = person()
	var/obj/machinery/microwave/M = allocate(/obj/machinery/microwave, get_step(run_loc_floor_bottom_left, NORTH))
	M.set_dirty(MAX_MICROWAVE_DIRTINESS)
	target = M
	held = hold(/obj/item/soap)

/datum/unit_test/dq_timed_pin_w9b/microwave_clean/is_done()
	var/obj/machinery/microwave/M = target
	return !QDELETED(M) && M.dirty == 0

/datum/unit_test/dq_timed_pin_w9b/microwave_clean/extra_pin()
	// a dirty microwave refuses anything that is not a cleaner
	setup_scene()
	var/obj/item/I = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	user.drop_from_inventory(held)
	user.put_in_active_hand(I)
	held = I
	refused("It's dirty!")
	clear_scene()
