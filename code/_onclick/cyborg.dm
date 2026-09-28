/*
	Cyborg ClickOn()

	Cyborgs have no range restriction on empty-gripper Use, because it is basically an AI click.
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

// A cyborg's modifier actions: a target's silicon hook (ai.dm), else the ordinary effect.
// The restraining bolt is checked once, here. Middle click cycles through modules.
/mob/living/silicon/robot/action_swap_hands(atom/A)
	cycle_modules()

/mob/living/silicon/robot/action_quick(atom/target)
	if(remote_interface_blocked(target))
		return
	target.silicon_quick(src)

/mob/living/silicon/robot/action_inspect(atom/target)
	if(remote_interface_blocked(target))
		return
	if(!target.silicon_inspect(src))
		target.inspected_by(src)

/mob/living/silicon/robot/action_pull(atom/target)
	if(remote_interface_blocked(target))
		return
	if(!target.silicon_pull(src))
		base_click_ctrl(target)

/mob/living/silicon/robot/action_alternate(atom/target)
	if(remote_interface_blocked(target))
		return
	target.silicon_alternate(src)

// Not used by click code (the robot adapter handles Use); here for anything that calls them.
/mob/living/silicon/robot/UnarmedAttack(atom/A)
	actor_use(/datum/input_adapter/robot, src, A)
/mob/living/silicon/robot/RangedAttack(atom/A)
	actor_use(/datum/input_adapter/robot, src, A)
