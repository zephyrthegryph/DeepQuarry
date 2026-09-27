/atom/movable/proc/can_be_injected_by(atom/injector)
	if(!Adjacent(get_turf(injector)))
		return FALSE
	if(!reagents)
		return FALSE
	if(!reagents.get_free_space())
		return FALSE
	return TRUE

// Helper for anything checking if it can inject a container like a syringe.
/atom/movable/proc/is_injectable_container()
	return is_open_container() || \
		istype(src, /obj/item/reagent_containers/food) || \
		istype(src, /obj/item/slime_extract) || \
		istype(src, /obj/item/clothing/mask/smokable/cigarette) || \
		istype(src, /obj/item/storage/fancy/cigarettes) || \
		istype(src, /obj/item/clothing/mask/chewable)

/obj/can_be_injected_by(atom/injector)
	if(!..())
		return FALSE
	// Then check if this is a type of container that can be injected
	return is_injectable_container()

/mob/living/can_be_injected_by(atom/injector)
	return ..() && (can_inject(null, 0, BP_TORSO) || can_inject(null, 0, BP_GROIN))


/// Water's latent heat, the one rule for water and water-based foam: hot air
/// on `T` above the boiling point gives up to `volume` x WATER_LATENT_HEAT to
/// boiling the liquid off (abstracted as steam). Returns TRUE if it was hot.
/proc/reagent_boil_off(turf/T, volume)
	var/datum/gas_mixture/environment = T.return_air()
	if(!environment || environment.return_temperature() <= WATER_BOILING_POINT)
		return FALSE
	var/removed_heat = between(0, volume * WATER_LATENT_HEAT, -environment.get_thermal_energy_change(WATER_BOILING_POINT))
	environment.add_thermal_energy(-removed_heat)
	return TRUE

/// Liquid on a burning tile knocks the fire back: the tile's gas loses at least
/// half its temperature (2000 K at most) and the hotspot goes out.
/proc/reagent_quench_hotspot(turf/T)
	var/obj/effect/hotspot/hotspot = locate() in T
	if(!hotspot || isspace(T))
		return
	var/datum/gas_mixture/lowertemp = T.remove_air(xgm_total_moles(T.return_air()))
	var/lowertemp_temperature = lowertemp.return_temperature()
	lowertemp.set_temperature(max(min(lowertemp_temperature - 2000, lowertemp_temperature / 2), 0))
	lowertemp.react()
	T.assume_air(lowertemp)
	qdel(hotspot)
