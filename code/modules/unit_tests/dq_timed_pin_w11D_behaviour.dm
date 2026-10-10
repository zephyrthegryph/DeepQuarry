// Behaviour pins for the timed actions of group D of timed actions round 3 (rewrite/timed3-D), on the harness of dq_timed_pin_w8_behaviour.dm
// (base type /datum/unit_test/dq_timed_pin_w8): every pin drives the real click path and records the duration (not done a second before, done a second
// after), the start message, what a move, a dropped held item or a lost target does, and what completion does and says. The scenes were written from
// the pre-conversion code of each file and run against the ops that replaced it.
//
// Pinned: clothing/glasses/glasses.dm (the prescription kit, both uses), structures/girders.dm (reinforcing), clothing/clothing.dm (a micro climbing out of
// shoes that are not worn), artifice/cursedform.dm (burning the form), clothing/gloves/antagonist.dm (a pocket swap).
// Unpinned, by reason:
//  unpinned: structures/stasis_cage.dm, structures/medical_stand.dm: a drag of a netted creature or a patient with a choice prompt; no fixture builds the net or the answer
//  unpinned: structures/transit_tubes.dm: not an actor's action (a pod travelling a tube network, timers on the pod)
//  unpinned: micro_structures.dm, trash_eating.dm: a micro inside a tunnel and a vore belly; the verb and the prompts are not driven by a click
//  unpinned: awaymissions/redgate.dm, body/plans/nanoform.dm, client/stored_item.dm: a laserdome team outfit, a dormant protean core and a client savefile
//  unpinned: clothing/spacesuits/rig/*: a worn, deployed rig and an airlock
//  unpinned: catalogue/cataloguer.dm: left on the legacy form (framework_gaps.md KD1)

/datum/unit_test/dq_timed_pin_w11D
	abstract_type = /datum/unit_test/dq_timed_pin_w11D
	parent_type = /datum/unit_test/dq_timed_pin_w8

// ---- The prescription kit used on somebody's eyes: five seconds, then it holds a prescription ----

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_measure
	duration = 5 SECONDS
	began = "begins making measurements"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_measure/setup_scene()
	user = person()
	target = person(get_step(user, NORTH))
	held = hold(/obj/item/glasses_kit)

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_measure/is_done()
	var/obj/item/glasses_kit/kit = held
	return !QDELETED(kit) && kit.scrip_loaded == 1

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_measure/extra_pin()
	// used on yourself it refuses at once and says so
	setup_scene()
	target = user
	refused("You can't use this on yourself")
	clear_scene()

// ---- The prescription kit used on a pair of glasses: needs a prescription, five seconds, the glasses change and the prescription is spent ----

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_prescribe
	duration = 5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_prescribe/setup_scene()
	user = person()
	target = allocate(/obj/item/clothing/glasses/regular, get_step(user, NORTH))
	var/obj/item/glasses_kit/kit = hold(/obj/item/glasses_kit)
	kit.set_scrip_loaded(1)
	held = kit

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_prescribe/is_done()
	var/obj/item/glasses_kit/kit = held
	var/obj/item/clothing/glasses/G = target
	return !QDELETED(kit) && !QDELETED(G) && G.prescription && kit.scrip_loaded == 0

/datum/unit_test/dq_timed_pin_w11D/glasses_kit_prescribe/extra_pin()
	// without a prescription nothing starts
	setup_scene()
	var/obj/item/glasses_kit/kit = held
	kit.set_scrip_loaded(0)
	refused("You need to build a prescription")
	clear_scene()

// ---- A girder ready to be reinforced: a sheet in hand, four seconds, one sheet is used ----

/datum/unit_test/dq_timed_pin_w11D/girder_reinforce
	duration = 4 SECONDS
	began = "Now reinforcing"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w11D/girder_reinforce/setup_scene()
	user = person()
	var/obj/structure/girder/G = allocate(/obj/structure/girder, get_step(user, NORTH))
	G.reinforcing = 1
	target = G
	var/obj/item/stack/material/steel/S = hold(/obj/item/stack/material/steel)
	S.set_amount(5, TRUE)
	held = S

/datum/unit_test/dq_timed_pin_w11D/girder_reinforce/is_done()
	var/obj/structure/girder/G = target
	var/obj/item/stack/material/steel/S = held
	return !QDELETED(G) && !isnull(G.reinf_material) && !QDELETED(S) && S.get_amount() == 4

// ---- A micro climbing out of shoes that lie on the floor: five seconds, then it stands beside them ----

/datum/unit_test/dq_timed_pin_w11D/shoes_micro_climb_out
	duration = 5 SECONDS
	loss_cancels = FALSE // the micro rides inside the shoes: deleting them deletes the scene

/datum/unit_test/dq_timed_pin_w11D/shoes_micro_climb_out/setup_scene()
	var/obj/item/clothing/shoes/boots/shoes = allocate(/obj/item/clothing/shoes/boots, get_step(run_loc_floor_bottom_left, NORTH))
	user = person(get_step(run_loc_floor_bottom_left, EAST))
	user.forceMove(shoes)
	target = shoes

/datum/unit_test/dq_timed_pin_w11D/shoes_micro_climb_out/start_click()
	test_chat_clear()
	var/obj/item/clothing/shoes/shoes = target
	shoes.container_resist(user)

/datum/unit_test/dq_timed_pin_w11D/shoes_micro_climb_out/is_done()
	return user.loc != target

// ---- The cursed form held to a lit lighter: two seconds, then it burns to ash ----

/datum/unit_test/dq_timed_pin_w11D/cursed_form_burn
	duration = 2 SECONDS
	began = "burning it slowly"
	finished = "turning it to ash"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w11D/cursed_form_burn/setup_scene()
	user = person()
	target = allocate(/obj/item/paper/carbon/cursedform, get_step(user, NORTH))
	var/obj/item/flame/lighter/L = hold(/obj/item/flame/lighter)
	L.lit = TRUE
	held = L

/datum/unit_test/dq_timed_pin_w11D/cursed_form_burn/is_done()
	return QDELETED(target)

// ---- Thieves' gloves, a disarm touch: a second's rummage, a second to take the left pocket's item ----

/datum/unit_test/dq_timed_pin_w11D/pickpocket_swap
	duration = 2 SECONDS
	legacy_click = TRUE // the gloves' Touch() is reached through the mob's own ClickOn()

/datum/unit_test/dq_timed_pin_w11D/pickpocket_swap/setup_scene()
	user = person()
	var/obj/item/clothing/gloves/sterile/thieves/gloves = allocate(/obj/item/clothing/gloves/sterile/thieves, run_loc_floor_bottom_left)
	user.equip_to_slot(gloves, SLOT_ID_GLOVES)
	user.set_use_stance(I_DISARM)
	var/mob/living/carbon/human/victim = person(get_step(user, NORTH))
	var/obj/item/pen/loot = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	victim.equip_to_slot(loot, SLOT_ID_POCKET_L)
	target = victim
	held = loot

/datum/unit_test/dq_timed_pin_w11D/pickpocket_swap/is_done()
	return !QDELETED(held) && user.get_equipped_item(SLOT_ID_POCKET_L) == held
