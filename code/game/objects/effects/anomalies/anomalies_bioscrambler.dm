/obj/effect/anomaly/bioscrambler
	name = "bioscrambler anomaly"
	icon_state = "bioscrambler"
	anomaly_core = /obj/item/assembly/signaler/anomaly/bioscrambler
	pass_flags = PASSTABLE | PASSGLASS | PASSGRILLE
	layer = ABOVE_MOB_LAYER
	lifespan = ANOMALY_COUNTDOWN_TIMER * 2
	danger_mult = 1.1

	/// Relation view: who are we moving towards?
	var/mob/living/pursuit_target
	/// Cooldown for every anomaly pulse
	COOLDOWN_DECLARE(pulse_cooldown)
	/// How many seconds between each anomaly pulse
	var/pulse_delay = 10 SECONDS
	/// Range of anomaly pulse
	var/range = 2

/obj/effect/anomaly/bioscrambler/Initialize(mapload, new_lifespan, drops_core)
	. = ..()
	rel_set(src, nameof(pursuit_target), find_nearest_target())

/obj/effect/anomaly/bioscrambler/anomalyEffect(seconds_per_tick)
	. = ..()
	if(stats)
		return
	if(!COOLDOWN_FINISHED(src, pulse_cooldown))
		return

	new /obj/effect/temp_visual/circle_wave/bioscrambler(get_turf(src))
	play_sfx(src, SFX_EFFECTS_COSMIC_ENERGY)
	COOLDOWN_START(src, pulse_cooldown, pulse_delay)
	for(var/mob/living/carbon/human/nearby in viewers(range, src))
		var/susceptibility = GetAnomalySusceptibility(nearby)
		if(prob(susceptibility * 100))
			randmutb(nearby)
			domutcheck(nearby, null)
			nearby.balloon_alert(nearby, "something has changed about you")

/obj/effect/anomaly/bioscrambler/move_anomaly()
	update_target()
	if(isnull(pursuit_target))
		return ..()
	var/turf/step_turf = get_step(src, get_dir(src, pursuit_target))
	step_to(src, step_turf)

/obj/effect/anomaly/bioscrambler/proc/update_target()
	var/mob/living/current_target = pursuit_target
	if(QDELETED(current_target))
		rel_clear(src, nameof(pursuit_target))
	if(!isnull(pursuit_target) && prob(80))
		return
	var/mob/living/new_target = find_nearest_target()
	if(isnull(new_target))
		rel_clear(src, nameof(pursuit_target))
		return
	if(new_target == current_target)
		return
	if(isbelly(new_target.loc) || istype(new_target.loc, /area/crew_quarters))
		return
	current_target = new_target
	rel_set(src, nameof(pursuit_target), new_target)

/obj/effect/anomaly/bioscrambler/proc/find_nearest_target()
	var/closest_distance = INFINITY
	var/mob/living/carbon/closest_target = null
	for(var/mob/living/carbon/target in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(target.z != z)
			continue
		if(in_godmode(target))
			continue
		if(target.stat >= UNCONSCIOUS)
			continue
		if(istype(get_area(target), /area/crew_quarters))
			continue
		var/distance_from_target = get_dist(src, target)
		if(distance_from_target >= closest_distance)
			continue
		closest_distance = distance_from_target
		closest_target = target

	return closest_target

/// A bioscrambler anomaly subtype which does not pursue people, for purposes of a space ruin
/obj/effect/anomaly/bioscrambler/docile

/obj/effect/anomaly/bioscrambler/docile/update_target()
	return

/obj/effect/anomaly/bioscrambler/detonate()
	COOLDOWN_RESET(src, pulse_cooldown)
	anomalyEffect()

/obj/effect/anomaly/bioscrambler/anomalyPulse()
	if(!..())
		return

	switch(stats.severity)
		if(0 to 15)
			fx_sparks(src, 3)
		else
			anomalyEffect()
