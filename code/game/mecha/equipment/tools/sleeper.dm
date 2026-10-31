/obj/item/mecha_parts/mecha_equipment/tool/sleeper
	name = "mounted sleeper"
	desc = "A sleeper. Mountable to an exosuit. (Can be attached to: Medical Exosuits)"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "sleeper_0"
	energy_drain = 20
	range = MECH_MELEE
	equip_cooldown = 30
	mech_flags = EXOSUIT_MODULE_MEDICAL
	var/inject_amount = 5
	required_type = list(/obj/mecha/medical)
	salvageable = 0
	allow_duplicate = TRUE

/// Life support is engaged on a loaded occupant.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/var/sustaining = FALSE

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/relation_definition/slot/occupant/mecha_sleeper
	holder = /obj/item/mecha_parts/mecha_equipment/tool/sleeper
	slot_id = OCCUPANT_SLOT_MECHA_SLEEPER
	name = "mounted sleeper"


/obj/item/mecha_parts/mecha_equipment/tool/sleeper/Exit(atom/movable/O)
	return 0

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/action(mob/living/carbon/human/target)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!action_checks(target))
		return
	if(!istype(target))
		return
	if(target?.buckled_to())
		occupant_message(span_infoplain("[target] will not fit into the sleeper because they are buckled to [target?.buckled_to()]."))
		return
	if(occupant)
		occupant_message(span_warning("The sleeper is already occupied"))
		return
	if(target.has_buckled_mobs())
		occupant_message(span_warning("\The [target] has other entities attached to it. Remove them first."))
		return
	occupant_message(span_infoplain("You start putting [target] into [src]."))
	chassis.visible_message(span_infoplain("[chassis] starts putting [target] into the [src]."))
	var/C = chassis.loc
	var/T = target.loc
	if(do_after_cooldown(target))
		if(chassis.loc!=C || target.loc!=T)
			return
		if(occupant)
			occupant_message(span_boldwarning("The sleeper is already occupied!"))
			return
		if(!move_into(src, OCCUPANT_SLOT_MECHA_SLEEPER, target))
			return
		occupant.set_stasis(/datum/body_effect/stasis/moderate, src)
		set_ready_state(FALSE)
		set_sustaining(TRUE)
		occupant_message(span_notice("[target] successfully loaded into [src]. Life support functions engaged."))
		chassis.visible_message(span_infoplain("[chassis] loads [target] into [src]."))
		src.mecha_log_message("[target] loaded. Life support functions engaged.")
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/go_out()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!occupant)
		return
	occupant_message(span_infoplain("[occupant] ejected. Life support functions disabled."))
	src.mecha_log_message("[occupant] ejected. Life support functions disabled.")
	occupant.set_stasis(null, src)
	slot_remove(occupant, get_turf(src))
	set_sustaining(FALSE)
	set_ready_state(TRUE)
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/detach()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(occupant)
		occupant_message(span_infoplain("Unable to detach [src] - equipment occupied."))
		return
	return ..()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/equip_info_lines()
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!occupant)
		return list()
	return list("Occupant: [occupant] (Health: [round(occupant.vitality()*100)]%)")

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/equip_controls()
	var/list/controls = list(list("key" = "view_stats", "label" = "View stats"))
	if(src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER))
		controls += list(list("key" = "eject", "label" = "Eject"))
	return controls

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/equip_press(mob/user, control, value)
	switch(control)
		if("view_stats")
			tgui_interact(user)
			return TRUE
		if("eject")
			go_out()
			return TRUE
	return FALSE

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/sleeper)
	interface("MechaSleeper", title = "Mounted Sleeper")
	without("ui_open")
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("inject", ui_act("inject", arg("reagent", schema_text(64))), then(PROC_REF(ui_act_inject)))
	every(1 SECOND, then(PROC_REF(sleeper_step)), when = nameof(sustaining))

