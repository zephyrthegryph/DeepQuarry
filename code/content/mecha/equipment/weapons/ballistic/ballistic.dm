/obj/item/mecha_parts/mecha_equipment/weapon/ballistic
	name = "general ballisic weapon"
	var/projectile_energy_cost

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/equip_info_lines()
	return list("Rounds: [src.projectiles]")

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/equip_controls()
	if(src.projectiles < initial(src.projectiles))
		return list(list("key" = "rearm", "label" = "Rearm"))
	return list()

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/equip_press(mob/user, control, value)
	if(control != "rearm")
		return FALSE
	rearm()
	return TRUE

/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/proc/rearm()
	if(projectiles < initial(projectiles))
		var/projectiles_to_add = initial(projectiles) - projectiles
		while(chassis.get_charge() >= projectile_energy_cost && projectiles_to_add)
			projectiles++
			projectiles_to_add--
			chassis.use_power(projectile_energy_cost)
	update_equip_info()
	src.mecha_log_message("Rearmed [src.name].")
	return

