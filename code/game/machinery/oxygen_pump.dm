/obj/machinery/oxygen_pump
	name = "emergency oxygen pump"
	icon = 'icons/obj/walllocker.dmi'
	desc = "A wall mounted oxygen pump with a retractable mask that you can pull over your face in case of emergencies."
	icon_state = "oxygen_tank"

	anchored = TRUE

	var/obj/item/tank/tank
	var/obj/item/clothing/mask/breath/contained

	var/spawn_type = /obj/item/tank/emergency/oxygen/engi
	var/mask_type = /obj/item/clothing/mask/breath/emergency
	var/icon_state_open = "oxygen_tank_open"
	var/icon_state_closed = "oxygen_tank"

	power_channel = ENVIRON
	idle_power_usage = 10
	active_power_usage = 120 // No idea what the realistic amount would be.

CAPABILITIES(/obj/machinery/oxygen_pump)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(breather), wakes_on = list(nameof(breather)))
	owns_one(nameof(tank), /obj/item/tank, starts = nameof(spawn_type))
	owns_one(nameof(contained), starts = nameof(mask_type))
	interface("Tank")
	op("pressure", ui_act("pressure", arg("pressure")), then(PROC_REF(ui_act_pressure)))
	op("oxygen_pump_hand", hand(), ungated(), needs(req(PROC_REF(can_use_pump), because = MSG(oxygen_pump/no_tank))), then(PROC_REF(oxygen_pump_interaction_hand)))
	op("oxygen_pump_item", item(/obj/item), then(PROC_REF(oxygen_pump_interaction_item)))
	op("oxygen_pump_settings", menu(), label("Show Tank Settings"), then(PROC_REF(oxygen_pump_settings)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))

/// Who wears the mask (a relation view), or null.
OM_FIELD_VIEW(/obj/machinery/oxygen_pump, mob/living/carbon, breather, CHANGE_MACHINE_OCCUPANT)
/// Keeps the mask and internals right while a mask is on someone.
// the mask retracts from its breather.
/obj/machinery/oxygen_pump/lifecycle_prerelease()
	..()
	if(breather())
		breather().internal = null
		if(breather().internals)
			breather().internals.icon_state = "internal0"
		breather().remove_from_mob(contained)
		breather().cozyloop.stop()
		visible_message(span_notice("\The [contained] rapidly retracts just before /the [src] is destroyed!"))

/obj/machinery/oxygen_pump/MouseDrop(mob/living/carbon/human/target, src_location, over_location)
	var/mob/living/user = usr
	if(!istype(user) || !istype(target) || user.is_incorporeal())
		return ..()

	if(CanMouseDrop(target, user))
		if(!can_apply_to_target(target, user)) // There is no point in attempting to apply a mask if it's impossible.
			return
		act_message(user, target, others = "%U% begins placing \the [contained] onto %T%.")
		om_task_timed(user, 2.5 SECONDS, target = target, receiver = src, on_done = PROC_REF(place_mask_done), done_args = list(user, target))

/obj/machinery/oxygen_pump/proc/place_mask_done(mob/living/user, mob/living/carbon/human/target)
	if(!can_apply_to_target(target, user))
		return
	// place mask and add fingerprints
	act_message(user, target, others = "%U% has placed \the [contained] on %T%'s mouth.")
	attach_mask(target)
	src.add_fingerprint(user)

MSG_DEF_SELF(oxygen_pump/no_tank, "There is no tank in it.")