/// /obj/item/mecha_parts/mecha_equipment/tool/sleeper's window data.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/ui_data(datum/act/eval/A)
	var/mob/living/carbon/human/occupant = slot_item_real(OCCUPANT_SLOT_MECHA_SLEEPER)
	var/list/data = list()
	data["has_occupant"] = occupant ? 1 : 0
	if(!occupant)
		data["occupant_name"] = ""
		data["status"] = ""
		data["health_percent"] = 0
		data["diagnosis"] = null
		data["body_temp_c"] = 0
		data["body_temp_f"] = 0
		data["reagents"] = list()
		data["injectables"] = list()
		return data
	data["occupant_name"] = occupant.name
	switch(occupant.stat)
		if(0)
			data["status"] = "Conscious"
		if(1)
			data["status"] = "Unconscious"
		if(2)
			data["status"] = "*dead*"
		else
			data["status"] = "Unknown"
	data["health_percent"] = round(occupant.vitality()*100)
	var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
	data["diagnosis"] = D?.report_data()
	spent(D)
	data["body_temp_c"] = round(occupant.body_temperature() - T0C, 0.1)
	data["body_temp_f"] = round(occupant.body_temperature() * 1.8 - 459.67, 0.1)
	var/list/rlist = list()
	if(occupant.reagents)
		for(var/datum/reagent/R in occupant.reagents.reagent_list)
			if(R.volume > 0)
				rlist += list(list("name" = "[R]", "volume" = round(R.volume, 0.01)))
	data["reagents"] = rlist
	var/list/inj = list()
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate_within(chassis, /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun)
	if(SG?.reagents && islist(SG.reagents.reagent_list))
		for(var/datum/reagent/R in SG.reagents.reagent_list)
			if(R.volume > 0)
				inj += list(list(
					"id" = R.id,
					"name" = R.name,
				))
	data["injectables"] = inj
	return data

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/ui_act_eject(datum/act/op/A)
	go_out()
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/ui_act_inject(datum/act/op/A, reagent)
	if(!istext(reagent))
		return FALSE
	// the window offers the reagents of the exosuit's syringe gun (the first one it carries)
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG = locate_within(chassis, /obj/item/mecha_parts/mecha_equipment/tool/syringe_gun)
	if(!SG?.reagents)
		return FALSE
	for(var/datum/reagent/R in SG.reagents.reagent_list)
		if(R.id == reagent && R.volume > 0)
			inject_reagent(R, SG)
			return TRUE
	return FALSE

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/inject_reagent(datum/reagent/R,obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/SG)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!R || !occupant || !SG || !(SG in chassis.equipment))
		return 0
	var/to_inject = min(R.volume, inject_amount)
	if(to_inject && occupant.reagents.get_reagent_amount(R.id) + to_inject > inject_amount*4)
		occupant_message(span_warning("Sleeper safeties prohibit you from injecting more than [inject_amount*4] units of [R.name]."))
	else
		occupant_message(span_notice("Injecting [occupant] with [to_inject] units of [R.name]."))
		src.mecha_log_message("Injecting [occupant] with [to_inject] units of [R.name].")
		SG.reagents.remove_reagent(R.id,to_inject)
		occupant.reagents.add_reagent(R.id,to_inject)
		update_equip_info()
	return

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/update_equip_info()
	SStgui.update_uis(src)
	return ..()

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/container_resist(mob/living)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(occupant == living)
		begin_release_sequence(living)

/// The slow release: whoever starts it (the occupant resisting, or the pilot through the exosuit's Sleeper Eject entry) frees the occupant a minute later.
/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/begin_release_sequence(mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!occupant || user.stat == DEAD)
		return
	to_chat(user, span_notice("Release sequence activated. This will take one minute."))
	after(src, 1 MINUTE, PROC_REF(release_sequence_done), with = list(occupant))

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/release_sequence_done(mob/living/carbon/human/occupant)
	if(occupant != src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)) //Check if someone's released/replaced/bombed him already
		return
	go_out()//and release him from the eternal prison.

/obj/item/mecha_parts/mecha_equipment/tool/sleeper/proc/sleeper_step(datum/act/timer/A)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER)
	if(!chassis)
		set_ready_state(TRUE)
		set_sustaining(FALSE) // the old step dropped out of the sweep here; the gate stays shut until an occupant is loaded again
		return
	if(!chassis.has_charge(energy_drain))
		set_ready_state(TRUE)
		src.mecha_log_message("Deactivated.")
		occupant_message(span_infoplain("[src] deactivated - no power."))
		set_sustaining(FALSE)
		return
	var/mob/living/carbon/M = occupant
	if(!M)
		return
	if(!M.is_critical())
		M.mend(TREAT_OXYGENATION, 1)
	M.status_adjust(STAT_STUNNED, -4)
	M.status_adjust(STAT_WEAKENED, -4)
	M.status_adjust(STAT_STUNNED, -4)
	M.status_at_least(STAT_PARALYZED, 2)
	M.status_at_least(STAT_WEAKENED, 2)
	M.status_at_least(STAT_STUNNED, 2)
	if(M.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) < 5)
		M.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 5)
	chassis.use_power(energy_drain)
	update_equip_info()
	return
