/obj/item/mecha_parts/mecha_equipment/tool/powertool
	name = "pneumatic wrench"
	desc = "An exosuit-mounted hydraulic wrench."
	icon_state = "mecha_wrench"
	equip_cooldown = 3
	energy_drain = 15
	range = MECH_MELEE
	equip_type = EQUIP_UTILITY
	ready_sound = SFX_ITEMS_RATCHET
	required_type = list(/obj/mecha/working/ripley)

	var/obj/item/my_tool = null
	var/tooltype = /obj/item/tool/wrench/power

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/powertool)
	owns_one(nameof(my_tool), /obj/item, starts = nameof(tooltype))

/obj/item/mecha_parts/mecha_equipment/tool/powertool/Initialize(mapload)
	. = ..()
	my_tool.name = name
	my_tool.set_anchored(TRUE)
	my_tool.canremove = FALSE


/obj/item/mecha_parts/mecha_equipment/tool/powertool/action(atom/target)
	if(!action_checks(target))
		return FALSE

	if(isliving(target))
		my_tool.attack(target, chassis?.slot_item(MECHA_SLOT_PILOT), BP_TORSO)

	target.attackby(my_tool,chassis?.slot_item(MECHA_SLOT_PILOT))

/obj/item/mecha_parts/mecha_equipment/tool/powertool/prybar
	name = "pneumatic prybar"
	desc = "An exosuit-mounted pneumatic prybar."
	icon_state = "mecha_crowbar"
	tooltype = /obj/item/tool/crowbar/power
	ready_sound = SFX_MECHA_GASDISCONNECTED

/obj/item/mecha_parts/mecha_equipment/tool/powertool/cutter
	name = "pneumatic cablecutter"
	desc = "An exosuit-mounted pneumatic cablecutter."
	icon_state = "mecha_cablecutter"
	tooltype = /obj/item/tool/wirecutters/power
	ready_sound = SFX_MECHA_GASDISCONNECTED

/obj/item/mecha_parts/mecha_equipment/tool/powertool/screwdriver
	name = "pneumatic screwdriver"
	desc = "An exosuit-mounted pneumatic screwdriver."
	icon_state = "mecha_screwdriver"
	tooltype = /obj/item/tool/screwdriver/power
	ready_sound = SFX_MECHA_GASDISCONNECTED
