/obj/effect/anomaly/flux
	name = "flux wave anomaly"
	icon_state = "flux"
	density = TRUE
	anomaly_core = /obj/item/assembly/signaler/anomaly/flux
	var/canshock = FALSE
	var/shockdamage = 20
	var/emp_zap = FLUX_EMP

/obj/effect/anomaly/flux/Initialize(mapload, new_lifespan, drops_core, emp_zap = FLUX_EMP)
	. = ..()
	src.emp_zap = emp_zap
	apply_wibbly_filters(src)

/obj/effect/anomaly/flux/anomalyEffect()
	..()
	canshock = TRUE
	for(var/mob/living/M in range(0, src))
		mobShock(M)

/obj/effect/anomaly/flux/Crossed(atom/movable/AM, oldloc)
	. = ..()
	on_entered(loc, AM)

/// Something entered our turf (was a connect_loc COMSIG_ATOM_ENTERED listener; now Crossed()).
/obj/effect/anomaly/flux/proc/on_entered(datum/source, atom/movable/AM)
	mobShock(AM)

/obj/effect/anomaly/flux/Bump(atom/A)
	mobShock(A)

/obj/effect/anomaly/flux/Bumped(atom/movable/AM)
	mobShock(AM)

EXTEND_INTERACTIONS(/obj/effect/anomaly/flux, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_flux_shock)), \
	INTERACT_ITEM(null, PROC_REF(interaction_flux_shock)), \
)

/// Old attack_hand and attackby: touching the flux anomaly, bare or with an item, shocks you; the touch carries on.
/obj/effect/anomaly/flux/proc/interaction_flux_shock(mob/user, obj/item/held, datum/interaction/interaction)
	mobShock(user)
	return FALSE

/obj/effect/anomaly/flux/proc/mobShock(mob/living/M)
	if(canshock && istype(M) && !M.is_incorporeal())
		canshock = FALSE
		M.electrocute_act(shockdamage, name)

/obj/effect/anomaly/flux/detonate()
	switch(emp_zap)
		if(FLUX_EMP)
			empulse(src, 4, 16)
			explosion(src, heavy_impact_range = 1, light_impact_range = 4, flash_range = 6)
		if(FLUX_LIGHT_EMP)
			empulse(src, 4, 6)
			explosion(src, light_impact_range = 3, flash_range = 6)
		if(FLUX_NO_EMP)
			new /obj/effect/effect/sparks(loc)

/obj/effect/anomaly/flux/minor
	anomaly_core = null

/obj/effect/anomaly/flux/minor/Initialize(mapload, new_lifespan, emp_zap = FLUX_NO_EMP)
	return ..()

/obj/effect/anomaly/flux/anomalyPulse()
	if(!..())
		return
	switch(stats.severity)
		if(0 to 15)
			var/datum/effect/effect/system/spark_spread/sparks = new /datum/effect/effect/system/spark_spread
			sparks.set_up(3, 1, src)
			sparks.start()
		if(16 to 33)
			tesla_zap(src, 2, 1000, FALSE, FALSE, current_jumps = 1) //Can't chain jumps.
		if(34 to 65)
			tesla_zap(src, 3, 1000, FALSE, FALSE, current_jumps = 1)
			om_after(src, 3 SECONDS, GLOBAL_PROC_REF(tesla_zap), src, 3, 1500, FALSE, FALSE)
		else
			tesla_zap(src, 4, 1000, FALSE, TRUE, current_jumps = 1)
			om_after(src, 3 SECONDS, PROC_REF(highSevPulse))

/obj/effect/anomaly/flux/proc/highSevPulse(power, explosive, current_jumps)
	tesla_zap(src, 4, 1250, FALSE, FALSE, current_jumps = 1)
	om_after(src, 3 SECONDS, GLOBAL_PROC_REF(tesla_zap), src, 4, 1500, FALSE, FALSE)
