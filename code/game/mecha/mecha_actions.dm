//AEIOU
//
//THIS FILE CONTAINS THE CODE TO ADD THE HUD BUTTONS AND THE MECH ACTIONS THEMSELVES.
//
//
// I better get some free food for this..

//
/// Adding the buttons things to the player. The interactive, top left things, at least at time of writing.
/// If you want it to be only for a special mech, you have to go and make an override like in the durand mech.
//

/obj/mecha/proc/GrantActions(mob/living/user, human_occupant = 0)
	if(human_occupant)
		eject_action.Grant(user, src)
	internals_action.Grant(user, src)
	cycle_action.Grant(user, src)
	lights_action.Grant(user, src)
	stats_action.Grant(user, src)
	strafing_action.Grant(user, src)//The defaults.

	if(defence_mode_possible)
		defence_action.Grant(user, src)
	if(overload_possible)
		overload_action.Grant(user, src)
	if(smoke_possible)
		smoke_action.Grant(user, src)
	if(zoom_possible)
		zoom_action.Grant(user, src)
	if(thrusters_possible)
		thrusters_action.Grant(user, src)
	if(phasing_possible)
		phasing_action.Grant(user, src)
	if(switch_dmg_type_possible)
		switch_damtype_action.Grant(user, src)
	if(cloak_possible)
		cloak_action.Grant(user, src)

/obj/mecha/proc/RemoveActions(mob/living/user, human_occupant = 0)
	if(human_occupant)
		revoke_action(eject_action, user)
	revoke_action(internals_action, user)
	revoke_action(cycle_action, user)
	revoke_action(lights_action, user)
	revoke_action(stats_action, user)
	revoke_action(strafing_action, user)

	revoke_action(defence_action, user)
	revoke_action(smoke_action, user)
	revoke_action(zoom_action, user)
	revoke_action(thrusters_action, user)
	revoke_action(phasing_action, user)
	revoke_action(switch_damtype_action, user)
	revoke_action(overload_action, user)
	revoke_action(cloak_action, user)

/// Revokes one of our action buttons from `user` (a local, so an action's Remove() is not
/// mistaken for a list write).
/obj/mecha/proc/revoke_action(datum/action/innate/mecha/action, mob/living/user)
	action?.Remove(user, src)

//
////BUTTONS STUFF
//

/datum/action/innate/mecha
	check_flags = AB_CHECK_RESTRAINED | AB_CHECK_STUNNED | AB_CHECK_CONSCIOUS
	background_icon = 'icons/effects/actions_mecha.dmi'
	button_icon = 'icons/effects/actions_mecha.dmi'
	overlay_icon = 'icons/effects/actions_mecha.dmi'
	var/obj/mecha/chassis

/datum/action/innate/mecha/Grant(mob/living/L, obj/mecha/M)
	if(M)
		rel_set(src, nameof(chassis), M)
	..()

/datum/action/innate/mecha/mech_toggle_lights
	name = "Toggle Lights"
	button_icon_state = "mech_lights_off"

/datum/action/innate/mecha/mech_toggle_lights/Activate()
	button_icon_state = "mech_lights_[chassis.lights ? "off" : "on"]"
	build_all_button_icons()
	chassis.lights(action_owner())

/datum/action/innate/mecha/mech_toggle_internals
	name = "Toggle Internal Airtank Usage"
	button_icon_state = "mech_internals_off"

/datum/action/innate/mecha/mech_toggle_internals/Activate()
	button_icon_state = "mech_internals_[chassis.use_internal_tank ? "off" : "on"]"
	build_all_button_icons()
	chassis.internal_tank(action_owner())

/datum/action/innate/mecha/mech_view_stats
	name = "View stats"
	button_icon_state = "mech_view_stats"

/datum/action/innate/mecha/mech_view_stats/Activate()
	chassis.view_stats(action_owner())

/datum/action/innate/mecha/mech_eject
	name = "Eject From Mech"
	button_icon_state = "mech_eject"

/datum/action/innate/mecha/mech_eject/Activate()
	chassis.go_out()

/datum/action/innate/mecha/strafe
	name = "Toggle Mech Strafing"
	button_icon_state = "mech_strafe_off"

