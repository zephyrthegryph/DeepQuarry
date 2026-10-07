/obj/item/mecha_parts/mecha_equipment/cloak
	name = "cloaking device"
	desc = "Integrated cloaking system. High power usage, but does render you invisible to the naked eye. Doesn't prevent noise, however."
	icon_state = "tesla"
	energy_drain = 300
	range = 0
	equip_type = EQUIP_SPECIAL

/obj/item/mecha_parts/mecha_equipment/cloak/var/cloaking = FALSE
TRACKED(/obj/item/mecha_parts/mecha_equipment/cloak, cloaking)

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/cloak)
	every(2 SECONDS, then(PROC_REF(cloak_step)), when = nameof(cloaking))

/obj/item/mecha_parts/mecha_equipment/cloak/proc/cloak_step(datum/act/timer/A)
	//Removed from chassis or ran out of power
	if(!chassis || !chassis.use_power(energy_drain))
		stop_cloak()
		return

/obj/item/mecha_parts/mecha_equipment/cloak/detach()
	if(!equip_ready) //We were running
		stop_cloak()
	return ..()

/obj/item/mecha_parts/mecha_equipment/cloak/get_equip_info()
	if(!chassis)
		return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[src.name] - <a href='byond://?src=\ref[src];toggle_cloak=1'>[equip_ready ? "A" : "Dea"]ctivate</a>"

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/cloak, "toggle_cloak", PROC_REF(topic_toggle_cloak))

/obj/item/mecha_parts/mecha_equipment/cloak/proc/topic_toggle_cloak(mob/user, list/args)
	if(equip_ready)
		start_cloak()
	else
		stop_cloak()
	return

/obj/item/mecha_parts/mecha_equipment/cloak/proc/start_cloak()
	if(chassis)
		chassis.cloak()
	src.mecha_log_message("Activated.")
	set_cloaking(TRUE)
	set_ready_state(FALSE)
	play_sfx(src, SFX_EFFECTS_EMPULSE)

/obj/item/mecha_parts/mecha_equipment/cloak/proc/stop_cloak()
	if(chassis)
		chassis.uncloak()
	src.mecha_log_message("Deactivated.")
	set_cloaking(FALSE)
	set_ready_state(TRUE)
	play_sfx(src, SFX_EFFECTS_EMPULSE)
