/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables
	name = "inflatable deployment mechanism"
	desc = "An exosuit-mounted inflatable barrier deployer. Useful!"
	icon_state = "mecha_inflatables"
	equip_cooldown = 3
	energy_drain = 30
	range = MECH_MELEE
	equip_type = EQUIP_UTILITY
	ready_sound = SFX_EFFECTS_SPRAY
	required_type = list(/obj/mecha/working/ripley)

	tooltype = /obj/item/inflatable_dispenser/robot
	var/obj/item/inflatable_dispenser/my_deployer

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/proc/link_deployer()
	rel_set(src, nameof(my_deployer), my_tool)

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables)
	setup(PROC_REF(link_deployer))
	ref_one(nameof(my_deployer))

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/equip_info_lines()
	return list("Doors left: [my_deployer().stored_doors]/[my_deployer().max_doors]", "Walls left: [my_deployer().stored_walls]/[my_deployer().max_walls]")

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/equip_controls()
	return list(list("key" = "toggle_deployable_mode", "label" = "Deploy [my_deployer().mode ? "Door" : "Wall"]"))

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/equip_press(mob/user, control, value)
	if(control != "toggle_deployable_mode")
		return FALSE
	my_deployer().attack_self()
	update_chassis_page()
	return TRUE

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/action(atom/target, params)
	if(!action_checks(target))
		return

	if(istype(target, /turf))
		my_deployer().try_deploy_inflatable(target, chassis?.slot_item(MECHA_SLOT_PILOT))
	if(istype(target, /obj/item/inflatable) || istype(target, /obj/structure/inflatable))
		my_deployer().pick_up(target, chassis?.slot_item(MECHA_SLOT_PILOT))

	set_ready_state(FALSE)
	chassis.use_power(energy_drain)
	do_after_cooldown()
	return

/// my deployer
/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/proc/my_deployer() as /obj/item/inflatable_dispenser
	return my_deployer
