DECLARE_UI(/obj/item/medigun_backpack, "Medigun")

UI_DATA_REPLACE(/obj/item/medigun_backpack, "merge:ui_data_obj_item_medigun_backpack{volume:num,max_volume:num}")

/// The computed part of /obj/item/medigun_backpack's window data (declared on its UI_DATA row).
/obj/item/medigun_backpack/proc/ui_data_obj_item_medigun_backpack(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/obj/item/bork_medigun/medigun = get_medigun()
	if(!medigun)
		return list()
	var/mob/living/carbon/human/H = medigun.current_target()
	var/patientname
	var/patienthealth = 0
	var/list/patientdiagnosis
	var/patientstatus = 0
	var/list/bloodData = list()
	var/inner_bleeding = FALSE
	var/organ_damage = FALSE

	if(scapacitor?.get_rating() < 5)
		gridstatus = 3
	if(H)
		for(var/obj/item/organ/org in H.internal_organ_list())
			if(org.is_robotic())
				continue
			if(org.status & ORGAN_BLEEDING)
				inner_bleeding = TRUE
			if(org.damage >= 1 && !istype(org, /obj/item/organ/internal/brain))
				organ_damage = TRUE
		patientname = H
		patienthealth = H.vitality()
		var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/automation)
		patientdiagnosis = D?.report_data()
		qdel(D)
		patientstatus = H.stat
		if(H.vessel)
			bloodData["volume"] = round(H.vessel.get_reagent_amount("blood"))
			bloodData["max_volume"] = H.species.blood_volume
	var/list/data = list(
		"maintenance" = maintenance,
		"generator" = charging,
		"gridstatus" = gridstatus,
		"tankmax" = tankmax,
		"power_cell_status" = bcell ? bcell.percent() : null,
		"cell_status" = ccell ? (ccell.percent()/100) : null,
		"bruteheal_charge" = scapacitor ? brutecharge : null,
		"burnheal_charge" = scapacitor ? burncharge : null,
		"toxheal_charge" = scapacitor ? toxcharge : null,
		"bruteheal_vol" = sbin ? brutevol : null,
		"burnheal_vol" = sbin ? burnvol : null,
		"toxheal_vol" = sbin ? toxvol : null,
		"patient_name" = smodule ? patientname : null,
		"patient_health" = smodule ? patienthealth : null,
		"patient_diagnosis" = smodule ? patientdiagnosis : null,
		"blood_status" = smodule ? bloodData : null,
		"patient_status" = smodule ? patientstatus : null,
		"organ_damage" = smodule ? organ_damage : null,
		"inner_bleeding" = smodule ? inner_bleeding : null,
		"examine_data" = get_examine_data()
		)
	return data

/obj/item/medigun_backpack/proc/get_examine_data()
	var/obj/item/bork_medigun/medigun = get_medigun()

	return list(
		"smodule" = smodule ? list("name" = smodule.name, "range" = medigun.beam_range, "rating" = smodule.get_rating()) : null,
		"smanipulator" = smanipulator ? list("name" = smanipulator.name, "rating" = smaniptier) : null,
		"slaser" = slaser ? list("name" = slaser.name, "rating" = slaser.get_rating()) : null,
		"scapacitor" = scapacitor ? list("name" = scapacitor.name, "chargecap" = chargecap, "rating" = scapacitor.get_rating()) : null,
		"sbin" = sbin ? list("name" = sbin.name, "chemcap" = chemcap, "tankmax" = tankmax, "rating" = sbin.get_rating()) : null
	)

UI_ACT(/obj/item/medigun_backpack, "celleject", ui_act_celleject)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_celleject)
	. = TRUE
	cell_eject(ui.user)
	return TRUE

UI_ACT(/obj/item/medigun_backpack, "cancel_healing", ui_act_cancel_healing)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_cancel_healing)
	. = TRUE
	var/obj/item/bork_medigun/medigun = get_medigun()
	if(medigun?.busy)
		medigun.busy = MEDIGUN_CANCELLED
		return TRUE

UI_ACT(/obj/item/medigun_backpack, "toggle_maintenance", ui_act_toggle_maintenance)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_toggle_maintenance)
	. = TRUE
	maintenance = !maintenance
	return TRUE

UI_ACT(/obj/item/medigun_backpack, "rem_smodule", ui_act_rem_smodule)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_rem_smodule)
	. = TRUE
	if(!smodule || !maintenance)
		return FALSE
	smodule.forceMove(get_turf(loc))
	to_chat(ui.user, span_notice("You remove the [smodule] from \the [src]."))
	own_take(src, nameof(/obj/item/medigun_backpack::smodule))
	update_icon()
	return TRUE

UI_ACT(/obj/item/medigun_backpack, "rem_mani", ui_act_rem_mani)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_rem_mani)
	. = TRUE
	if(!smanipulator || !maintenance)
		return FALSE
	smanipulator.forceMove(get_turf(loc))
	to_chat(ui.user, span_notice("You remove the [smanipulator] from \the [src]."))
	own_take(src, nameof(/obj/item/medigun_backpack::smanipulator))
	smaniptier = 0
	update_icon()
	return TRUE

UI_ACT(/obj/item/medigun_backpack, "rem_laser", ui_act_rem_laser)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_rem_laser)
	. = TRUE
	if(!slaser || !maintenance)
		return FALSE
	slaser.forceMove(get_turf(loc))
	to_chat(ui.user, span_notice("You remove the [slaser] from \the [src]."))
	own_take(src, nameof(/obj/item/medigun_backpack::slaser))
	update_icon()
	return TRUE

UI_ACT(/obj/item/medigun_backpack, "rem_cap", ui_act_rem_cap)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_rem_cap)
	. = TRUE
	if(!scapacitor || !maintenance)
		return FALSE
	scapacitor.forceMove(get_turf(loc))
	to_chat(ui.user, span_notice("You remove the [scapacitor] from \the [src]."))
	own_take(src, nameof(/obj/item/medigun_backpack::scapacitor))
	update_icon()
	return TRUE

UI_ACT(/obj/item/medigun_backpack, "rem_bin", ui_act_rem_bin)
UI_ACT_PROC(/obj/item/medigun_backpack, ui_act_rem_bin)
	. = TRUE
	if(!sbin || !maintenance)
		return FALSE
	sbin.forceMove(get_turf(loc))
	to_chat(ui.user, span_notice("You remove the [sbin] from \the [src]."))
	own_take(src, nameof(/obj/item/medigun_backpack::sbin))
	sbintier = 0
	update_icon()
	return TRUE

/obj/item/medigun_backpack/inspected_by(mob/user)
	. = ..()
	var/obj/item/bork_medigun/medigun = get_medigun()
	if(!medigun)
		return
	tgui_interact(user)

/obj/item/medigun_backpack/proc/cell_eject(mob/user)
	if(!ccell)
		return FALSE
	charging = FALSE
	ccell.forceMove(get_turf(loc))
	if(user)
		to_chat(user, span_notice("You remove the [ccell] from \the [src]."))
	own_take(src, nameof(ccell))
	update_icon()
	return TRUE
