// Borg abilities (doc/rewrite/rules.md §5). Player-facing robot self-actions -
// as opposed to admin/law-management verbs, which stay plain verbs - move here
// one at a time.

/datum/interaction/ability/self/robot_toggle_lights
	id = ABILITY_ID_ROBOT_TOGGLE_LIGHTS
	name = "Toggle lights"
	category = ABILITY_CAT_UTILITY
	requires = list(REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/proc/dq_pred_lights_have_power, "there isn't enough power to run your integrated light"))
	effect = /mob/living/silicon/robot/proc/dq_do_toggle_lights

/datum/interaction/ability/self/robot_toggle_lights/applies_to(atom/target)
	return isrobot(target)

/// TRUE unless the light is off and there's no power to turn it on.
/mob/living/silicon/robot/proc/dq_pred_lights_have_power(mob/living/silicon/robot/actor, atom/target, obj/item/held)
	return (actor.lights_on || actor.has_power) || "there isn't enough power to run your integrated light"

/mob/living/silicon/robot/proc/dq_do_toggle_lights(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	set_lights(!lights_on)
	to_chat(src, span_filter_notice("You [lights_on ? "enable" : "disable"] your integrated light."))
	return TRUE
