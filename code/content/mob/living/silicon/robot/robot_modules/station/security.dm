/obj/item/robot_module/robot/security
	staffing_role = DEPARTMENT_SECURITY
	security_emotes = TRUE
	name = "security robot module"
	channels = list(CHANNEL_SECURITY = 1)
	networks = list(NETWORK_SECURITY)
	subsystems = list(/mob/living/silicon/proc/subsystem_crew_monitor)
	supported_upgrades = list(/obj/item/borg/upgrade/restricted/tasercooler, /obj/item/borg/upgrade/restricted/bellycapupgrade)
	pto_type = PTO_SECURITY

/obj/item/robot_module/robot/security/respawn_consumable(mob/living/silicon/robot/R, amount)
	..()
	var/obj/item/flash/F = locate_in_list(src.modules, /obj/item/flash)
	if(F && F.broken)
		F.set_broken(0)
		F.times_used = 0
	else if(F.times_used)
		F.times_used--
	var/obj/item/gun/energy/robotic/taser/T = locate_in_list(src.modules, /obj/item/gun/energy/robotic/taser)
	if(!T)
		return
	if(T.power_supply.charge < T.power_supply.maxcharge)
		T.power_supply.give(T.charge_cost * amount)
	else
		T.charge_tick = 0
