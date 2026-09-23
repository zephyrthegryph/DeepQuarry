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

// ---------------------------------------------------------------------------

/datum/interaction/ability/self/robot_pick_name
	id = ABILITY_ID_ROBOT_PICK_NAME
	name = "Pick name"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_pick_name

/datum/interaction/ability/self/robot_pick_name/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_do_pick_name(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	if(custom_name)
		to_chat(src, "You can't pick another custom name. [isshell(src) ? "" : "Go ask for a name change."]")
		return FALSE
	var/newname = sanitizeSafe(tgui_input_text(src, "You are a robot. Enter a name, or leave blank for the default name.", "Name change", "", MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
	if(newname)
		custom_name = newname
		sprite_name = newname
	updatename()
	return TRUE

/datum/interaction/ability/self/robot_customize_appearance
	id = ABILITY_ID_ROBOT_CUSTOMIZE_APPEARANCE
	name = "Customize appearance"
	category = ABILITY_CAT_UTILITY
	requires = list(REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/proc/dq_pred_customizable, "your sprite cannot be customized"))
	effect = /mob/living/silicon/robot/proc/dq_do_customize_appearance

/datum/interaction/ability/self/robot_customize_appearance/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_pred_customizable(mob/living/silicon/robot/actor, atom/target, obj/item/held)
	return (actor.sprite_datum && actor.sprite_datum.has_extra_customization) || "your sprite cannot be customized"

/mob/living/silicon/robot/proc/dq_do_customize_appearance(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	sprite_datum.handle_extra_customization(src)
	return TRUE

/datum/interaction/ability/self/robot_toggle_glowy_stomach
	id = ABILITY_ID_ROBOT_TOGGLE_GLOWY_STOMACH
	name = "Toggle glowing stomach & accents"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_toggle_glowy_stomach

/datum/interaction/ability/self/robot_toggle_glowy_stomach/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_do_toggle_glowy_stomach(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	glowy_enabled = !glowy_enabled
	if(glowy_enabled)
		to_chat(src, span_filter_notice("Your stomach will now glow and any naturally glowing accents you have will now appear!"))
	else
		to_chat(src, span_filter_notice("Your stomach will no longer glow, and any naturally glowing accents you have will be hidden!"))
	update_icon()
	return TRUE

/datum/interaction/ability/self/robot_spark_plug
	id = ABILITY_ID_ROBOT_SPARK_PLUG
	name = "Emit sparks"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_spark_plug

/datum/interaction/ability/self/robot_spark_plug/applies_to(atom/target)
	return isrobot(target)

/// So you can still sparkle on demand without violence.
/mob/living/silicon/robot/proc/dq_do_spark_plug(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	to_chat(src, span_filter_notice("You harmlessly spark."))
	spark_system.start()
	return TRUE

/datum/interaction/ability/self/robot_toggle_grabbability
	id = ABILITY_ID_ROBOT_TOGGLE_GRABBABILITY
	name = "Toggle pickup"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_toggle_grabbability

/datum/interaction/ability/self/robot_toggle_grabbability/applies_to(atom/target)
	return isrobot(target)

/// Grisp the preyborgs with consent (and allows for your borg to still be pet).
/mob/living/silicon/robot/proc/dq_do_toggle_grabbability(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	grabbable = !grabbable
	to_chat(src, span_filter_notice("You feel [grabbable ? "more" : "less"] grabbable."))
	return TRUE

/datum/interaction/ability/self/robot_purge_nutrition
	id = ABILITY_ID_ROBOT_PURGE_NUTRITION
	name = "Purge nutrition"
	category = ABILITY_CAT_UTILITY
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/proc/dq_pred_has_excess_nutrition, "you have nothing to purge"),
	)
	effect = /mob/living/silicon/robot/proc/dq_do_purge_nutrition

/datum/interaction/ability/self/robot_purge_nutrition/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_pred_has_excess_nutrition(mob/living/silicon/robot/actor, atom/target, obj/item/held)
	return (actor.nutrition > 1000) || "you have nothing to purge"

/mob/living/silicon/robot/proc/dq_do_purge_nutrition(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	nutrition = 1000
	to_chat(src, span_warning("You have purged most of the nutrition lingering in your systems."))
	return TRUE

/datum/interaction/ability/self/robot_toggle_decals
	id = ABILITY_ID_ROBOT_TOGGLE_DECALS
	name = "Control decals & animations"
	category = ABILITY_CAT_UTILITY
	requires = list(REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/proc/dq_pred_has_sprite, "your sprite has no decals to control"))
	effect = /mob/living/silicon/robot/proc/dq_do_toggle_decals

/datum/interaction/ability/self/robot_toggle_decals/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_pred_has_sprite(mob/living/silicon/robot/actor, atom/target, obj/item/held)
	return actor.sprite_datum || "your sprite has no decals to control"

/mob/living/silicon/robot/proc/dq_do_toggle_decals(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	decal_control.tgui_interact(src)
	return TRUE

// ---------------------------------------------------------------------------
// These two are conditionally granted (add_robot_verbs()/remove_robot_verbs()
// in robot.dm - gated by whether the robot is alive, same as the verbs they
// replace were only present while alive).

/datum/interaction/ability/self/robot_sensor_mode
	id = ABILITY_ID_ROBOT_SENSOR_MODE
	name = "Toggle sensor augmentation"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_sensor_mode

/datum/interaction/ability/self/robot_sensor_mode/applies_to(atom/target)
	return isrobot(target)

/// Medical/Security HUD controller for borgs: augments the visual feed with internal sensor overlays.
/mob/living/silicon/robot/proc/dq_do_sensor_mode(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	sensor_type = !sensor_type
	to_chat(src, "You [sensor_type ? "enable" : "disable"] your sensors.")
	toggle_sensor_mode()
	return TRUE

/datum/interaction/ability/self/robot_recolour
	id = ABILITY_ID_ROBOT_RECOLOUR
	name = "Recolour module"
	category = ABILITY_CAT_UTILITY
	requires = list(REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/proc/dq_pred_not_recoloured, "you've already recoloured yourself once - ask for a module reset for another"))
	effect = /mob/living/silicon/robot/proc/dq_do_recolour

/datum/interaction/ability/self/robot_recolour/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_pred_not_recoloured(mob/living/silicon/robot/actor, atom/target, obj/item/held)
	return !actor.has_recoloured || "you've already recoloured yourself once - ask for a module reset for another"

/mob/living/silicon/robot/proc/dq_do_recolour(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	tgui_input_colormatrix(src, "Allows you to recolor yourself", "Robot Recolor", src, ui_state = GLOB.tgui_conscious_state)
	return TRUE

// ---------------------------------------------------------------------------
// Granted once, permanently, by the upgrade item that installs it
// (code/game/objects/items/robot/robot_upgrades.dm) - it's a one-way install
// with no matching removal, same as the verb it replaces.

/datum/interaction/ability/self/robot_toggle_vtec
	id = ABILITY_ID_ROBOT_TOGGLE_VTEC
	name = "Toggle VTEC"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_toggle_vtec

/datum/interaction/ability/self/robot_toggle_vtec/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_do_toggle_vtec(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	vtec_active = !vtec_active
	hud_used.toggle_vtec_control()
	to_chat(src, span_filter_notice("VTEC module [vtec_active ? "enabled" : "disabled"]."))
	return TRUE
