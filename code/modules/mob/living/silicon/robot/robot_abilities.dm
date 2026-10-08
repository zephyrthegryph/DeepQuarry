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
	also_requires = list(REQ_FIELD_NOT("custom_name", "you can't pick another custom name; ask for a name change"))

/datum/interaction/ability/self/robot_pick_name/applies_to(atom/target)
	return isrobot(target)

/mob/living/silicon/robot/proc/dq_do_pick_name(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	// A cancel answers "": the default name.
	open_request(src, /datum/prompt/text, PROC_REF(robot_name_entered), answerer = src, title = "Name change", question = "You are a robot. Enter a name, or leave blank for the default name.", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE, timeout = 0)
	return TRUE

/mob/living/silicon/robot/proc/robot_name_entered(datum/act/request/A)
	var/newname = sanitizeSafe(A.answer ? A.answer.value : "", MAX_NAME_LEN)
	if (newname && !custom_name)
		custom_name = newname
		sprite_name = newname

	updatename()

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
	set_glowy_enabled(!glowy_enabled)
	if(glowy_enabled)
		to_chat(src, span_filter_notice("Your stomach will now glow and any naturally glowing accents you have will now appear!"))
	else
		to_chat(src, span_filter_notice("Your stomach will no longer glow, and any naturally glowing accents you have will be hidden!"))
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
	fx_sparks(src, 5, FALSE)
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
	set_nutrition(1000)
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
	// The window paints us in place (and sets has_recoloured); there's no answer to act on.
	open_request(src, /datum/prompt/colormatrix, null, answerer = src, title = "Robot Recolor", question = "Allows you to recolor yourself", preview = src, ui_state = GLOB.tgui_conscious_state)
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

// ---------------------------------------------------------------------------
// Targeted, picked abilities (code/datums/abilities/ability.dm's /picker):
// the legacy verb argument syntax (`mob/living/T in living_mobs(1)`) gave a
// native target picker for free; these ask for one explicitly instead.

/datum/interaction/ability/picker/robot_nom
	id = ABILITY_ID_ROBOT_NOM
	name = "Robot nom"
	category = ABILITY_CAT_UTILITY
	picker_title = "Robot Nom"
	picker_prompt = "Eat whom?"
	requires = list(REQ_CONSCIOUS)
	effect = /mob/living/proc/dq_do_robot_nom

/datum/interaction/ability/picker/robot_nom/candidates(mob/living/actor)
	return actor.living_mobs_in_view(1) - actor

/// Allows you to eat someone.
/mob/living/proc/dq_do_robot_nom(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	return actor.feed_grabbed_to_self(actor, src)

/datum/interaction/ability/picker/robot_mount
	id = ABILITY_ID_ROBOT_MOUNT
	name = "Robot mount/dismount"
	category = ABILITY_CAT_UTILITY
	picker_title = "Robot Mount"
	picker_prompt = "Let ride:"
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON(PRED_ACTOR, /mob/living/silicon/robot/proc/dq_pred_can_buckle, "you can't carry riders"),
	)
	effect = /mob/living/proc/dq_do_robot_mount

/mob/living/silicon/robot/proc/dq_pred_can_buckle(mob/living/silicon/robot/actor, atom/target, obj/item/held)
	return actor.can_buckle || "you can't carry riders"

/**
 * Dismounts everyone already riding instead of picking a new rider - the
 * same "the ability toggles between two different actions" shape the legacy
 * verb had. When nobody's riding, picks from adjacent, unbuckled living mobs.
 */
/datum/interaction/ability/picker/robot_mount/pick_target(mob/living/silicon/robot/actor)
	var/list/riders = actor?.buckled_mob_list()
	if(LAZYLEN(riders))
		for(var/rider in riders.Copy())
			actor.riding_datum?.force_dismount(rider)
		return null
	return ..()

/datum/interaction/ability/picker/robot_mount/candidates(mob/living/silicon/robot/actor)
	. = list()
	for(var/mob/living/candidate as anything in actor.living_mobs(1))
		if(candidate != actor && candidate.Adjacent(actor) && !candidate?.buckled_to())
			. += candidate

/// Let people ride on you. Runs on the rider (the picked target); `actor` is the robot.
/mob/living/proc/dq_do_robot_mount(mob/living/silicon/robot/actor, obj/item/held, datum/interaction/ability/interaction)
	if(actor.buckle_mob(src))
		act_message(src, actor, others = span_notice("%U% starts riding %T%!"))
	return TRUE

// ---------------------------------------------------------------------------
// Module select: one ability per slot (1-3), sharing an effect that reads the
// slot off the ability singleton itself (a fixed, per-subtype argument - the
// simplest shape for "argument-supplying" abilities: subtype vars, read
// through the `interaction` the effect is already handed).

/datum/interaction/ability/self/robot_toggle_module
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/proc/dq_do_toggle_module
	/// Which module slot (1-3) this instance selects.
	var/module_index

/datum/interaction/ability/self/robot_toggle_module/applies_to(atom/target)
	return isrobot(target)

/datum/interaction/ability/self/robot_toggle_module/module_1
	id = ABILITY_ID_ROBOT_TOGGLE_MODULE_1
	name = "Module 1"
	module_index = 1

/datum/interaction/ability/self/robot_toggle_module/module_2
	id = ABILITY_ID_ROBOT_TOGGLE_MODULE_2
	name = "Module 2"
	module_index = 2

/datum/interaction/ability/self/robot_toggle_module/module_3
	id = ABILITY_ID_ROBOT_TOGGLE_MODULE_3
	name = "Module 3"
	module_index = 3

/mob/living/silicon/robot/proc/dq_do_toggle_module(mob/actor, obj/item/held, datum/interaction/ability/self/robot_toggle_module/interaction)
	toggle_module(interaction.module_index)
	return TRUE