/// Requirement: the mask needs a tank behind it (removing the tank in maintenance is always fine).
/obj/machinery/oxygen_pump/proc/can_use_pump(datum/act/op/A)
	return A.actor.is_incorporeal() || has_stat(MAINT) || tank

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/oxygen_pump/proc/oxygen_pump_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.is_incorporeal())
		return TRUE
	if((has_stat(MAINT)) && tank)
		act_message(user, src, MSG_SELF(span_notice("You remove \the [tank] from %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " removes \the [tank] from %T%.")))
		user.put_in_hands(tank)
		src.add_fingerprint(user)
		tank.add_fingerprint(user)
		rel_take(src, nameof(tank))
		return TRUE
	if(!tank)
		return TRUE
	if(breather())
		if(tank)
			tank.forceMove(src)
		breather().remove_from_mob(contained)
		contained.forceMove(src)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " makes \the [contained] rapidly retract back into %T%!"))
		breather().cozyloop.stop() // Cozy Music
		if(breather().internals)
			breather().internals.icon_state = "internal0"
		rel_clear(src, nameof(breather))
		set_use_power(USE_POWER_IDLE)
	return TRUE

/obj/machinery/oxygen_pump
	silicon_use = SILICON_USE_UI

/obj/machinery/oxygen_pump/proc/attach_mask(mob/living/carbon/C)
	if(C && istype(C))
		contained.forceMove(get_turf(C))
		C.equip_to_slot(contained, SLOT_ID_MASK)
		if(tank)
			tank.forceMove(C)
		rel_set(src, nameof(breather), C)
		after(src, 0.1 SECONDS, PROC_REF(attach_mask_finish))

/obj/machinery/oxygen_pump/proc/attach_mask_finish()
	if(!breather().internal && tank)
		breather().internal = tank
		if(breather().internals)
			breather().internals.icon_state = "internal1"
	set_use_power(USE_POWER_ACTIVE)

/obj/machinery/oxygen_pump/proc/can_apply_to_target(mob/living/carbon/human/target, mob/user as mob)
	if(!user)
		user = target
	// Check target validity
	if(!target.organs_by_name[BP_HEAD])
		to_chat(user, span_warning("\The [target] doesn't have a head."))
		return
	if(!target.check_has_mouth())
		to_chat(user, span_warning("\The [target] doesn't have a mouth."))
		return
	if(target.get_equipped_item(SLOT_ID_MASK) && target != breather())
		to_chat(user, span_warning("\The [target] is already wearing a mask."))
		return
	if(target.get_equipped_item(SLOT_ID_HEAD) && (target.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE))
		to_chat(user, span_warning("Remove their [target.get_equipped_item(SLOT_ID_HEAD)] first."))
		return
	if(!tank)
		to_chat(user, span_warning("There is no tank in \the [src]."))
		return
	if(has_stat(MAINT))
		to_chat(user, span_warning("Please close the maintenance hatch first."))
		return
	if(!Adjacent(target))
		to_chat(user, span_warning("Please stay close to \the [src]."))
		return
	//when there is a breather:
	if(breather() && target != breather())
		to_chat(user, span_warning("\The [src] is already in use."))
		return
	//Checking if breather is still valid
	if(target == breather() && target.get_equipped_item(SLOT_ID_MASK) != contained)
		to_chat(user, span_warning("\The [target] is not using the supplied [contained]."))
		return
	return 1

/// Old attackby. It never called ..(), so every item stops here.
/obj/machinery/oxygen_pump/proc/oxygen_pump_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(user.is_incorporeal())
		return TRUE
	if(istype(W, /obj/item/tank) && (has_stat(MAINT)))
		if(tank)
			to_chat(user, span_warning("\The [src] already has a tank installed!"))
		else
			if(!move_into(src, nameof(src.tank), W, user))
				return TRUE
			act_message(user, src, MSG_SELF(span_notice("You install %I% into %T%.")), \
				MSG_OTHERS(span_infoplain(span_bold("%U%") + " installs %I% into %T%.")), \
				item = tank)
			src.add_fingerprint(user)
	if(istype(W, /obj/item/tank) && !has_stat(MACHINE_STAT_ANY))
		to_chat(user, span_warning("Please open the maintenance hatch first."))
	return TRUE

/obj/machinery/oxygen_pump/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	if(user.is_incorporeal())
		return OP_OK
	if(!stat_remove(MAINT))
		stat_add(MAINT)
	act_message(user, src, MSG_SELF(span_notice("You [has_stat(MAINT) ? "open" : "close"] %T%.")), \
		MSG_OTHERS(span_notice("%U% [has_stat(MAINT) ? "opens" : "closes"] %T%.")))
	icon_state = (has_stat(MAINT)) ? icon_state_open : icon_state_closed
	return OP_OK

/obj/machinery/oxygen_pump/examine(mob/user)
	. = ..()
	if(tank)
		. += "The meter shows [round(tank.air_contents.return_pressure())] kPa."
	else
		. += span_warning("It is missing a tank!")

/// Runs while a mask is on someone (the declaration above).
/obj/machinery/oxygen_pump/proc/work_step(datum/act/timer/A)
	if(!breather()) // the breather was deleted
		return
	if(breather())
		if(!can_apply_to_target(breather()))
			if(tank)
				tank.forceMove(src)
			breather().remove_from_mob(contained)
			contained.forceMove(src)
			breather().cozyloop.stop() // Cozy Music
			src.visible_message(span_notice("\The [contained] rapidly retracts back into \the [src]!"))
			rel_clear(src, nameof(breather))
			set_use_power(USE_POWER_IDLE)
		else if(!breather().internal && tank)
			breather().internal = tank
			if(breather().internals)
				breather().internals.icon_state = "internal0"

//Create rightclick to view tank settings
/obj/machinery/oxygen_pump/proc/oxygen_pump_settings(datum/act/op/A)
	tgui_interact(A.actor)

/obj/machinery/oxygen_pump/ui_prepare(mob/user, datum/tgui/ui)
	if(!tank)
		to_chat(user, span_warning("[src] is missing a tank."))
		return FALSE

	return TRUE

/obj/machinery/oxygen_pump/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["showToggle"] = FALSE
	data["maskConnected"] = !!breather()

	data["tankPressure"] = 0
	data["releasePressure"] = 0
	data["defaultReleasePressure"] = 0
	data["minReleasePressure"] = 0
	data["releasePressure"] = round(tank.distribute_pressure ? tank.distribute_pressure : 0)
	data["maxReleasePressure"] = round(TANK_MAX_RELEASE_PRESSURE)

	if(tank)
		data["tankPressure"] = round(tank.air_contents.return_pressure() ? tank.air_contents.return_pressure() : 0)
		data["defaultReleasePressure"] = round(TANK_DEFAULT_RELEASE_PRESSURE)

	return data

/obj/machinery/oxygen_pump/proc/ui_act_pressure(datum/act/op/A, raw_pressure)
	var/pressure = raw_pressure
	if(pressure == "reset")
		pressure = TANK_DEFAULT_RELEASE_PRESSURE
		. = TRUE
	else if(pressure == "min")
		pressure = 0
		. = TRUE
	else if(pressure == "max")
		pressure = TANK_MAX_RELEASE_PRESSURE
		. = TRUE
	else if(isnum(pressure))
		. = TRUE
	if(.)
		tank.distribute_pressure = clamp(round(pressure), 0, TANK_MAX_RELEASE_PRESSURE)

/obj/machinery/oxygen_pump/anesthetic
	name = "anesthetic pump"
	desc = "A wall mounted anesthetic pump with a retractable mask that someone can pull over your face to knock you out."
	spawn_type = /obj/item/tank/anesthetic
	icon_state = "anesthetic_tank"
	icon_state_closed = "anesthetic_tank"
	icon_state_open = "anesthetic_tank_open"
	mask_type = /obj/item/clothing/mask/breath/anesthetic

// Cozy Music
/obj/machinery/oxygen_pump/anesthetic/attach_mask(mob/living/carbon/C)
	if(C && istype(C))
		contained.forceMove(get_turf(C))
		C.equip_to_slot(contained, SLOT_ID_MASK)
		if(tank)
			tank.forceMove(C)
		rel_set(src, nameof(breather), C)
		after(src, 0.1 SECONDS, PROC_REF(attach_mask_finish))

/obj/machinery/oxygen_pump/anesthetic/attach_mask_finish()
	if(!breather().internal && tank)
		breather().internal = tank
		if(breather().internals)
			breather().internals.icon_state = "internal1"
	set_use_power(USE_POWER_ACTIVE)
	breather().cozyloop.start()

/obj/machinery/oxygen_pump/mobile
	name = "portable oxygen pump"
	icon = 'icons/obj/atmos.dmi'
	desc = "A portable oxygen pump with a retractable mask that you can pull over your face in case of emergencies."
	icon_state = "medpump"
	icon_state_open = "medpump_open"
	icon_state_closed = "medpump"

	anchored = FALSE
	density = TRUE

	mask_type = /obj/item/clothing/mask/gas/clear

	var/last_area = null

/// A mobile pump re-reads its area's power when it is wheeled into another area.
/obj/machinery/oxygen_pump/mobile/Moved(atom/old_loc)
	. = ..()
	var/area/A = get_area(src)
	if(A && last_area != A)
		last_area = A
		power_change()

/obj/machinery/oxygen_pump/mobile/anesthetic
	name = "portable anesthetic pump"
	desc = "A portable anesthetic pump with a retractable mask that someone can pull over your face to knock you out."
	spawn_type = /obj/item/tank/anesthetic
	icon_state = "medpump_n2o"
	icon_state_closed = "medpump_n2o"
	icon_state_open = "medpump_n2o_open"
	mask_type = /obj/item/clothing/mask/breath/anesthetic

// Cozy Music
/obj/machinery/oxygen_pump/mobile/anesthetic/attach_mask(mob/living/carbon/C)
	if(C && istype(C))
		contained.forceMove(get_turf(C))
		C.equip_to_slot(contained, SLOT_ID_MASK)
		if(tank)
			tank.forceMove(C)
		rel_set(src, nameof(breather), C)
		after(src, 0.1 SECONDS, PROC_REF(attach_mask_finish))

/obj/machinery/oxygen_pump/mobile/anesthetic/attach_mask_finish()
	if(!breather().internal && tank)
		breather().internal = tank
		if(breather().internals)
			breather().internals.icon_state = "internal1"
	set_use_power(USE_POWER_ACTIVE)
	breather().cozyloop.start()

/obj/machinery/oxygen_pump/mobile/stabilizer
	name = "portable patient stabilizer"
	desc = "A portable oxygen pump with a retractable mask used for stabilizing patients in the field."

/obj/machinery/oxygen_pump/mobile/stabilizer/work_step(datum/act/timer/A)
	if(!breather())
		return PROCESS_KILL
	if(breather())
		if(!can_apply_to_target(breather()))
			if(tank)
				tank.forceMove(src)
			breather().remove_from_mob(contained)
			contained.forceMove(src)
			src.visible_message(span_notice("\The [contained] rapidly retracts back into \the [src]!"))
			rel_clear(src, nameof(breather))
			set_use_power(USE_POWER_IDLE)
		else if(!breather().internal && tank)
			breather().internal = tank
			if(breather().internals)
				breather().internals.icon_state = "internal0"

		if(breather())	// Safety.
			if(ishuman(breather()) && !(HAS_SYNTHETIC_BIOLOGY(breather())))
				var/mob/living/carbon/human/H = breather()

				if(H.organ_in(O_LUNGS))
					var/obj/item/organ/internal/L = H.organ_in(O_LUNGS)
					if(L)
						if(!(L.status & ORGAN_DEAD))
							H.mend(TREAT_OXYGENATION, rand(10,15))

							if(L.is_bruised() && prob(30))
								H.mend(TREAT_RESPIRATORY, 1, L)
							else
								H.AdjustLosebreath(-(rand(1, 5)))
						else
							H.mend(TREAT_OXYGENATION, rand(1,8))

				if(H.stat == DEAD)
					H.apply_body_effect(/datum/body_effect/bloodpump_corpse, 6 SECONDS)

				else
					H.apply_body_effect(/datum/body_effect/bloodpump, 6 SECONDS)
					// A ventilator and circulatory pump: floors under the
					// breathing drive and cardiac output while attached.
					H.body?.add_support(src, BF_RESP_DRIVE, 1, 6 SECONDS)
					H.body?.add_support(src, BF_PUMP, 1, 6 SECONDS)

/// breather (a relation view: it reads null once the target is deleted).
/obj/machinery/oxygen_pump/proc/breather() as /mob/living/carbon
	return breather
