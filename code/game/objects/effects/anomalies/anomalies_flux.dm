/obj/effect/anomaly/flux
	name = "flux wave anomaly"
	icon_state = "flux"
	density = TRUE
	anomaly_core = /obj/item/assembly/signaler/anomaly/flux
	var/canshock = FALSE
	var/shockdamage = 20
	var/emp_zap = FLUX_EMP

// ALLOW(init/INSTANCE_STATE): a flux anomaly wobbles
/obj/effect/anomaly/flux/Initialize(mapload)
	. = ..()
	apply_wibbly_filters(src)

/obj/effect/anomaly/flux/anomalyEffect()
	..()
	canshock = TRUE
	for(var/mob/living/M in range(0, src))
		mobShock(M)

/obj/effect/anomaly/flux/Crossed(atom/movable/AM, oldloc)
	. = ..()
	on_entered(loc, AM)

/// Something entered our turf: Crossed().
/obj/effect/anomaly/flux/proc/on_entered(datum/source, atom/movable/AM)
	mobShock(AM)

/obj/effect/anomaly/flux/Bump(atom/A)
	mobShock(A)

CAPABILITIES(/obj/effect/anomaly/flux)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	param(nameof(emp_zap), pos = 3)
	op("flux_shock", hand(), ungated(), label("Interaction flux shock"), then(PROC_REF(interaction_flux_shock)))
	op("flux_shock_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT), label("Interaction flux shock"), then(PROC_REF(interaction_flux_shock)))

/// Something walked into it (the bump action's notice).
/obj/effect/anomaly/flux/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	mobShock(AM)

/// Old attack_hand and attackby: touching the flux anomaly, bare or with an item, shocks you; the touch carries on.
/obj/effect/anomaly/flux/proc/interaction_flux_shock(datum/act/op/A)
	var/mob/user = A.actor
	mobShock(user)
	return OP_DECLINE

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

/obj/effect/anomaly/flux/anomalyPulse()
	if(!..())
		return
	switch(stats.severity)
		if(0 to 15)
			fx_sparks(src, 3)
		if(16 to 33)
			tesla_zap(src, 2, 1000, FALSE, FALSE, current_jumps = 1) //Can't chain jumps.
		if(34 to 65)
			tesla_zap(src, 3, 1000, FALSE, FALSE, current_jumps = 1)
			after(src, 3 SECONDS, GLOBAL_PROC_REF(tesla_zap), with = list(src, 3, 1500, FALSE, FALSE))
		else
			tesla_zap(src, 4, 1000, FALSE, TRUE, current_jumps = 1)
			after(src, 3 SECONDS, PROC_REF(highSevPulse))

/obj/effect/anomaly/flux/proc/highSevPulse(power, explosive, current_jumps)
	tesla_zap(src, 4, 1250, FALSE, FALSE, current_jumps = 1)
	after(src, 3 SECONDS, GLOBAL_PROC_REF(tesla_zap), with = list(src, 4, 1500, FALSE, FALSE))