/datum/action/innate/mecha/strafe/Activate()
	button_icon_state = "mech_strafe_[chassis.strafing ? "off" : "on"]"
	build_all_button_icons()
	chassis.strafing(action_owner())

/datum/action/innate/mecha/mech_defence_mode
	name = "Toggle Mech defence mode"
	button_icon_state = "mech_defense_mode_off"

/datum/action/innate/mecha/mech_defence_mode/Activate()
	button_icon_state = "mech_defense_mode_[chassis.defence_mode ? "off" : "on"]"
	build_all_button_icons()
	chassis.defence_mode(action_owner())

/datum/action/innate/mecha/mech_overload_mode
	name = "Toggle Mech Leg Overload"
	button_icon_state = "mech_overload_off"

/datum/action/innate/mecha/mech_overload_mode/Activate()
	button_icon_state = "mech_overload_[chassis.overload ? "off" : "on"]"
	build_all_button_icons()
	chassis.overload(action_owner())

/datum/action/innate/mecha/mech_smoke
	name = "Toggle Mech Smoke"
	button_icon_state = "mech_smoke_off"

/datum/action/innate/mecha/mech_smoke/Activate()
	//button_icon_state = "mech_smoke_[chassis.smoke ? "off" : "on"]"
	//build_all_button_icons()	//Dual colors notneeded ATM
	chassis.smoke(action_owner())

/datum/action/innate/mecha/mech_zoom
	name = "Toggle Mech Zoom"
	button_icon_state = "mech_zoom_off"

/datum/action/innate/mecha/mech_zoom/Activate()
	button_icon_state = "mech_zoom_[chassis.zoom ? "off" : "on"]"
	build_all_button_icons()
	chassis.zoom(action_owner())

/datum/action/innate/mecha/mech_toggle_thrusters
	name = "Toggle Mech thrusters"
	button_icon_state = "mech_thrusters_off"

/datum/action/innate/mecha/mech_toggle_thrusters/Activate()
	button_icon_state = "mech_thrusters_[chassis.thrusters ? "off" : "on"]"
	build_all_button_icons()
	chassis.thrusters(action_owner())

/datum/action/innate/mecha/mech_cycle_equip	//I'll be honest, i don't understand this part, buuuuuut it works!
	name = "Cycle Equipment"
	button_icon_state = "mech_cycle_equip_off"

/datum/action/innate/mecha/mech_cycle_equip/Activate()

	var/list/available_equipment = list()
	available_equipment = chassis.equipment

	if(chassis.weapons_only_cycle)
		available_equipment = chassis.weapon_equipment || list()

	if(available_equipment.len == 0)
		chassis.occupant_message("No equipment available.")
		return
	if(!chassis.selected)
		rel_set(chassis, nameof(chassis.selected), available_equipment[1])
		chassis.occupant_message("You select [chassis.selected]")
		send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","eq_list",chassis.get_equipment_list())
		button_icon_state = "mech_cycle_equip_on"
		build_all_button_icons()
		return
	var/number = 0
	for(var/A in available_equipment)
		number++
		if(A == chassis.selected)
			if(available_equipment.len == number)
				rel_clear(chassis, nameof(chassis.selected))
				chassis.occupant_message("You switch to no equipment")
				button_icon_state = "mech_cycle_equip_off"
			else
				rel_set(chassis, nameof(chassis.selected), available_equipment[number+1])
				chassis.occupant_message("You switch to [chassis.selected]")
				button_icon_state = "mech_cycle_equip_on"
			send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","eq_list",chassis.get_equipment_list())
			build_all_button_icons()
			return

/datum/action/innate/mecha/mech_switch_damtype
	name = "Reconfigure arm microtool arrays"
	button_icon_state = "mech_damtype_brute"

/datum/action/innate/mecha/mech_switch_damtype/Activate()
	button_icon_state = "mech_damtype_[chassis.melee_damtype_icon()]"
	play_sfx(src, SFX_MECHA_MECHMOVE01)
	build_all_button_icons()
	chassis.query_damtype(action_owner())

/datum/action/innate/mecha/mech_toggle_phasing
	name = "Toggle Mech phasing"
	button_icon_state = "mech_phasing_off"

/datum/action/innate/mecha/mech_toggle_phasing/Activate()
	button_icon_state = "mech_phasing_[chassis.phasing ? "off" : "on"]"
	build_all_button_icons()
	chassis.phasing(action_owner())

