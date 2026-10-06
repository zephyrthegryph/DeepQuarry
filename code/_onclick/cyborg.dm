/*
	Cyborg ClickOn()

	Cyborgs have no range restriction on empty-gripper Use, because it is basically an AI click.
	However, they do have a range restriction on item use, so they cannot do without the
	adjacency code.
*/

/// Can this cyborg act on a click at all right now?
/mob/living/silicon/robot/proc/can_click_act()
	return !(stat || lockdown || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || has_status(STAT_PARALYZED))

// Cyborg clicks route through the input router with the robot adapter (adapters.dm) when no op of the target answered them first. A machine's
// remote controls (a ctrl-click bolting a door) are remote() ops, reached through the cyborg's interface provider while its link works
// (library/mob/silicon.dm: a working restraining bolt or a camera view takes the interface away). Middle click cycles through modules.
/mob/living/silicon/robot/action_swap_hands(atom/A)
	cycle_modules()

/// A cyborg's Alternate is the target's own alt-click only: it has no loot panel.
/mob/living/silicon/robot/action_alternate(atom/target)
	target.click_alt(src)

// Not used by click code (the robot adapter handles Use); here for anything that calls them.
/mob/living/silicon/robot/UnarmedAttack(atom/A)
	actor_use(/datum/input_adapter/robot, src, A)
/mob/living/silicon/robot/RangedAttack(atom/A)
	actor_use(/datum/input_adapter/robot, src, A)
