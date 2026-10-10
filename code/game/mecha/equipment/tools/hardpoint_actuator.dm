/*
 * A special device used to pick up and equip other exosuit components on the fly, without leaving an Exosuit. Costly.
 */

/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator
	name = "hardpoint actuator clamp"
	icon_state = "mecha_clamp"
	equip_cooldown = 10 SECONDS
	energy_drain = 600
	equip_type = EQUIP_HULL

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator)
	op("integrate", ai(), takes("equipment"), wait(3 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(integrate_done)))

/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator/proc/integrate_done(datum/act/op/A)
	var/obj/item/mecha_parts/mecha_equipment/ME = A.arg("equipment")
	if(QDELETED(ME))
		return OP_REFUSED
	if(ME.can_attach(chassis))
		ME.attach(chassis)
		occupant_message("[ME] successfully integrated.")
	return OP_OK

/obj/item/mecha_parts/mecha_equipment/hardpoint_actuator/action(atom/target)
	if(!action_checks(target))
		return

	if(istype(target,/obj/item/mecha_parts/mecha_equipment))
		var/obj/item/mecha_parts/mecha_equipment/ME = target
		if(ME.can_attach(chassis))
			occupant_message("[ME] can be integrated. Stand by.")
			perform_op(chassis?.slot_item(MECHA_SLOT_PILOT), src, "integrate", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("equipment" = ME))
		else
			occupant_message("[ME] cannot be integrated due to lack of free hardpoints.")

	else
		occupant_message("[target] is not compatible with any present hardpoints.")

	set_ready_state(FALSE)
	chassis.use_power(energy_drain)
	do_after_cooldown()
	return
