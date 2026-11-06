// robot_upgrades.dm
// Contains various borg upgrades.

/obj/item/borg/upgrade
	name = "borg upgrade module."
	desc = "Protected by FRM."
	icon = 'icons/obj/module.dmi'
	icon_state = "cyborg_upgrade"
	///	Bitflags listing module compatibility. Used in the exosuit fabricator for creating sub-categories.
	var/list/module_flags = NONE
	var/locked = FALSE
	var/require_module = FALSE
	var/installed = FALSE

/obj/item/borg/upgrade/proc/action(mob/user, mob/living/silicon/robot/R)
	if(R.stat == DEAD)
		to_chat(user, span_warning("The [src] will not function on a deceased robot."))
		return TRUE
	return FALSE

/**
 * Undoes whatever `action()` did to `R` (verbs added, vars flipped, ...).
 * Called on module reset (see /mob/living/silicon/robot/proc/module_reset())
 * so an upgrade doesn't leave permanent side effects on a robot whose module
 * -- and therefore, conceptually, this upgrade along with it -- was reset.
 * No-ops by default; override alongside `action()` for any upgrade that
 * mutates the robot outside of `is_installed(R)`'s own detection surface.
 */
/obj/item/borg/upgrade/proc/remove_upgrade(mob/living/silicon/robot/R)
	return

/obj/item/borg/upgrade/proc/generic_error(mob/user, mob/living/silicon/robot/R, obj/item/borg/type)
	type = lowertext(initial(type.name))
	to_chat(R, span_warning("Upgrade mounting error! No suitable hardpoint for \the \"[type]\" detected!"))
	to_chat(user, span_warning("There's no mounting point for \the \"[type]\" module!"))

/obj/item/borg/upgrade/proc/software_error(mob/user, mob/living/silicon/robot/R, obj/item/borg/type)
	type = lowertext(initial(type.name))
	to_chat(R, span_warning("Upgrade installation error! Incompatibility with \the \"[type]\" detected!"))
	to_chat(user, span_warning("\The \"[type]\" upgrade is not compatibile!"))

/*	######################################################################################################
	# Utility section. All reusable upgrades without lasting effects, like renaming, reset, etc. go here.#
	######################################################################################################*/

/obj/item/borg/upgrade/utility
	module_flags = BORG_UTILITY

/obj/item/borg/upgrade/utility/reset
	name = "robotic module reset board"
	desc = "Used to reset a cyborg's module. Destroys any higher than basic upgrades applied to the robot."
	icon_state = "cyborg_upgrade1"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/utility/reset/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	R.module_reset()
	return TRUE

/*	###################################################################################
	# Basic section. All upgrades which effect the robot's variables directly go here.#
	###################################################################################*/

/obj/item/borg/upgrade/basic
	module_flags = BORG_BASIC

/*	###########################################################################
	# Advanced section. All upgrades which effect the robot's modules go here.#
	###########################################################################*/

/obj/item/borg/upgrade/advanced
	module_flags = BORG_ADVANCED

/*	###############################################
	# Unsorted section. All cargo modules go here.#
	###############################################*/

/obj/item/borg/upgrade/no_prod
	var/hidden_from_scan = FALSE//use this for unproduceable modules you want to hide from scanning (e.g. event tools / admeme)
