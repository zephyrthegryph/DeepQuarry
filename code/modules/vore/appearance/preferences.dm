/**
 * Additional variables that must be defined on /mob/living/carbon/human
 * for use in code that is part of the vore modules.
 *
 * These variables are declared here (separately from the normal human_defines.dm)
 * in order to isolate VOREStation changes and ease merging of other codebases.
 */

// Additional vars
/mob/living/carbon/human

	// Horray Furries!
	var/hair_accessory_style_handle
	var/r_acc = 30
	var/g_acc = 30
	var/b_acc = 30
	var/r_acc2 = 30
	var/g_acc2 = 30
	var/b_acc2 = 30
	var/r_acc3 = 30
	var/g_acc3 = 30
	var/b_acc3 = 30

/// LC-refs: the hair_accessory_style this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/mob/living/carbon/human/proc/hair_accessory_style() as /datum/sprite_accessory/hair_accessory
	return om_resolve(hair_accessory_style_handle)
