/obj/effect/anomaly/grav
	name = "gravitational anomaly"
	icon_state = "gravity"
	density = FALSE
	anomaly_core = /obj/item/assembly/signaler/anomaly/grav
	var/boing = FALSE
	var/object_launch_prob = 20

/obj/effect/anomaly/grav/Initialize(mapload, new_lifespan)
	. = ..()
	apply_wibbly_filters(src)

/obj/effect/anomaly/grav/anomalyEffect(seconds_per_tick)
	..()
	if(stats)
		return
	boing = TRUE
	for(var/obj/O in orange(4, src))
		if(!O.anchored)
			step_towards(O, src)
	for(var/mob/living/M in range(0, src))
		if(ishuman(M))
			var/mob/living/carbon/human/human = M
			if(istype(human.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes/magboots) && (human.get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP))
				continue
		gravShock(M)
	for(var/mob/living/M in range(4, src))
		if(ishuman(M))
			var/mob/living/carbon/human/human = M
			if(istype(human.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes/magboots) && (human.get_equipped_item(SLOT_ID_SHOES).item_flags & NOSLIP))
				continue
		step_towards(M, src)
	for(var/obj/O in range(0, src))
		if(O.anchored)
			continue
		var/mob/living/target = locate_in_list(view(4, src), /mob/living)
		if(target && !target.stat && prob(object_launch_prob))
			O.throw_at(target, 5, 10)

/obj/effect/anomaly/grav/Crossed(atom/movable/AM, oldloc)
	. = ..()
	on_entered(loc, AM)

/// Something entered our turf: Crossed().
/obj/effect/anomaly/grav/proc/on_entered(datum/source, atom/movable/AM)
	gravShock(AM)

/obj/effect/anomaly/grav/Bump(atom/A)
	gravShock(A)

CAPABILITIES(/obj/effect/anomaly/grav)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))

/// Something walked into it (the bump action's notice).
/obj/effect/anomaly/grav/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	gravShock(AM)

/obj/effect/anomaly/grav/proc/gravShock(mob/living/living_debris)
	if(boing && isliving(living_debris) && !living_debris.stat && !living_debris.can_overcome_gravity())
		living_debris.status_set(STAT_STUNNED, 2)
		var/atom/target = get_edge_target_turf(living_debris, get_dir(src, get_step_away(living_debris, src)))
		living_debris.throw_at(target, 5, 1)
		boing = FALSE

/obj/effect/anomaly/grav/detonate()
	new /obj/effect/temp_visual/circle_wave/gravity(get_turf(src))
	play_sfx(src, SFX_EFFECTS_COSMIC_ENERGY, vary = FALSE)

/obj/effect/temp_visual/circle_wave/gravity
	color = COLOR_NAVY

/obj/effect/anomaly/grav/anomalyPulse()
	if(!..())
		return
	switch(stats.severity)
		if(0 to 15)
			fx_sparks(src, 3)
		else
			anomalyEffect()
