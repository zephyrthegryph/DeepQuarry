/*
 * A special device used to pick up and equip other exosuit components on the fly, without leaving an Exosuit. Costly.
 */

/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator
	name = "hardpoint actuator clamp"
	icon_state = "mecha_clamp"
	equip_cooldown = 10 SECONDS
	energy_drain = 600
	equip_type = EQUIP_HULL

/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator/proc/integrate_done(obj/item/mecha_parts/mecha_equipment/ME)
	if(ME.can_attach(chassis))
		ME.attach(chassis)
		occupant_message("[ME] successfully integrated.")

/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator/action(atom/target)
	if(!action_checks(target))
		return

	if(istype(target,/obj/item/mecha_parts/mecha_equipment))
		var/obj/item/mecha_parts/mecha_equipment/ME = target
		if(ME.can_attach(chassis))
			occupant_message("[ME] can be integrated. Stand by.")
			task_timed(chassis?.slot_item(MECHA_SLOT_PILOT), 3 SECONDS, target, src, PROC_REF(integrate_done), list(ME), IGNORE_HELD_ITEM)
		else
			occupant_message("[ME] cannot be integrated due to lack of free hardpoints.")

	else
		occupant_message("[target] is not compatible with any present hardpoints.")

	set_ready_state(FALSE)
	chassis.use_power(energy_drain)
	do_after_cooldown()
	return
