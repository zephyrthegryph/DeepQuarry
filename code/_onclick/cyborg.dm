/*
	Cyborg ClickOn()

	Cyborgs have no range restriction on attack_robot(), because it is basically an AI click.
	However, they do have a range restriction on item use, so they cannot do without the
	adjacency code.
*/

/// Modifier clicks (shift, ctrl, alt, middle and their combinations) route
/// the same way for every mob. Returns TRUE if the click was a modifier click
/// and has been handled.
/mob/proc/dispatch_modifier_click(atom/A, list/modifiers, params)
	if(LAZYACCESS(modifiers, SHIFT_CLICK))
		if(LAZYACCESS(modifiers, MIDDLE_CLICK))
			ShiftMiddleClickOn(A)
			return TRUE
		if(LAZYACCESS(modifiers, CTRL_CLICK))
			CtrlShiftClickOn(A)
			return TRUE
		if(LAZYACCESS(modifiers, ALT_CLICK))
			alt_shift_click_on(A)
			return TRUE
		ShiftClickOn(A)
		return TRUE
	if(LAZYACCESS(modifiers, MIDDLE_CLICK))
		if(LAZYACCESS(modifiers, CTRL_CLICK))
			CtrlMiddleClickOn(A)
		else
			MiddleClickOn(A, params)
		return TRUE
	if(LAZYACCESS(modifiers, ALT_CLICK)) // alt and alt-gr (rightalt)
		if(LAZYACCESS(modifiers, RIGHT_CLICK))
			AltClickSecondaryOn(A)
		else
			AltClickOn(A)
		return TRUE
	if(LAZYACCESS(modifiers, CTRL_CLICK))
		CtrlClickOn(A)
		return TRUE
	return FALSE

/// Can this cyborg act on a click at all right now?
/mob/living/silicon/robot/proc/can_click_act()
	return !(stat || lockdown || weakened || stunned || paralysis)

/// A working restraining bolt blocks remote (AI-style) interfacing. The one
/// place the bolt is checked for clicks.
/mob/living/silicon/robot/proc/remote_interface_blocked(atom/target)
	return get_restraining_bolt() && target?.is_ai_remote_interface()

/// Does clicking this atom as a cyborg reach it through the AI interface
/// (and so get blocked by a restraining bolt)?
/atom/proc/is_ai_remote_interface()
	return FALSE

/obj/machinery/door/airlock/is_ai_remote_interface()
	return TRUE

/obj/machinery/power/apc/is_ai_remote_interface()
	return TRUE

/obj/machinery/turretid/is_ai_remote_interface()
	return TRUE

/mob/living/silicon/robot/ClickOn(atom/A, params)
	if(!checkClickCooldown())
		return

	if(check_click_intercept(params,A))
		return

	setClickCooldown(1)

	if(client.buildmode) // comes after object.Click to allow buildmode gui objects to be clicked
		build_click(src, client.buildmode, params, A)
		return

	var/list/modifiers = params2list(params)

	if(LAZYACCESS(modifiers, BUTTON4) || LAZYACCESS(modifiers, BUTTON5))
		return

	if(dispatch_modifier_click(A, modifiers, params))
		return

	if(!can_click_act())
		return

	face_atom(A) // change direction to face what you clicked on

	if(aiCamera && aiCamera.in_camera_mode)
		aiCamera.camera_mode_off()
		if(is_component_functioning(ROBOT_SLOT_CAMERA))
			aiCamera.captureimage(A, src)
		else
			to_chat(src, span_userdanger("Your camera isn't functional."))
		return

	var/obj/item/W = get_active_hand(A)

	// Cyborgs have no range-checking unless there is item use
	if(!W)
		// A bolted cyborg can't remotely interface with anything but its own module.
		if(get_restraining_bolt() && A.loc != module)
			return
		A.add_hiddenprint(src)
		A.attack_robot(src)
		return
	// buckled cannot prevent machine interlinking but stops arm movement
	if( buckled )
		return

	if(W == A)

		W.attack_self(src)
		return

	// cyborgs are prohibited from using storage items so we can I think safely remove (A.loc in contents)
	if(A == loc || (A in loc) || (A in contents))
		// No adjacency checks

		var/resolved = W.resolve_attackby(A, src, click_parameters = params)
		if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
			W.afterattack(A,src,1,params)
		return

	if(!isturf(loc))
		return

	var/sdepth = A.storage_depth_turf()
	if(isturf(A) || isturf(A.loc) || (sdepth <= MAX_STORAGE_REACH))
		if(A.Adjacent(src) || (W && W.attack_can_reach(src, A, W.reach))) // see adjacent.dm, allows robots to use ranged melee weapons
			SEND_SIGNAL(src, COMSIG_ROBOT_ITEM_ATTACK, W, src, params) //This is we ATTEMPTED to attack someone.
			var/resolved = W.resolve_attackby(A, src, click_parameters = params)
			if(!ITEM_INTERACT_CONSUMED(resolved) && A && W)
				W.afterattack(A, src, 1, params)
			return
		else
			W.afterattack(A, src, 0, params)
			return
	return

