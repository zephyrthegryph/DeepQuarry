/*
	Cyborg ClickOn()

	Cyborgs have no range restriction on attack_robot(), because it is basically an AI click.
	However, they do have a range restriction on item use, so they cannot do without the
	adjacency code.
*/

/// Can this cyborg act on a click at all right now?
/mob/living/silicon/robot/proc/can_click_act()
	return !(stat || lockdown || has_status(EFFECT_WEAKENED) || has_status(EFFECT_STUNNED) || has_status(EFFECT_PARALYZED))

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

// Cyborg clicks route through the input router with the robot adapter (adapters.dm).

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

/// A cyborg's empty-gripper Use (the robot adapter, adapters.dm). With no override,
/// `silicon_use` may make it a hand's Use; otherwise it interfaces like the AI.
/atom/proc/attack_robot(mob/user as mob)
	if(silicon_use & ROBOT_USE_HAND)
		return attack_hand(user)
	if(silicon_use & ROBOT_USE_HAND_ADJACENT)
		if(Adjacent(user))
			return attack_hand(user)
		return
	return attack_ai(user)