/datum/action/innate/mecha/mech_toggle_cloaking
	name = "Toggle Mech phasing"
	button_icon_state = "mech_phasing_off"

/datum/action/innate/mecha/mech_toggle_cloaking/Activate()
	button_icon_state = "mech_phasing_[dq_get_cloaked(chassis) ? "off" : "on"]"
	build_all_button_icons()
	chassis.toggle_cloaking(action_owner())

/////
/////
/////		ACTUAL MECANICS FOR THE ACTIONS
/////		OVERLOAD, DEFENCE, SMOKE
/////
/////

/// Old verb "Toggle defence mode".
/obj/mecha/proc/mecha_verb_toggle_defence_mode(mob/user, obj/item/held)
	defence_mode(user)

// Capability requirements (old moved_inside() removing the verbs a mech can't use).
/obj/mecha/proc/pred_mecha_can_defence_mode(mob/actor, atom/target, obj/item/held)
	return defence_mode_possible
/obj/mecha/proc/pred_mecha_can_overload(mob/actor, atom/target, obj/item/held)
	return overload_possible
/obj/mecha/proc/pred_mecha_can_smoke(mob/actor, atom/target, obj/item/held)
	return smoke_possible
/obj/mecha/proc/pred_mecha_can_zoom(mob/actor, atom/target, obj/item/held)
	return zoom_possible
/obj/mecha/proc/pred_mecha_can_thrusters(mob/actor, atom/target, obj/item/held)
	return thrusters_possible
/obj/mecha/proc/pred_mecha_can_switch_damtype(mob/actor, atom/target, obj/item/held)
	return switch_dmg_type_possible
/obj/mecha/proc/pred_mecha_can_phasing(mob/actor, atom/target, obj/item/held)
	return phasing_possible
/obj/mecha/proc/pred_mecha_can_cloak(mob/actor, atom/target, obj/item/held)
	return cloak_possible

