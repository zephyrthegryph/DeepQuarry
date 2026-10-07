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

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(my_deployer), my_tool)

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables)
	op("toggle_deployable_mode", topic("toggle_deployable_mode"), then(PROC_REF(topic_toggle_deployable_mode)))

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/proc/topic_toggle_deployable_mode(datum/act/op/A)
	my_deployer().attack_self()
	update_chassis_page()
	return

/obj/item/mecha_parts/mecha_equipment/tool/powertool/inflatables/get_equip_info()
	if(!chassis) return
	var/data_return = (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[chassis.selected==src?"<b>":"<a href='byond://?src=\ref[chassis];select_equip=\ref[src]'>"][src.name][chassis.selected==src?"</b>":"</a>"] - <a href='byond://?src=\ref[src];toggle_deployable_mode=1'>Deploy [my_deployer().mode?"Door":"Wall"]</a><br>\
	&nbsp; - Doors left: " + span_yellow("[my_deployer().stored_doors]") + "/[my_deployer().max_doors]<br>\
	&nbsp; - Walls left: " + span_yellow("[my_deployer().stored_walls]") + "/[my_deployer().max_walls]"

	return data_return

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
