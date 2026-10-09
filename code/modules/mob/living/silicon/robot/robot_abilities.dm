// Borg abilities. Player-facing robot self-actions - as opposed to admin/law-management verbs, which stay plain verbs - are ops with a
// menu(button =, bind =) binding that a capability brings to the robot; the robot (or an upgrade, or an admin) is the source that grants it.
// The op keys are the ABILITY_ID_* defines (code/__defines/abilities.dm).

MSG_DEF_SELF(robot_ability/no_light_power, "there isn't enough power to run your integrated light")
MSG_DEF_SELF(robot_ability/name_taken, "you can't pick another custom name; ask for a name change")
MSG_DEF_SELF(robot_ability/not_customizable, "your sprite cannot be customized")
MSG_DEF_SELF(robot_ability/nothing_to_purge, "you have nothing to purge")
MSG_DEF_SELF(robot_ability/no_sprite, "your sprite has no decals to control")
MSG_DEF_SELF(robot_ability/already_recoloured, "you've already recoloured yourself once - ask for a module reset for another")
MSG_DEF_SELF(robot_ability/no_riders, "you can't carry riders")
MSG_DEF_SELF(robot_ability/nothing_to_eat, "There's nothing nearby to robot nom.")
MSG_DEF_SELF(robot_ability/nothing_to_mount, "There's nothing nearby to robot mount/dismount.")

// ---------------------------------------------------------------------------
// Every robot grants itself these on Initialize() and revokes them in on_destroy() - never gated by death.

CAPABILITY_DEF(robot_utility, CAP_ROBOT_UTILITY, key = NONE)

/datum/capability/def/robot_utility/entries()
	return list(
		op("toggle_lights", label("Toggle lights"), menu(button = "Toggle lights", bind = "ability_robot_toggle_lights"),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, lights_have_power), because = MSG(robot_ability/no_light_power))),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_lights))),
		op("customize_appearance", label("Customize appearance"), menu(button = "Customize appearance", bind = "ability_robot_customize_appearance"),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, sprite_customizable), because = MSG(robot_ability/not_customizable))),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_customize_appearance))),
		op("toggle_glowy_stomach", label("Toggle glowing stomach & accents"), menu(button = "Toggle glowing stomach & accents", bind = "ability_robot_toggle_glowy_stomach"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_glowy_stomach))),
		op("spark_plug", label("Emit sparks"), menu(button = "Emit sparks", bind = "ability_robot_spark_plug"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_spark_plug))),
		op("toggle_grabbability", label("Toggle pickup"), menu(button = "Toggle pickup", bind = "ability_robot_toggle_grabbability"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_grabbability))),
		op("purge_nutrition", label("Purge nutrition"), menu(button = "Purge nutrition", bind = "ability_robot_purge_nutrition"),
			needs(req_conscious(), req(TYPE_PROC_REF(/mob/living/silicon/robot, has_excess_nutrition), because = MSG(robot_ability/nothing_to_purge))),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_purge_nutrition))),
		op("toggle_decals", label("Control decals & animations"), menu(button = "Control decals & animations", bind = "ability_robot_toggle_decals"),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, has_sprite_datum), because = MSG(robot_ability/no_sprite))),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_decals))),
		op("nom", label("Robot nom"), menu(button = "Robot nom", bind = "ability_robot_nom"),
			needs(req_conscious(), req(TYPE_PROC_REF(/mob/living/silicon/robot, has_nom_candidates), because = MSG(robot_ability/nothing_to_eat))),
			asks(/datum/prompt/choice/ability_pick, fields = list("title" = "Robot Nom", "question" = "Eat whom?", "choices" = computed(TYPE_PROC_REF(/mob/living/silicon/robot, nom_candidate_choices))), step = "target"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_nom))))

/// TRUE unless the light is off and there's no power to turn it on.
/mob/living/silicon/robot/proc/lights_have_power(datum/act/op/A)
	return lights_on || has_power

/mob/living/silicon/robot/proc/ability_toggle_lights(datum/act/op/A)
	set_lights(!lights_on)
	to_chat(src, span_filter_notice("You [lights_on ? "enable" : "disable"] your integrated light."))
	return OP_OK

/mob/living/silicon/robot/proc/sprite_customizable(datum/act/op/A)
	return sprite_datum && sprite_datum.has_extra_customization

/mob/living/silicon/robot/proc/ability_customize_appearance(datum/act/op/A)
	sprite_datum.handle_extra_customization(src)
	return OP_OK

/mob/living/silicon/robot/proc/ability_toggle_glowy_stomach(datum/act/op/A)
	set_glowy_enabled(!glowy_enabled)
	if(glowy_enabled)
		to_chat(src, span_filter_notice("Your stomach will now glow and any naturally glowing accents you have will now appear!"))
	else
		to_chat(src, span_filter_notice("Your stomach will no longer glow, and any naturally glowing accents you have will be hidden!"))
	return OP_OK

/// So you can still sparkle on demand without violence.
/mob/living/silicon/robot/proc/ability_spark_plug(datum/act/op/A)
	to_chat(src, span_filter_notice("You harmlessly spark."))
	fx_sparks(src, 5, FALSE)
	return OP_OK

