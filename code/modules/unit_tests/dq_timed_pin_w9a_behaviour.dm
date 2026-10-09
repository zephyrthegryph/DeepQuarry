// Behaviour pins for the timed actions of code/game/objects/items and code/game (worker group A, wave 9), recorded on the legacy task_timed /
// task_start forms before they become ops with wait(). Same harness as dq_timed_pin_w8_behaviour.dm (base type /datum/unit_test/dq_timed_pin_w8).
//
// Pinned: soap (bite, scrub a decal), lockpick (simple door), mop (a tile), shock maul (charge), chainsaw (pull the string).
// Already pinned elsewhere (skipped): handcuffs, nanopaste, implanter, tanks, vore egg, uav cell (dq_timed_pin_w1..w7).
// unpinned: code/game/gamemodes/changeling/state/powers/absorb.dm: needs a grab on a living victim and the changeling state machine
// unpinned: code/game/gamemodes/cult/construct_spells.dm: needs a construct with an aimed spell and a marker image
// unpinned: code/game/gamemodes/cult/ritual.dm: tome scribing asks a rune-name prompt and needs a cultist
// unpinned: code/game/gamemodes/malfunction/newmalf_ability_trees/tree_interdiction.dm: needs an AI with a malf datum and a cyborg
// unpinned: code/game/mecha/components/_component.dm: needs a mecha with a damaged component and nanopaste
// unpinned: code/game/mecha/equipment/tools/clamp.dm: needs a piloted mecha and a bolted firedoor or airlock
// unpinned: code/game/mecha/equipment/tools/hardpoint_actuator.dm: needs a piloted mecha and a hardpoint module
// unpinned: code/game/mecha/equipment/tools/orescanner.dm: needs a piloted mecha with the scanner and ore
// unpinned: code/game/objects/effects/decals/posters/posters.dm: needs a wall to face and the roll's constructor-built poster
// unpinned: code/game/objects/items/crayons.dm: the draw starts from a two-step prompt answer, not a click
// unpinned: code/game/objects/items/devices/aicard.dm: needs a live AI to grab
// unpinned: code/game/objects/items/devices/body_snatcher.dm: needs two minded mobs
// unpinned: code/game/objects/items/devices/defib.dm: needs a dead patient with a brain and the paddles' power
// unpinned: code/game/objects/items/devices/denecrotizer.dm: needs a dead mob and a ghost
// unpinned: code/game/objects/items/devices/extrapolator.dm: needs a diseased host
// unpinned: code/game/objects/items/devices/hacktool.dm: needs a target airlock with a security level and a hack prompt
// unpinned: code/game/objects/items/devices/mind_binder.dm: needs minded mobs
// unpinned: code/game/objects/items/devices/multitool.dm: needs a robot with an exploitable component
// unpinned: code/game/objects/items/devices/paicard.dm: needs a pAI and the card's topic window
// unpinned: code/game/objects/items/devices/radio/radio_service.dm: a doc-comment mention only
// unpinned: code/game/objects/items/devices/scanners/sleevemate.dm: needs a minded body, a NIF and the mate's topic window
// unpinned: code/game/objects/items/devices/translocator.dm: needs a vore belly and a prompt
// unpinned: code/game/objects/items/fantasy_items.dm: needs a grab and a bath or toilet fixture
// unpinned: code/game/objects/items/ghost_hunting/trap.dm: needs a ghost or an escaping mob inside the trap
// unpinned: code/game/objects/items/ghost_hunting/weapons.dm: needs a ghost target and the beam effects
// unpinned: code/game/objects/items/holosign_creator.dm: the sign is made on a turf the creator charges; busy claim needs a holosign fixture
// unpinned: code/game/objects/items/leash.dm: needs a leashed pet and the leash's own click states
// unpinned: code/game/objects/items/stacks/medical.dm: needs injured limbs on a patient
// unpinned: code/game/objects/items/stacks/sandbags.dm: needs a recipe window and outdoor ground
// unpinned: code/game/objects/items/stacks/stack.dm: starts from the stack window's build act, not a click
// unpinned: code/game/objects/items/toys/toys.dm: needs the stuffed toy fixture with a hidden item
// unpinned: code/game/objects/items/weapons/AI_modules.dm: needs an AI upload console and a module
// unpinned: code/game/objects/items/weapons/RCD.dm: needs a build prompt, a charge and a target turf
// unpinned: code/game/objects/items/weapons/RMS.dm: needs a charged cell and a machine
// unpinned: code/game/objects/items/weapons/RPD.dm: needs pipe layer state and a pipe on the turf
// unpinned: code/game/objects/items/weapons/explosives.dm: the planted charge explodes from after(), which would fire inside a later scene
// unpinned: code/game/objects/items/weapons/implants/implantreagent.dm: needs an implanted reagent implant on a mob
// unpinned: code/game/objects/items/weapons/inducer.dm: needs a charged inducer and a chargeable device with a beam
// unpinned: code/game/objects/items/weapons/material/kitchen.dm: needs a loaded utensil and a feedable victim
// unpinned: code/game/objects/items/weapons/material/material_weapons.dm: repair and sharpen start from a kit's own click states
// unpinned: code/game/objects/items/weapons/medigun/linked_medigun.dm: needs the linked backpack and a patient
// unpinned: code/game/objects/items/weapons/mop_deploy.dm: a DROPDEL item that exists only in a robot's module hand
// unpinned: code/game/objects/items/weapons/storage/pouches.dm: needs a worn pouch with a delayed removal
// unpinned: code/game/objects/items/weapons/weaponry.dm: needs a buckled mob struggling free of a bola or net

