// The pockets that draw from tracked state: the modular computer follows its program and its error screen, the device assembly its cover, the
// hand HUD the handcuffs on its mob, the look builder's invisibility part, the ability master the abilities it holds, and the robot the
// belly preference of its bellies.

/// A computer that records no window, with the interim program fixtures.
/obj/item/modular_computer/dq_draw_pocket
	hardware_flag = PROGRAM_LAPTOP

/obj/item/modular_computer/dq_draw_pocket/install_default_hardware()
	. = ..()
	install_hardware(new /obj/item/computer_hardware/processor_unit/small(src))
	install_hardware(new /obj/item/computer_hardware/hard_drive(src))

/obj/item/modular_computer/dq_draw_pocket/tgui_interact(mob/user, datum/tgui/ui)
	return

/datum/computer_file/program/dq_draw_pocket
	filename = "dq_draw_pocket"
	required_access = ACCESS_ENGINE
	program_icon_state = "dq_pocket_screen"

/// The program that runs shows its own screen, a program change redraws the computer, and the error screen replaces both.
/datum/unit_test/dq_draw_pocket_computer_follows_program_and_bsod

/datum/unit_test/dq_draw_pocket_computer_follows_program_and_bsod/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(interim_computer_actor_card(actor, T), "the actor is authorized")
	var/obj/item/modular_computer/dq_draw_pocket/computer = allocate(/obj/item/modular_computer/dq_draw_pocket, T)
	var/datum/computer_file/program/dq_draw_pocket/program = allocate(/datum/computer_file/program/dq_draw_pocket)
	TEST_ASSERT(computer.hard_drive.store_file(program), "the drive stores the program")
	computer.enable_computer(actor)
	refresh_flush()
	TEST_ASSERT(computer.enabled, "the computer is on")
	var/list/menu = dq_overlay_states(computer)
	TEST_ASSERT(("menu" in menu), "with no program it shows the menu screen: [json_encode(menu)]")
	TEST_ASSERT(!("dq_pocket_screen" in menu), "and not the program's")
	computer.run_program(program.filename, actor)
	refresh_flush()
	var/list/running = dq_overlay_states(computer)
	TEST_ASSERT(("dq_pocket_screen" in running), "starting a program redraws the computer with its screen, no call: [json_encode(running)]")
	computer.set_bsod(TRUE)
	refresh_flush()
	var/list/bsod = dq_overlay_states(computer)
	TEST_ASSERT(("bsod" in bsod), "the error screen is drawn: [json_encode(bsod)]")
	TEST_ASSERT(!("dq_pocket_screen" in bsod), "in place of the program's screen")
	computer.set_bsod(FALSE)
	refresh_flush()
	TEST_ASSERT(("dq_pocket_screen" in dq_overlay_states(computer)), "clearing it brings the program's screen back")
	computer.minimize_program(actor)
	refresh_flush()
	var/list/minimized = dq_overlay_states(computer)
	TEST_ASSERT(!("dq_pocket_screen" in minimized), "minimizing the program takes its screen off: [json_encode(minimized)]")
	TEST_ASSERT(("menu" in minimized), "and the menu is back")

/// Opening and closing a device assembly redraws it: `opened` is tracked.
/datum/unit_test/dq_draw_pocket_assembly_open_close

/datum/unit_test/dq_draw_pocket_assembly_open_close/Run()
	var/obj/item/assembly/electronic_assembly/device = allocate(/obj/item/assembly/electronic_assembly, test_floor())
	refresh_flush()
	var/closed_state = device.icon_state
	TEST_ASSERT(!findtext(closed_state, "-open"), "a closed device shows its closed state: [closed_state]")
	device.toggle_open(null)
	refresh_flush()
	TEST_ASSERT(findtext(device.icon_state, "-open"), "opening it redraws the open state: [device.icon_state]")
	device.toggle_open(null)
	refresh_flush()
	TEST_ASSERT_EQUAL(device.icon_state, closed_state, "closing it gives the closed state back")

/// A look that names an invisibility applies it, and a look that stops naming it gives the type default back.
/obj/dq_draw_pocket_hider
	name = "hider"
	icon = 'icons/obj/items.dmi'
	icon_state = "wrench"
	var/hidden = FALSE

TRACKED(/obj/dq_draw_pocket_hider, hidden)

/obj/dq_draw_pocket_hider/draw(datum/look/look)
	..()
	if(hidden)
		look.set_invisibility(INVISIBILITY_ABSTRACT)

/datum/unit_test/dq_draw_pocket_look_invisibility

/datum/unit_test/dq_draw_pocket_look_invisibility/Run()
	var/obj/dq_draw_pocket_hider/thing = allocate(/obj/dq_draw_pocket_hider, test_floor())
	refresh_flush()
	var/normal = thing.invisibility
	thing.set_hidden(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(thing.invisibility, INVISIBILITY_ABSTRACT, "a draw that names the invisibility applies it")
	thing.set_hidden(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(thing.invisibility, normal, "a draw that stops naming it gives the type default back")

/// The ability master hides while it holds no abilities and shows as one is added; removing the last hides it again.
/datum/unit_test/dq_draw_pocket_ability_master_visibility

/datum/unit_test/dq_draw_pocket_ability_master_visibility/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/atom/movable/screen/movable/ability_master/master = allocate(/atom/movable/screen/movable/ability_master, user)
	refresh_flush()
	TEST_ASSERT_EQUAL(master.invisibility, INVISIBILITY_ABSTRACT, "an empty master is hidden")
	master.add_ability("dq_pocket_ability")
	refresh_flush()
	TEST_ASSERT_EQUAL(master.invisibility, INVISIBILITY_NONE, "holding an ability shows it, with no sync call")
	var/atom/movable/screen/ability/ability = master.ability_objects[1]
	master.remove_ability(ability)
	refresh_flush()
	TEST_ASSERT_EQUAL(master.invisibility, INVISIBILITY_ABSTRACT, "removing the last ability hides it again")

/// Handcuffs put on and taken off a mob redraw its hand HUD.
/datum/unit_test/dq_draw_pocket_hand_hud_follows_handcuffs

/datum/unit_test/dq_draw_pocket_hand_hud_follows_handcuffs/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	if(!H.hud_used)
		H.set_hud_used(new /datum/hud(H))
		H.hud_used.instantiate()
	var/atom/movable/screen/inventory/hand/left = H.hud_used.l_hand_hud_object
	TEST_ASSERT(istype(left), "the human HUD has a left hand slot")
	refresh_flush()
	TEST_ASSERT(!("l_hand_hud_handcuffs" in dq_overlay_states(left)), "a free hand shows no handcuffs")
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, H.loc)
	TEST_ASSERT(H.equip_to_slot_if_possible(cuffs, SLOT_ID_HANDCUFFED, disable_warning = TRUE), "the cuffs go on")
	refresh_flush()
	var/list/cuffed = dq_overlay_states(left)
	TEST_ASSERT(("l_hand_hud_handcuffs" in cuffed), "the hand shows the cuffs, with no sync: [json_encode(cuffed)] (hud [!!left.owner_hud()], mob [left.owner_hud()?.mymob() == H], carbon [iscarbon(left.owner_hud()?.mymob())], cuffed [!!H.get_equipped_item(SLOT_ID_HANDCUFFED)], state [left.icon_state], watchers [length(H.rel_watchers)])")
	H.remove_from_mob(cuffs)
	refresh_flush()
	TEST_ASSERT(!("l_hand_hud_handcuffs" in dq_overlay_states(left)), "taking them off clears it")
