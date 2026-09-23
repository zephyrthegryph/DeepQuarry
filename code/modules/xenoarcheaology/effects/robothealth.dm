/// Verified to work with the Artifact Harvester
#define ROBO_HEAL 1
#define ROBO_HARM 2
/datum/artifact_effect/robohealth
	name = "Robotic Healing"
	var/last_message
	effect_type = EFFECT_ROBOT_HEALTH
	effect_color = "#3879ad"
	var/health_type = ROBO_HEAL

/datum/artifact_effect/robohealth/New()
	..()
	health_type = pick(ROBO_HEAL, ROBO_HARM)
	if(health_type == ROBO_HARM)
		effect_color = "#5432cf"
	else
		effect_color = "#3879ad"

/datum/artifact_effect/robohealth/DoEffectTouch(mob/user)
	if(user)
		if(isrobot(user))
			var/mob/living/silicon/robot/R = user
			if(health_type == ROBO_HEAL)
				to_chat(R, span_blue("Your systems report damaged components mending by themselves!"))
				R.mend(TREAT_PLATING_REPAIR, rand(10,30))
				R.mend(TREAT_WIRING_REPAIR, rand(10,30))
			else
				to_chat(R, span_red("Your systems report severe damage has been inflicted!"))
				R.injure(INJURY_BLUNT, rand(10,50))
				R.injure(INJURY_ELECTRIC, rand(10,50))
			return 1

/datum/artifact_effect/robohealth/DoEffectAura()
	var/atom/holder = get_master_holder()
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/silicon/robot/M in range(src.effectrange,T))
			if(health_type == ROBO_HEAL)
				if(world.time - last_message > 200)
					to_chat(M, span_blue("SYSTEM ALERT: Beneficial energy field detected!"))
					last_message = world.time
				M.mend(TREAT_PLATING_REPAIR, 1)
				M.mend(TREAT_WIRING_REPAIR, 1)
			else
				if(world.time - last_message > 200)
					to_chat(M, span_red("SYSTEM ALERT: Harmful energy field detected!"))
					last_message = world.time
				M.injure(INJURY_BLUNT, 1, null, null, 0, null, INJURE_SILENT)
				M.injure(INJURY_ELECTRIC, 1, null, null, 0, null, INJURE_SILENT)
		return 1

/datum/artifact_effect/robohealth/DoEffectPulse()
	var/atom/holder = get_master_holder()
	if(holder)
		var/turf/T = get_turf(holder)
		for (var/mob/living/silicon/robot/M in range(src.effectrange,T))
			if(health_type == ROBO_HEAL)
				if(world.time - last_message > 200)
					to_chat(M, span_blue("SYSTEM ALERT: Structural damage has been repaired by energy pulse!"))
					last_message = world.time
				M.mend(TREAT_PLATING_REPAIR, 10)
				M.mend(TREAT_WIRING_REPAIR, 10)
			else
				if(world.time - last_message > 200)
					to_chat(M, span_red("SYSTEM ALERT: Structural damage inflicted by energy pulse!"))
					last_message = world.time
				M.injure(INJURY_BLUNT, 10, null, null, 0, null, INJURE_SILENT)
				M.injure(INJURY_ELECTRIC, 10, null, null, 0, null, INJURE_SILENT)
		return 1

#undef ROBO_HEAL
#undef ROBO_HARM