// ---- Soap: bitten by oneself, half a second ----

/datum/unit_test/dq_timed_pin_w8/soap_bite
	duration = 0.5 SECONDS
	began = "raise the soap to your mouth"
	drop_cancels = TRUE
	loss_cancels = FALSE // legacy: the user is the target; nothing else to lose
	legacy_click = TRUE // soap still does its work in afterattack()

/datum/unit_test/dq_timed_pin_w8/soap_bite/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = O_MOUTH
	target = user
	held = hold(/obj/item/soap)

/datum/unit_test/dq_timed_pin_w8/soap_bite/is_done()
	var/obj/item/soap/S = held
	return !QDELETED(S) && S.bites > 0

// ---- Soap: scrubbing a cleanable decal away, the soap's cleaning speed ----

/datum/unit_test/dq_timed_pin_w8/soap_scrub_decal
	duration = 3.5 SECONDS
	began = "You begin to scrub"
	drop_cancels = TRUE
	legacy_click = TRUE // soap still does its work in afterattack()

/datum/unit_test/dq_timed_pin_w8/soap_scrub_decal/setup_scene()
	user = person()
	dq_give_zone_sel(user)
	user.zone_sel.selecting = BP_TORSO
	target = allocate(/obj/effect/decal/cleanable/dirt, get_step(user, NORTH))
	held = hold(/obj/item/soap)

/datum/unit_test/dq_timed_pin_w8/soap_scrub_decal/is_done()
	return QDELETED(target)

// ---- A lockpick: a locked simple door, ten seconds a point of difficulty ----

/datum/unit_test/dq_timed_pin_w8/lockpick_door
	duration = 10 SECONDS
	began = "You start to pick the lock"
	finished = "Success"
	drop_cancels = TRUE
	loss_cancels = FALSE // legacy: the lockpick was the task's target, so losing the door cancelled nothing

/datum/unit_test/dq_timed_pin_w8/lockpick_door/setup_scene()
	user = person()
	var/obj/structure/simple_door/D = allocate(/obj/structure/simple_door, get_step(user, NORTH))
	D.locked = TRUE
	target = D
	held = hold(/obj/item/lockpick)

/datum/unit_test/dq_timed_pin_w8/lockpick_door/is_done()
	var/obj/structure/simple_door/D = target
	return !QDELETED(D) && !D.locked

/datum/unit_test/dq_timed_pin_w8/lockpick_door/extra_pin()
	// a door that is not locked is told so and nothing starts
	setup_scene()
	var/obj/structure/simple_door/D = target
	D.locked = FALSE
	refused("isn't locked")
	clear_scene()

// ---- A mop: a wet mop on a tile, the tile (not the decal clicked) is the task's target ----

/datum/unit_test/dq_timed_pin_w8/mop_tile
	duration = 4 SECONDS
	drop_cancels = TRUE
	loss_cancels = FALSE // legacy: the task's target was the turf under the decal
	/// The mop's water when the scene began.
	var/start_volume = 0

/datum/unit_test/dq_timed_pin_w8/mop_tile/setup_scene()
	user = person()
	target = allocate(/obj/effect/decal/cleanable/dirt, get_step(user, NORTH))
	held = hold(/obj/item/mop)
	held.reagents.add_reagent(REAGENT_ID_WATER, 10)
	start_volume = held.reagents.total_volume

/datum/unit_test/dq_timed_pin_w8/mop_tile/is_done()
	return !QDELETED(held) && held.reagents.total_volume < start_volume

/datum/unit_test/dq_timed_pin_w8/mop_tile/extra_pin()
	// a dry mop starts nothing
	setup_scene()
	held.reagents.clear_reagents()
	refused()
	clear_scene()

// ---- A shock maul: charged by hand (the op), two seconds; a maul without a cell is out of charge ----

/datum/unit_test/dq_timed_pin_w8/shock_maul_charge
	duration = 2 SECONDS
	menu_key = "self"
	finished = "It's hammer time"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/shock_maul_charge/setup_scene()
	user = person()
	held = hold(/obj/item/melee/shock_maul/loaded)
	target = held

/datum/unit_test/dq_timed_pin_w8/shock_maul_charge/is_done()
	var/obj/item/melee/shock_maul/M = held
	return !QDELETED(M) && M.status == 1

/datum/unit_test/dq_timed_pin_w8/shock_maul_charge/extra_pin()
	// without a power source nothing is charged
	setup_scene()
	var/obj/item/melee/shock_maul/M = held
	rel_take(M, nameof(/obj/item/melee/shock_maul::bcell))
	refused("out of charge")
	target = null
	tidy()

// ---- A chainsaw: the string pulled, a second and a half; the move and the drop fail it ----

/datum/unit_test/dq_timed_pin_w8/chainsaw_start
	duration = 1.5 SECONDS
	menu_key = "self"
	began = "You start pulling the string"
	finished = "loud grinding"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/chainsaw_start/setup_scene()
	user = person()
	held = hold(/obj/item/chainsaw)
	target = held

/datum/unit_test/dq_timed_pin_w8/chainsaw_start/is_done()
	var/obj/item/chainsaw/C = held
	return !QDELETED(C) && C.on
