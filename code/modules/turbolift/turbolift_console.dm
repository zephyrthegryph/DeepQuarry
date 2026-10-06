// Base type, do not use.
/obj/structure/lift
	resistance_flags = BOMB_PROOF
	name = "turbolift control component"
	icon = 'icons/obj/turbolift.dmi'
	anchored = TRUE
	density = FALSE
	plane = MOB_PLANE

	var/tmp/datum/turbolift/lift

/obj/structure/lift/set_dir(newdir)
	. = ..()
	pixel_x = 0
	pixel_y = 0
	if(dir & NORTH)
		pixel_y = -32
	else if(dir & SOUTH)
		pixel_y = 32
	else if(dir & EAST)
		pixel_x = -32
	else if(dir & WEST)
		pixel_x = 32

/// `stance`: the touch's stance (a tgui button press is a plain press).
/obj/structure/lift/proc/pressed(mob/user, stance = I_HELP)
	if(!istype(user, /mob/living/silicon))
		if(stance == I_HURT)
			act_message(user, null, others = span_danger("%U% hammers on the lift button!"))
		else
			act_message(user, null, others = span_infoplain(span_bold("%U%") + " presses the lift button."))

/obj/structure/lift
	silicon_use = SILICON_USE_HAND

CAPABILITIES(/obj/structure/lift)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	param(nameof(lift), pos = 1)

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/lift/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	attack_hand(user)
	return OP_OK

DECLARE_INTERACTIONS(/obj/structure/lift, INTERACT_HAND_UNGATED_AS(I_HURT, "Hammer on it", PROC_REF(interaction_hand)), INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/lift/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	return interact(user, interaction.stance)

/// `stance`: the touch's stance, passed on to pressed().
/obj/structure/lift/interact(mob/user, stance = I_HELP)
	if(!lift().is_functional())
		return 0
	return 1
// End base.

// Button. No HTML interface, just calls the associated lift to its floor.
/obj/structure/lift/button
	name = "elevator button"
	desc = "A call button for an elevator. Be sure to hit it three hundred times."
	icon_state = "button"
	var/light_up = FALSE
	req_access = list(ACCESS_EVA)
	var/datum/turbolift_floor/floor
TRACKED(/obj/structure/lift/button, light_up)

/obj/structure/lift/button/relations()
	. = ..()
	. += rel_one(nameof(floor), back = nameof(/datum/turbolift_floor::ext_panel))
/datum/turbolift_floor/relations()
	. = ..()
	. += rel_one(nameof(ext_panel), back = nameof(/obj/structure/lift/button::floor))

/obj/structure/lift/button/proc/reset()
	set_light_up(FALSE)
	update_icon()

// Hit it with a PDA or ID to enable priority call mode
EXTEND_INTERACTIONS(/obj/structure/lift/button, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/lift/button/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/card/id/id = W.GetID()
	if(istype(id))
		if(!check_access(id))
			play_sfx(src, SFX_MACHINES_BUZZ_TWO)
			return INTERACTION_HANDLED_PASS
		lift().priority_mode()
		if(floor == lift().current_floor())
			lift().open_doors()
		else
			lift().queue_move_to(floor)
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/structure/lift/button/interact(mob/user, stance = I_HELP)
	if(!..())
		return
	if(lift().fire_mode || lift().priority_mode)
		play_sfx(src, SFX_MACHINES_BUZZ_TWO)
		return
	light_up()
	pressed(user, stance)
	if(floor == lift().current_floor() && !(lift().target_floor()))	//Make sure we're not going anywhere before opening doors
		lift().open_doors()
		after(src, 0.3 SECONDS, PROC_REF(reset))
		return
	lift().queue_move_to(floor)

/obj/structure/lift/button/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/structure/lift/button/proc/light_up()
	set_light_up(TRUE)
	update_icon()

/obj/structure/lift/button/draw(datum/look/look)
	..()
	if(lift().fire_mode)
		look.state("button_fire")
	else if(lift().priority_mode)
		look.state("button_pri")
	else if(light_up)
		look.state("button_lit")
	else
		look.state(initial(icon_state))

// End button.

// Panel. Lists floors (HTML), moves with the elevator, schedules a move to a given floor.
/obj/structure/lift/panel
	name = "elevator control panel"
	desc = "A control panel for moving the elevator. There's a slot for swiping IDs to enable additional controls."
	icon_state = "panel"
	req_access = list(ACCESS_EVA)
	req_one_access = list(ACCESS_HEADS, ACCESS_ATMOSPHERICS, ACCESS_MEDICAL)

// Hit it with a PDA or ID to enable priority call mode
EXTEND_INTERACTIONS(/obj/structure/lift/panel, \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_OBSERVER("View", TYPE_PROC_REF(/atom, interaction_interact)), \
)

/// Old attackby.
/obj/structure/lift/panel/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/card/id/id = W.GetID()
	if(istype(id))
		if(!check_access(id))
			play_sfx(src, SFX_MACHINES_BUZZ_TWO)
			return INTERACTION_HANDLED_PASS
		lift().update_fire_mode(!lift().fire_mode)
		if(lift().fire_mode)
			audible_message(span_danger("Firefighter Mode Activated.  Door safeties disabled.  Manual control engaged."), runemessage = "SCREECH")
			play_sfx(src, SFX_MACHINES_AIRALARM, volume_channel = VOLUME_CHANNEL_ALARMS)
		else
			audible_message(span_warning("Firefighter Mode Deactivated. Door safeties enabled.  Automatic control engaged."), runemessage = "ding")
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/structure/lift/panel/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/structure/lift/panel/interact(mob/user)
	if(!..())
		return

	tgui_interact(user)

CAPABILITIES(/obj/structure/lift/panel)
	interface("Turbolift")
	without("ui_open")
	op("move_to_floor", ui_act("move_to_floor", arg("ref", schema_ref())), then(PROC_REF(ui_act_move_to_floor)))
	op("toggle_doors", ui_act("toggle_doors"), then(PROC_REF(ui_act_toggle_doors)))
	op("emergency_stop", ui_act("emergency_stop"), then(PROC_REF(ui_act_emergency_stop)))

/// /obj/structure/lift/panel's window data.
/obj/structure/lift/panel/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["doors_open"] = lift().doors_are_open()
	data["fire_mode"] = lift().fire_mode

	var/list/floors = list()
	for(var/i in lift().floors.len to 1 step -1)
		var/datum/turbolift_floor/floor = lift().floors[i]
		floors.Add(list(list(
			"id" = i,
			"ref" = "\ref[floor]",
			"queued" = (floor in lift().queued_floors),
			"target" = (lift().target_floor() == floor),
			"current" = (lift().current_floor() == floor),
			"label" = floor.label,
			"name" = floor.name,
		)))
	data["floors"] = floors

	return data

/obj/structure/lift/panel/proc/ui_act_move_to_floor(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(isnull(ref))
		return FALSE
	. = TRUE
	lift().queue_move_to(ref)
	if(.)
		pressed(user)

/obj/structure/lift/panel/proc/ui_act_toggle_doors(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	if(lift().doors_are_open())
		lift().close_doors()
	else
		lift().open_doors()
	if(.)
		pressed(user)

/obj/structure/lift/panel/proc/ui_act_emergency_stop(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	lift().emergency_stop()
	if(.)
		pressed(user)

/obj/structure/lift/panel/draw(datum/look/look)
	..()
	if(lift().fire_mode)
		look.state("panel_fire")
	else
		look.state(initial(icon_state))

// End panel.

/// the lift this refers to (a relation view: it reads null once the target is deleted).
/obj/structure/lift/proc/lift() as /datum/turbolift
	return lift
