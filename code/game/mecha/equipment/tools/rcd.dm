/obj/item/mecha_parts/mecha_equipment/tool/rcd
	name = "mounted RCD"
	desc = "An exosuit-mounted Rapid Construction Device. (Can be attached to: Any exosuit)"
	mech_flags = EXOSUIT_MODULE_WORKING|EXOSUIT_MODULE_COMBAT|EXOSUIT_MODULE_MEDICAL
	icon_state = "mecha_rcd"
	equip_cooldown = 10
	energy_drain = 250
	range = MECH_MELEE|RANGED
	equip_type = EQUIP_SPECIAL
	var/obj/item/rcd/electric/mounted/mecha/my_rcd = null

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/rcd)
	owns_one(nameof(my_rcd), starts = /obj/item/rcd/electric/mounted/mecha)


/obj/item/mecha_parts/mecha_equipment/tool/rcd/action(atom/target)
	if(!action_checks(target) || get_dist(chassis, target) > 3)
		return FALSE

	my_rcd.use_rcd(target, chassis?.slot_item(MECHA_SLOT_PILOT))


/obj/item/mecha_parts/mecha_equipment/tool/rcd/proc/set_rcd_mode(new_mode)
	my_rcd.mode_index = new_mode
	occupant_message("RCD reconfigured to '[LAZYACCESS(TYPE_TABLE_GET(my_rcd, rcd_modes), my_rcd.mode_index)]'.")

/obj/item/mecha_parts/mecha_equipment/tool/rcd/equip_controls()
	var/list/controls = list()
	var/i = 1
	for(var/mode in TYPE_TABLE_GET(my_rcd, rcd_modes))
		controls += list(list("key" = "mode", "label" = "[mode]", "value" = i))
		i++
	return controls

/obj/item/mecha_parts/mecha_equipment/tool/rcd/equip_press(mob/user, control, value)
	if(control != "mode" || !isnum(value))
		return FALSE
	set_rcd_mode(value)
	return TRUE
