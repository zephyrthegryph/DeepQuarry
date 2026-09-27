/*
	AI ClickOn()

	Note currently ai restrained() returns 0 in all cases,
	therefore restrained code has been removed

	The AI can double click to move the camera (this was already true but is cleaner),
	or double click a mob to track them.

	Note that AI have no need for the adjacency proc, and so this proc is a lot cleaner.
*/
/mob/living/silicon/ai/DblClickOn(atom/A, params)
	if(client.buildmode) // comes after object.Click to allow buildmode gui objects to be clicked
		build_click(src, client.buildmode, params, A)
		return

	if(control_disabled || stat) return

	if(ismob(A))
		ai_actual_track(A)
	else
		A.move_camera_by_click()


// AI clicks route through the input router with the AI adapter (adapters.dm):
// its own click table, then attack_ai for Use.

/*
	AI has no need for the UnarmedAttack() and RangedAttack() procs,
	because the AI code is not generic;	attack_ai() is used instead.
	The below is only really for safety, or you can alter the way
	it functions and re-insert it above.
*/
/mob/living/silicon/ai/UnarmedAttack(atom/A)
	A.attack_ai(src)
/mob/living/silicon/ai/RangedAttack(atom/A)
	A.attack_ai(src)

/// The AI's Use (the AI adapter, adapters.dm). With no override, `silicon_use` says what it does.
/atom/proc/attack_ai(mob/user as mob)
	if(silicon_use & SILICON_USE_HAND)
		return attack_hand(user)
	if(silicon_use & SILICON_USE_UI)
		return tgui_interact(user)

/*
	Since the AI handles shift, ctrl, and alt-click differently
	than anything else in the game, atoms have separate procs
	for AI shift, ctrl, and alt clicking.
*/

/mob/living/silicon/ai/ShiftClickOn(atom/A)
	if(!control_disabled && A.AIShiftClick(src))
		return
	..()

/mob/living/silicon/ai/CtrlClickOn(atom/A)
	if(!control_disabled && A.ctrl_click_ai(src))
		return
	..()

/mob/living/silicon/ai/AltClickOn(atom/A)
	if(!control_disabled && A.AIAltClick(src))
		return
	..()

/mob/living/silicon/ai/MiddleClickOn(atom/A)
	if(!control_disabled && A.AIMiddleClick(src))
		return
	..()

/*
	The following criminally helpful code is just the previous code cleaned up;
	I have no idea why it was in atoms.dm instead of respective files.
*/

/atom/proc/AIclick_ctrl_shift()
	return

/atom/proc/AIShiftClick()
	return

/obj/machinery/door/airlock/AIShiftClick(mob/user)  // Opens and closes doors!
	add_fingerprint(user)
	user_toggle_open(user)
	return 1

/atom/proc/ctrl_click_ai(mob/user)
	return

/obj/machinery/door/airlock/ctrl_click_ai(mob/user) // Bolts doors
	add_fingerprint(user)
	toggle_bolt(user)
	return 1

/obj/machinery/power/apc/ctrl_click_ai(mob/user) // turns off/on APCs.
	add_fingerprint(user)
	toggle_breaker()
	return 1

/obj/machinery/turretid/ctrl_click_ai() //turns off/on Turrets
	enabled = !enabled
	updateTurrets()
	return TRUE

/atom/proc/AIAltClick(atom/A)
	return click_alt(A)

/obj/machinery/door/airlock/AIAltClick(mob/user) // Electrifies doors.
	add_fingerprint(user)
	if(electrified_until)
		electrify(0, 1)
	else
		electrify(-1, 1)
	// Clientside only notification
	var/turf/root_turf = get_turf(src)
	var/image/client_only/electrify_notice/zap = new('icons/hud/screen_gen.dmi', root_turf, electrified_until ? "stamina_crit" : "stamina_dead", OBFUSCATION_LAYER, SOUTH)
	zap.place_from_root(root_turf)
	zap.append_client(user.client)
	return 1

/obj/machinery/turretid/AIAltClick() //toggles lethal on turrets
	if(lethal_is_configurable)
		lethal = !lethal
		updateTurrets()
	return TRUE

/atom/proc/AIMiddleClick(mob/living/silicon/user)
	return 0

/obj/machinery/door/airlock/AIMiddleClick(mob/user) // Toggles door bolt lights.
	if(..())
		return
	add_fingerprint(user)
	if(wires.is_cut(WIRE_BOLT_LIGHT))
		to_chat(user, "The bolt lights wire is cut - The door bolt lights are permanently disabled.")
		return
	lights = !lights
	to_chat(user, span_notice("Lights are now [lights ? "on." : "off."]"))
	update_icon()
	return TRUE

//
// Override AdjacentQuick for AltClicking
//

/mob/living/silicon/ai/TurfAdjacent(turf/T)
	return (GLOB.cameranet && GLOB.cameranet.checkTurfVis(T))
