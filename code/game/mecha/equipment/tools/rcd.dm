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

DECLARE_DEFAULT_CHILD(/obj/item/mecha_parts/mecha_equipment/tool/rcd, "my_rcd", /obj/item/rcd/electric/mounted/mecha)

DECLARE_REF(/obj/item/mecha_parts/mecha_equipment/tool/rcd, "my_rcd", OWNED, null)

/obj/item/mecha_parts/mecha_equipment/tool/rcd/action(atom/target)
	if(!action_checks(target) || get_dist(chassis, target) > 3)
		return FALSE

	my_rcd.use_rcd(target, chassis?.slot_item(MECHA_SLOT_PILOT))

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/tool/rcd, "mode", PROC_REF(topic_mode), TOPIC_NUM("mode"))

/obj/item/mecha_parts/mecha_equipment/tool/rcd/proc/topic_mode(mob/user, list/args)
	if(isnum(args["mode"]))
		my_rcd.mode_index = args["mode"]
		occupant_message("RCD reconfigured to '[LAZYACCESS(my_rcd.modes, my_rcd.mode_index)]'.")
/*
/obj/item/mecha_parts/mecha_equipment/tool/rcd/get_equip_info()
	return "[..()] \[<a href='byond://?src=\ref[src];mode=0'>D</a>|<a href='byond://?src=\ref[src];mode=1'>C</a>|<a href='byond://?src=\ref[src];mode=2'>A</a>\]"
*/
/obj/item/mecha_parts/mecha_equipment/tool/rcd/get_equip_info()
	var/list/content = list(..()) // This is all for one line, in the interest of string tree conservation.
	var/i = 1
	content += "<br>"
	for(var/mode in my_rcd.modes)
		content += "     <a href='byond://?src=\ref[src];mode=[i]'>[mode]</a>"
		if(i < length(my_rcd.modes))
			content += "<br>"
		i++

	return content.Join()
