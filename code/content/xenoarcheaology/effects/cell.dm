/// Verified to work with the Artifact Harvester
#define CELL_DRAIN 1
#define CELL_CHARGE 2

/datum/artifact_effect/cell
	name = "Cell Power Effect"
	effect_type = EFFECT_CELL
	effect_color = "#ffee06"
	COOLDOWN_DECLARE(message_cooldown)
	var/charge_type = CELL_CHARGE

/datum/artifact_effect/cell/New()
	..()
	charge_type = pick(CELL_DRAIN, CELL_CHARGE)


/datum/artifact_effect/cell/proc/effect_cells(amount = 25, effect)
	var/atom/holder = get_master_holder()
	if(!holder)
		return
	var/turf/turf = get_turf(holder)
	if(!turf)
		return

	var/messaged_robots
	for(var/atom/movable/AM in range(effectrange, turf))
		if(isliving(AM))
			var/mob/living/L = AM
			var/obj/item/cell/C = L.get_cell()

			if(C)
				if(issilicon(L) && (COOLDOWN_FINISHED(src, message_cooldown)))
					messaged_robots = TRUE
					switch(effect)
						if(CELL_CHARGE)
							to_chat(L, span_notice("SYSTEM ALERT: Energy boost detected!"))
							C.set_charge(min(C.maxcharge, C.charge + amount))
						else
							to_chat(L, span_warning("SYSTEM ALERT: Energy drain detected!"))
							C.set_charge(max(0, min(C.maxcharge, C.charge - amount)))
			continue

		var/obj/item/cell/C = AM.get_cell()
		if(C)
			if(effect == CELL_CHARGE)
				C.set_charge(min(C.maxcharge, C.charge + amount))
			else
				C.set_charge(max(0, C.charge - amount))

	if(messaged_robots)
		COOLDOWN_START(src, message_cooldown, (1 MINUTE))

/datum/artifact_effect/cell/DoEffectTouch(mob/living/user)
	if(!user)
		return
	if(charge_type == CELL_DRAIN)
		effect_cells(100, CELL_DRAIN)
	else
		effect_cells(100, CELL_CHARGE)
/datum/artifact_effect/cell/DoEffectAura()
	if(charge_type == CELL_DRAIN)
		effect_cells(25, CELL_DRAIN)
	else
		effect_cells(25, CELL_CHARGE)

/datum/artifact_effect/cell/DoEffectPulse()
	if(charge_type == CELL_DRAIN)
		effect_cells(50, CELL_DRAIN)
	else
		effect_cells(50, CELL_CHARGE)
#undef CELL_DRAIN
#undef CELL_CHARGE
