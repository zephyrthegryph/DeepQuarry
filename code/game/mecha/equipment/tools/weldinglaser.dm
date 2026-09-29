/obj/item/mecha_parts/mecha_equipment/tool/powertool/welding
	name = "welding laser"
	desc = "An exosuit-mounted welding laser."
	icon_state = "mecha_laser-rig"
	equip_cooldown = 3
	energy_drain = 15
	range = MECH_MELEE
	equip_type = EQUIP_UTILITY
	ready_sound = SFX_ITEMS_RATCHET
	required_type = list(/obj/mecha/working/ripley)

	tooltype = /obj/item/weldingtool/electric/mounted/exosuit

/obj/item/mecha_parts/mecha_equipment/tool/powertool/welding/action(atom/target)
	..()

	if(is_ranged())
		var/atom/movable/beam_origin = chassis
		beam_origin.Beam(target, icon_state = "solar_beam", time = 0.3 SECONDS)

	// The beam ends itself after 0.3 seconds.

/obj/item/mecha_parts/mecha_equipment/tool/powertool/welding/attach(obj/mecha/M as obj)
	..()

	if(enable_special)
		range = MECH_MELEE|RANGED
		my_tool.reach = 7
	else
		range = MECH_MELEE
		my_tool.reach = 1