/// Grisp the preyborgs with consent (and allows for your borg to still be pet).
/mob/living/silicon/robot/proc/ability_toggle_grabbability(datum/act/op/A)
	grabbable = !grabbable
	to_chat(src, span_filter_notice("You feel [grabbable ? "more" : "less"] grabbable."))
	return OP_OK

/mob/living/silicon/robot/proc/has_excess_nutrition(datum/act/op/A)
	return nutrition > 1000

/mob/living/silicon/robot/proc/ability_purge_nutrition(datum/act/op/A)
	set_nutrition(1000)
	to_chat(src, span_warning("You have purged most of the nutrition lingering in your systems."))
	return OP_OK

/mob/living/silicon/robot/proc/has_sprite_datum(datum/act/op/A)
	return !!sprite_datum

/mob/living/silicon/robot/proc/ability_toggle_decals(datum/act/op/A)
	decal_control.tgui_interact(src)
	return OP_OK

/// Who the robot could eat now: living mobs within one tile but itself. Fresh every time, never cached: the world moves between key presses.
/mob/living/silicon/robot/proc/nom_candidates()
	return living_mobs_in_view(1) - src

/mob/living/silicon/robot/proc/has_nom_candidates(datum/act/op/A)
	return length(nom_candidates()) > 0

/mob/living/silicon/robot/proc/nom_candidate_choices(datum/act/op/A)
	return nom_candidates()

/// Allows you to eat someone.
/mob/living/silicon/robot/proc/ability_nom(datum/act/op/A)
	var/mob/living/prey = A.step_value("target")
	if(!istype(prey) || !(prey in nom_candidates()))
		return OP_FAILED
	feed_grabbed_to_self(src, prey)
	return OP_OK

/// Picks one target for an ability from a list that was built when the question opened; it must still be there when the answer lands.
/datum/prompt/choice/ability_pick
	timeout = 0

/datum/prompt/choice/ability_pick/recheck_extra()
	if(isnull(value))
		return
	var/atom/selected = value
	if(!istype(selected) || QDELETED(selected))
		return "gone"

// ---------------------------------------------------------------------------
// A robot that its player may name grants itself this beside the utility set (a drone does not: may_pick_name()).

CAPABILITY_DEF(robot_naming, CAP_ROBOT_NAMING, key = NONE)

/datum/capability/def/robot_naming/entries()
	return list(
		op("pick_name", label("Pick name"), menu(button = "Pick name", bind = "ability_robot_pick_name"),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, can_pick_custom_name), because = MSG(robot_ability/name_taken))),
			asks(/datum/prompt/text, fields = list("title" = "Name change", "question" = "You are a robot. Enter a name, or leave blank for the default name.", "max_len" = MAX_NAME_LEN, "encode" = FALSE, "name_text" = TRUE, "timeout" = 0), step = "name"),
			on_interrupt(TYPE_PROC_REF(/mob/living/silicon/robot, ability_name_cancelled)),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_pick_name))))

/// Whether the robot grants itself the pick-name ability.
/mob/living/silicon/robot/proc/may_pick_name()
	return TRUE

/// TRUE while no custom name has been picked yet.
/mob/living/silicon/robot/proc/can_pick_custom_name(datum/act/op/A)
	return !custom_name

/// The answer is the name; a blank one (or a cancel, ability_name_cancelled()) is the default name.
/mob/living/silicon/robot/proc/ability_pick_name(datum/act/op/A)
	robot_name_entered(A.answer?.value)
	return OP_OK

/mob/living/silicon/robot/proc/ability_name_cancelled(datum/act/op/A)
	robot_name_entered("")

/mob/living/silicon/robot/proc/robot_name_entered(entered)
	var/newname = sanitizeSafe(entered || "", MAX_NAME_LEN)
	if (newname && !custom_name)
		custom_name = newname
		sprite_name = newname

	updatename()

// ---------------------------------------------------------------------------
// Granted while the robot is alive (add_robot_verbs()/remove_robot_verbs() in robot.dm), the same as the verbs they replaced.

CAPABILITY_DEF(robot_live, CAP_ROBOT_LIVE, key = NONE)

/datum/capability/def/robot_live/entries()
	return list(
		op("sensor_mode", label("Toggle sensor augmentation"), menu(button = "Toggle sensor augmentation", bind = "ability_robot_sensor_mode"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_sensor_mode))),
		op("mount", label("Robot mount/dismount"), menu(button = "Robot mount/dismount", bind = "ability_robot_mount"),
			needs(req_conscious(), req(TYPE_PROC_REF(/mob/living/silicon/robot, can_carry_riders), because = MSG(robot_ability/no_riders)),
				req(TYPE_PROC_REF(/mob/living/silicon/robot, has_riders_or_mount_candidates), because = MSG(robot_ability/nothing_to_mount))),
			asks(/datum/prompt/choice/ability_pick, fields = list("title" = "Robot Mount", "question" = "Let ride:", "choices" = computed(TYPE_PROC_REF(/mob/living/silicon/robot, mount_candidate_choices))), step = "rider", when = TYPE_PROC_REF(/mob/living/silicon/robot, has_no_riders)),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_mount))),
		op("toggle_module_1", label("Module 1"), menu(button = "Module 1", bind = "ability_robot_toggle_module_1"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_module_1))),
		op("toggle_module_2", label("Module 2"), menu(button = "Module 2", bind = "ability_robot_toggle_module_2"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_module_2))),
		op("toggle_module_3", label("Module 3"), menu(button = "Module 3", bind = "ability_robot_toggle_module_3"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_module_3))))