//Middle click cycles through selected modules.
/mob/living/silicon/robot/MiddleClickOn(atom/A)
	cycle_modules()
	return

//Give cyborgs hotkey clicks without breaking existing uses of hotkey clicks
// for non-doors/apcs. The restraining bolt is checked once, here.
/mob/living/silicon/robot/CtrlShiftClickOn(atom/target)
	if(remote_interface_blocked(target))
		return
	target.BorgCtrlShiftClick(src)

/mob/living/silicon/robot/ShiftClickOn(atom/target)
	if(remote_interface_blocked(target))
		return
	target.BorgShiftClick(src)

/mob/living/silicon/robot/CtrlClickOn(atom/target)
	if(remote_interface_blocked(target))
		return
	target.BorgCtrlClick(src)

/mob/living/silicon/robot/AltClickOn(atom/target)
	if(remote_interface_blocked(target))
		return
	target.BorgAltClick(src)

/atom/proc/BorgCtrlShiftClick(mob/living/silicon/robot/user) //forward to human click if not overriden
	click_ctrl_shift(user)

/obj/machinery/door/airlock/BorgCtrlShiftClick(mob/living/silicon/robot/user)
	AIclick_ctrl_shift(user)

/atom/proc/BorgShiftClick(mob/living/silicon/robot/user) //forward to human click if not overriden
	ShiftClick(user)

/obj/machinery/door/airlock/BorgShiftClick(mob/living/silicon/robot/user)  // Opens and closes doors! Forwards to AI code.
	AIShiftClick(user)

/atom/proc/BorgCtrlClick(mob/living/silicon/robot/user) //forward to human click if not overriden
	user.base_click_ctrl(src)

/obj/machinery/door/airlock/BorgCtrlClick(mob/living/silicon/robot/user) // Bolts doors. Forwards to AI code.
	ctrl_click_ai(user)

/obj/machinery/power/apc/BorgCtrlClick(mob/living/silicon/robot/user) // turns off/on APCs. Forwards to AI code.
	ctrl_click_ai(user)

/obj/machinery/turretid/BorgCtrlClick(mob/living/silicon/robot/user) //turret control on/off. Forwards to AI code.
	ctrl_click_ai(user)

/atom/proc/BorgAltClick(mob/living/silicon/robot/user)
	click_alt(user)
	return

/obj/machinery/door/airlock/BorgAltClick(mob/living/silicon/robot/user) // Eletrifies doors. Forwards to AI code.
	AIAltClick(user)

/obj/machinery/turretid/BorgAltClick(mob/living/silicon/robot/user) //turret lethal on/off. Forwards to AI code.
	AIAltClick(user)

/*
	As with AI, these are not used in click code,
	because the code for robots is specific, not generic.

	If you would like to add advanced features to robot
	clicks, you can do so here, but you will have to
	change attack_robot() above to the proper function
*/
/mob/living/silicon/robot/UnarmedAttack(atom/A)
	A.attack_robot(src)
/mob/living/silicon/robot/RangedAttack(atom/A)
	A.attack_robot(src)

/atom/proc/attack_robot(mob/user as mob)
	attack_ai(user)
	return
