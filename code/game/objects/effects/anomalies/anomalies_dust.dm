/obj/effect/anomaly/dust
	name = "dust anomaly"
	icon_state = "dust"
	density = FALSE
	anomaly_core = /obj/item/assembly/signaler/anomaly/dust
	pass_flags = PASSTABLE | PASSGRILLE
	layer = ABOVE_MOB_LAYER
	lifespan = ANOMALY_COUNTDOWN_TIMER * 1.5
	danger_mult = 0.75

	move_chance = 80

	COOLDOWN_DECLARE(pulse_cooldown)
	var/pulse_delay = 5 SECONDS

/obj/effect/anomaly/dust/Initialize(mapload, new_lifespan, drops_core)
	. = ..()

	animate(src, transform = matrix()*0.85, time = 3, loop = -1)
	animate(transform = matrix(), time = 3, loop = -1)

/obj/effect/anomaly/dust/Crossed(atom/movable/AM, oldloc)
	. = ..()
	on_entered(loc, AM)

/// Something entered our turf: Crossed().
/obj/effect/anomaly/dust/proc/on_entered(datum/source, atom/movable/AM)
	if(istype(AM, /turf/simulated/floor))
		var/turf/simulated/floor/floor = AM
		if(floor.can_dirty)
			floor.dirt += 50
			floor.update_dirt()

/obj/effect/anomaly/dust/anomalyEffect(seconds_per_tick)
	. = ..()

	if(!COOLDOWN_FINISHED(src, pulse_cooldown))
		return

	new /obj/effect/temp_visual/circle_wave/dirt(get_turf(src))
	play_sfx(src, SFX_EFFECTS_COSMIC_ENERGY)
	COOLDOWN_START(src, pulse_cooldown, pulse_delay)
	for(var/mob/living/carbon/human/person in viewers(5, src))
		person.germ_level += rand(5, 10)
		if(HAS_SYNTHETIC_BIOLOGY(person))
			continue
		if(person.is_mouth_covered())
			continue
		if(!person.has_lungs())
			continue
		person.emote(prob(50) ? "cough" : "sneeze")
		person.status_at_least(STAT_STUNNED, 2)
		person.body?.add_restriction(src, BF_GAS_EXCHANGE, 0.4, 10 SECONDS) // dust coats the lungs
		if(prob(15))
			person.status_at_least(STAT_STUNNED, 2)
			to_chat(person, span_danger(pick("You have a coughing fit!", "You can't stop coughing!")))
			after(src, 3 SECONDS, PROC_REF(extraCough), with = list(person))

	for(var/turf/simulated/floor/ground in circleviewturfs(src, 3))
		if(ground.can_dirty)
			ground.dirt += 20
			ground.update_dirt()

		if(prob(1))
			new /obj/random/mob/vermin(ground)

		if(prob(2))
			new /obj/effect/decal/cleanable/filth(ground)

/obj/effect/anomaly/dust/proc/extraCough(mob/living/coughing)
	if(!coughing)
		return
	coughing.emote("cough")
	after(coughing, 3 SECONDS, TYPE_PROC_REF(/mob, emote), with = list("cough"))

/obj/effect/anomaly/dust/detonate()
	COOLDOWN_RESET(src, pulse_cooldown)
	anomalyEffect()

/obj/effect/anomaly/dust/anomalyPulse()
	if(!..())
		return

	switch(stats.severity)
		if(0 to 15)
			fx_sparks(src, 3)
		else
			anomalyEffect()
