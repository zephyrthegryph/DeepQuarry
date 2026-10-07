/obj/item/mecha_parts/mecha_equipment/weapon/ballistic
	name = "general ballisic weapon"
	var/projectile_energy_cost

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/get_equip_info()
	return "[..()]\[[src.projectiles]\][(src.projectiles < initial(src.projectiles))?" - <a href='byond://?src=\ref[src];rearm=1'>Rearm</a>":null]"

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/proc/rearm()
	if(projectiles < initial(projectiles))
		var/projectiles_to_add = initial(projectiles) - projectiles
		while(chassis.get_charge() >= projectile_energy_cost && projectiles_to_add)
			projectiles++
			projectiles_to_add--
			chassis.use_power(projectile_energy_cost)
	send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
	src.mecha_log_message("Rearmed [src.name].")
	return

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/weapon/ballistic)
	op("rearm", topic("rearm"), then(PROC_REF(topic_rearm)))

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/proc/topic_rearm(datum/act/op/A)
	src.rearm()
	return