/// Medical/Security HUD controller for borgs: augments the visual feed with internal sensor overlays.
/mob/living/silicon/robot/proc/ability_sensor_mode(datum/act/op/A)
	sensor_type = !sensor_type
	to_chat(src, "You [sensor_type ? "enable" : "disable"] your sensors.")
	toggle_sensor_mode()
	return OP_OK

/mob/living/silicon/robot/proc/can_carry_riders(datum/act/op/A)
	return can_buckle

/mob/living/silicon/robot/proc/has_no_riders(datum/act/op/A)
	return !LAZYLEN(buckled_mob_list())

/// Adjacent, unbuckled living mobs that could ride.
/mob/living/silicon/robot/proc/mount_candidates()
	. = list()
	for(var/mob/living/candidate as anything in living_mobs(1))
		if(candidate != src && candidate.Adjacent(src) && !candidate?.buckled_to())
			. += candidate

/// A rider to dismount, or somebody to pick.
/mob/living/silicon/robot/proc/has_riders_or_mount_candidates(datum/act/op/A)
	return LAZYLEN(buckled_mob_list()) || length(mount_candidates()) > 0

/mob/living/silicon/robot/proc/mount_candidate_choices(datum/act/op/A)
	return mount_candidates()

/**
 * Dismounts everyone already riding instead of picking a new rider - the same "the ability toggles between two different actions" shape the
 * legacy verb had. When nobody's riding, lets the picked adjacent, unbuckled living mob ride on you.
 */
/mob/living/silicon/robot/proc/ability_mount(datum/act/op/A)
	var/list/riders = buckled_mob_list()
	if(LAZYLEN(riders))
		for(var/rider in riders.Copy())
			riding_datum?.force_dismount(rider)
		return OP_OK
	var/mob/living/rider = A.step_value("rider")
	if(!istype(rider) || !(rider in mount_candidates()))
		return OP_FAILED
	if(buckle_mob(rider))
		act_message(rider, src, others = span_notice("%U% starts riding %T%!"))
	return OP_OK

/mob/living/silicon/robot/proc/ability_toggle_module_1(datum/act/op/A)
	toggle_module(1)
	return OP_OK

/mob/living/silicon/robot/proc/ability_toggle_module_2(datum/act/op/A)
	toggle_module(2)
	return OP_OK

/mob/living/silicon/robot/proc/ability_toggle_module_3(datum/act/op/A)
	toggle_module(3)
	return OP_OK

// ---------------------------------------------------------------------------
// Granted while the config allows recolouring (add_robot_verbs() in robot.dm) or by an admin (player effects).

CAPABILITY_DEF(robot_recolour, CAP_ROBOT_RECOLOUR, key = NONE)

/datum/capability/def/robot_recolour/entries()
	return list(
		op("recolour", label("Recolour module"), menu(button = "Recolour module", bind = "ability_robot_recolour"),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot, not_recoloured), because = MSG(robot_ability/already_recoloured))),
			asks(/datum/prompt/colormatrix, fields = list("title" = "Robot Recolor", "question" = "Allows you to recolor yourself", "preview" = computed(TYPE_PROC_REF(/mob/living/silicon/robot, recolour_preview)), "ui_state" = computed(TYPE_PROC_REF(/mob/living/silicon/robot, recolour_ui_state))), step = "matrix"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_recolour))))

/mob/living/silicon/robot/proc/not_recoloured(datum/act/op/A)
	return !has_recoloured

/// The window paints us in place (and sets has_recoloured); there is no answer to act on.
/mob/living/silicon/robot/proc/ability_recolour(datum/act/op/A)
	return OP_OK

/mob/living/silicon/robot/proc/recolour_preview(datum/act/A)
	return src

/mob/living/silicon/robot/proc/recolour_ui_state(datum/act/A)
	return GLOB.tgui_conscious_state

// ---------------------------------------------------------------------------
// Granted once, permanently, by the upgrade item that installs it (code/game/objects/items/robot/robot_upgrades.dm).

CAPABILITY_DEF(robot_vtec, CAP_ROBOT_VTEC, key = NONE)

/datum/capability/def/robot_vtec/entries()
	return list(
		op("toggle_vtec", label("Toggle VTEC"), menu(button = "Toggle VTEC", bind = "ability_robot_toggle_vtec"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot, ability_toggle_vtec))))

/mob/living/silicon/robot/proc/ability_toggle_vtec(datum/act/op/A)
	vtec_active = !vtec_active
	hud_used.toggle_vtec_control()
	to_chat(src, span_filter_notice("VTEC module [vtec_active ? "enabled" : "disabled"]."))
	return OP_OK