/obj/mecha/proc/defence_mode(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	play_sfx(src, SFX_MECHA_DURANDDEFENCEMODE)
	defence_mode = !defence_mode
	// The body plan adds the defence-mode deflection bonus (mech_body_plan().deflect_chance()).
	if(defence_mode)
		src.occupant_message(span_blue("You enable [src] defence mode."))
	else
		src.occupant_message(span_red("You disable [src] defence mode."))
	src.log_message("Toggled defence mode.", LOG_GAME)
	return

/// Old verb "Toggle leg actuators overload".
/obj/mecha/proc/mecha_verb_toggle_overload(mob/user, obj/item/held)
	overload(user)

/obj/mecha/proc/overload(mob/user)
	if(user.stat == 1)//No manipulating things while unconcious.
		return
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	if(get_integrity() < max_integrity - max_integrity/3)//Same formula as in movement, just beforehand.
		src.occupant_message(span_red("Leg actuators damage critical, unable to engage overload."))
		overload = 0	//Just to be sure
		return
	if(overload)
		overload = 0
		step_energy_drain = initial(step_energy_drain)
		src.occupant_message(span_blue("You disable leg actuators overload."))
	else
		overload = 1
		step_energy_drain = step_energy_drain*overload_coeff
		src.occupant_message(span_red("You enable leg actuators overload."))
	src.log_message("Toggled leg actuators overload.", LOG_GAME)
	play_sfx(src, SFX_MECHA_MECHANICAL_TOGGLE)
	return

/// Old verb "Activate Smoke".
/obj/mecha/proc/mecha_verb_toggle_smoke(mob/user, obj/item/held)
	smoke(user)

/obj/mecha/proc/smoke(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return

	if(smoke_reserve < 1)
		src.occupant_message(span_red("You don't have any smoke left in stock!"))
		return

	if(COOLDOWN_FINISHED(src, smoke_cooldown_end))
		smoke_reserve--	//Remove ammo
		src.occupant_message(span_red("Smoke fired. [smoke_reserve] usages left."))

		var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
		smoke.attach(src)
		smoke.set_up(10, 0, user.loc)
		smoke.start()
		play_sfx(src, SFX_EFFECTS_SMOKE)

		COOLDOWN_START(src, smoke_cooldown_end, smoke_cooldown)
	return

/// Old verb "Zoom".
/obj/mecha/proc/mecha_verb_toggle_zoom(mob/user, obj/item/held)
	zoom(user)

/obj/mecha/proc/zoom(mob/user)//This could use improvements but maybe later.
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	var/mob/living/_tmp_occ_11 = src?.slot_item(MECHA_SLOT_PILOT)
	if(_tmp_occ_11.client)
		src.zoom = !src.zoom
		src.log_message("Toggled zoom mode.", LOG_GAME)
		if(src.zoom)
			src.occupant_message(span_blue("Zoom mode enabled."))
		else
			src.occupant_message(span_red("Zoom mode disabled."))
		if(zoom)
			var/mob/living/_tmp_occ_12 = src?.slot_item(MECHA_SLOT_PILOT)
			_tmp_occ_12.set_viewsize(12)
			src?.slot_item(MECHA_SLOT_PILOT) << sound('sound/mecha/imag_enh.ogg',volume=50)
		else
			var/mob/living/_tmp_occ_13 = src?.slot_item(MECHA_SLOT_PILOT)
			_tmp_occ_13.set_viewsize() // Reset to default
	return

/// Old verb "Toggle thrusters".
/obj/mecha/proc/mecha_verb_toggle_thrusters(mob/user, obj/item/held)
	thrusters(user)

/obj/mecha/proc/thrusters(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	if(src?.slot_item(MECHA_SLOT_PILOT))
		if(get_charge() > 0)
			thrusters = !thrusters
			src.log_message("Toggled thrusters.", LOG_GAME)
			if(src.thrusters)
				src.occupant_message(span_blue("Thrusters enabled."))
			else
				src.occupant_message(span_red("Thrusters disabled."))
	return

/// Old verb "Change melee damage type".
/obj/mecha/proc/mecha_verb_switch_damtype(mob/user, obj/item/held)
	query_damtype(user)

/obj/mecha/proc/query_damtype(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(melee_damtype_chosen), answerer = user, title = "Damage Type", question = "Melee Damage Type", choices = list("Brute","Fire","Toxic"), buttons = TRUE, ask_flags = ASK_INSIDE, timeout = 0)

/obj/mecha/proc/melee_damtype_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/new_damtype = A.answer.value
	switch(new_damtype)
		if("Brute")
			melee_injury_kind = INJURY_BLUNT
			occupant_message("Your exosuit's hands form into fists.")
		if("Fire")
			melee_injury_kind = INJURY_BURN
			occupant_message("A torch tip extends from your exosuit's hand, glowing red.")
		if("Toxic")
			melee_injury_kind = INJURY_TOXIN
			occupant_message("A bone-chillingly thick plasteel needle protracts from the exosuit's palm.")
	occupant_message("Melee damage type switched to [new_damtype]")
	return

/// Old verb "Toggle phasing".
/obj/mecha/proc/mecha_verb_toggle_phasing(mob/user, obj/item/held)
	phasing(user)

/obj/mecha/proc/phasing(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	phasing = !phasing
	send_byjax(src?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","phasing_command","[phasing?"Dis":"En"]able phasing")
	if(phasing)
		src.occupant_message(span_blue("Enabled phasing."))
	else
		src.occupant_message(span_red("Disabled phasing."))
	return

/// Old verb "Toggle cloaking".
/obj/mecha/proc/mecha_verb_toggle_cloak(mob/user, obj/item/held)
	toggle_cloaking(user)

/obj/mecha/proc/toggle_cloaking(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return

	if(dq_get_cloaked(src))
		uncloak()
	else
		cloak()

	if(dq_get_cloaked(src))
		src.occupant_message(span_blue("Enabled cloaking."))
	else
		src.occupant_message(span_red("Disabled cloaking."))
	return

/// Old verb "Toggle weapons only cycling".
/obj/mecha/proc/mecha_verb_toggle_weapons_only_cycle(mob/user, obj/item/held)
	set_weapons_only_cycle(user)

/obj/mecha/proc/set_weapons_only_cycle(mob/user)
	if(user!=src?.slot_item(MECHA_SLOT_PILOT))
		return
	weapons_only_cycle = !weapons_only_cycle
	if(weapons_only_cycle)
		src.occupant_message(span_blue("Enabled weapons only cycling."))
	else
		src.occupant_message(span_red("Disabled weapons only cycling."))
	return

