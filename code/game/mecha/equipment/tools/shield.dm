/obj/item/mecha_parts/mecha_equipment/combat_shield
	name = "linear combat shield"
	desc = "A shield generator that forms a rectangular, unidirectionally projectile-blocking wall in front of the exosuit."
	icon_state = "shield"
	equip_cooldown = 5
	energy_drain = 20
	range = 0

	step_delay = 0.2

	var/obj/item/shield_projector/line/exosuit/my_shield = null
	var/my_shield_type = /obj/item/shield_projector/line/exosuit

	equip_type = EQUIP_HULL

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/combat_shield)
	owns_one(nameof(my_shield), /obj/item/shield_projector/line/exosuit, starts = nameof(my_shield_type), starts_args = NO_LOC)
	op("toggle_shield", topic("toggle_shield"), then(PROC_REF(topic_toggle_shield)))

/obj/item/mecha_parts/mecha_equipment/combat_shield/Initialize(mapload)
	. = ..()
	my_shield.shield_regen_delay = equip_cooldown
	rel_set(my_shield, nameof(my_shield.my_tool), src)

/obj/item/mecha_parts/mecha_equipment/combat_shield/critfail()
	..()
	my_shield.adjust_health(-200)
	return

// its shields drop.
/obj/item/mecha_parts/mecha_equipment/combat_shield/lifecycle_prerelease()
	..()
	my_shield?.destroy_shields()

/obj/item/mecha_parts/mecha_equipment/combat_shield/equip_look(datum/look/look)
	..()
	look.overlay("shield_droid", icon = icon)

/obj/item/mecha_parts/mecha_equipment/combat_shield/attach(obj/mecha/M as obj)
	..()
	if(chassis)
		my_shield.update_integrity(0)
		rel_set(my_shield, nameof(my_shield.my_mecha), chassis)
		my_shield.forceMove(chassis)
	return

/obj/item/mecha_parts/mecha_equipment/combat_shield/detach()
	..()
	my_shield.destroy_shields()
	rel_clear(my_shield, nameof(my_shield.my_mecha))
	my_shield.repair_damage(my_shield.max_integrity)
	my_shield.forceMove(src)
	return

/obj/item/mecha_parts/mecha_equipment/combat_shield/handle_movement_action()
	if(chassis)
		my_shield.update_shield_positions()
	return

/obj/item/mecha_parts/mecha_equipment/combat_shield/proc/toggle_shield()
	if(chassis)
		my_shield.attack_self(chassis?.slot_item(MECHA_SLOT_PILOT))
		if(my_shield.active)
			set_ready_state(FALSE)
			step_delay = 4
			src.mecha_log_message("Activated.")
		else
			set_ready_state(TRUE)
			step_delay = 1
			src.mecha_log_message("Deactivated.")


/obj/item/mecha_parts/mecha_equipment/combat_shield/proc/topic_toggle_shield(datum/act/op/A)
	toggle_shield()
	return

/obj/item/mecha_parts/mecha_equipment/combat_shield/get_equip_info()
	if(!chassis) return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[src.name] - <a href='byond://?src=\ref[src];toggle_shield=1'>[my_shield.active?"Dea":"A"]ctivate</a>"
