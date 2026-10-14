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
	var/tmp/datum/sprite_accessory/hair_accessory/hair_accessory_style_static

/// A shared definition/flyweight (never cleared).
/mob/living/carbon/human/proc/hair_accessory_style() as /datum/sprite_accessory/hair_accessory
	return hair_accessory_style_static
