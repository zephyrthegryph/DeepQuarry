/obj/item/mecha_parts/mecha_equipment/repair_droid
	name = "repair droid"
	desc = "Automated repair droid. Scans exosuit for damage and repairs it. Can fix almost any type of external or internal damage."
	icon_state = "repair_droid"
	equip_cooldown = 20
	energy_drain = 100
	range = 0
	var/health_boost = 2
	var/icon/droid_overlay
	var/static/list/repairable_damage = list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH)

	step_delay = 1

	equip_type = EQUIP_HULL

/obj/item/mecha_parts/mecha_equipment/repair_droid/var/repairing = FALSE
TRACKED(/obj/item/mecha_parts/mecha_equipment/repair_droid, repairing)

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/repair_droid)
	every(2 SECONDS, then(PROC_REF(repair_droid_step)), when = nameof(repairing))
	op("toggle_repairs", topic("toggle_repairs"), then(PROC_REF(topic_toggle_repairs)))

/obj/item/mecha_parts/mecha_equipment/repair_droid/add_equip_overlay(obj/mecha/M as obj)
	..()
	if(!droid_overlay)
		droid_overlay = new(src.icon, icon_state = "repair_droid")
	M.add_overlay(droid_overlay)
	return

/obj/item/mecha_parts/mecha_equipment/repair_droid/destroy()
	chassis.cut_overlay(droid_overlay)
	..()
	return

/obj/item/mecha_parts/mecha_equipment/repair_droid/detach()
	chassis.cut_overlay(droid_overlay)
	set_repairing(FALSE)
	..()
	return

/obj/item/mecha_parts/mecha_equipment/repair_droid/get_equip_info()
	if(!chassis) return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[src.name] - <a href='byond://?src=\ref[src];toggle_repairs=1'>[repairing?"Dea":"A"]ctivate</a>"



/obj/item/mecha_parts/mecha_equipment/repair_droid/proc/topic_toggle_repairs(datum/act/op/A)
	chassis.cut_overlay(droid_overlay)
	if(repairing)
		droid_overlay = new(src.icon, icon_state = "repair_droid")
		set_repairing(FALSE)
		src.mecha_log_message("Deactivated.")
		set_ready_state(TRUE)
	else
		droid_overlay = new(src.icon, icon_state = "repair_droid_a")
		src.mecha_log_message("Activated.")
		set_repairing(TRUE)
	chassis.add_overlay(droid_overlay)
	send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
	return

/obj/item/mecha_parts/mecha_equipment/repair_droid/proc/repair_droid_step(datum/act/timer/A)
	if(!chassis) // the droid only works mounted
		return
	var/repaired = 0
	var/effective_boost = health_boost
	if(mech_body_plan().has_affliction(chassis, MECHA_INT_SHORT_CIRCUIT))
		effective_boost *= -2
	else if(mech_body_plan().has_affliction(chassis) && prob(15))
		for(var/int_dam_flag in repairable_damage)
			if(mech_body_plan().has_affliction(chassis, int_dam_flag))
				mech_body_plan().cure(chassis, int_dam_flag)
				repaired = 1
				break

	var/obj/item/mecha_parts/component/AC = chassis.internal_components[MECH_ARMOR]
	var/obj/item/mecha_parts/component/HC = chassis.internal_components[MECH_HULL]

	var/damaged_armor = AC && AC.get_integrity() < AC.max_integrity

	var/damaged_hull = HC && HC.get_integrity() < HC.max_integrity

	if(effective_boost<0 || chassis.get_integrity() < chassis.max_integrity || damaged_armor || damaged_hull)
		// A short circuit flips effective_boost negative — that must DAMAGE the chassis.
		// repair_damage() early-returns on a non-positive amount, so branch on the sign.
		if(effective_boost < 0)
			chassis.take_damage(-effective_boost, BURN)
		else
			chassis.repair_damage(min(effective_boost, chassis.max_integrity - chassis.get_integrity()))

		if(AC)
			AC.adjust_integrity(round(effective_boost * 0.5, 0.5))

		if(HC)
			HC.adjust_integrity(round(effective_boost * 0.5, 0.5))

		repaired = 1
	if(repaired)
		if(chassis.use_power(energy_drain))
			set_ready_state(FALSE)
		else
			set_ready_state(TRUE)
			set_repairing(FALSE)
			return
	else
		set_ready_state(TRUE)
	return

