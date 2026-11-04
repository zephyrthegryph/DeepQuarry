/obj/item/clothing/suit/armor/reactive/weather
	name = "reactive metereological armor"
	desc = "An experimental suit of armor that manipulates the weather around the wearer when in danger."
	emp_message = span_warning("The reactive armor's weather control unit sputters and groans...")
	cooldown_message = span_danger("The reactive weather system is still recharging! It fails to activate!")
	reactivearmor_cooldown_duration = 30 SECONDS

/obj/item/clothing/suit/armor/reactive/weather/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(owner, null, others = span_danger("The reactive armor alters the weather around %U%, shielding %THEM% from [attack_text]!"))
	play_sfx(src, SFX_EFFECTS_LIGHTNINGBOLT, 0.33)

	new /obj/effect/effect/smoke/bad(get_turf(loc))

	var/list/affected_turfs = list()
	for(var/mob/living/attacker in oview(2, owner))
		attacker.adjust_wet_stacks(5)
		attacker.extinguish_mob()

		var/turf/location = get_turf(attacker)
		if(!location.is_outdoors())
			continue

		for(var/turf/simulated/open/to_affect in view(1, attacker.loc))
			affected_turfs += to_affect

		shock_turf_windup(attacker.loc)

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/weather/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor malfunctions, calling down a storm upon [owner.p_them()]!"))
	play_sfx(src, SFX_EFFECTS_LIGHTNINGBOLT, 0.33)

	new /obj/effect/effect/smoke/bad(loc)

	if(!isopenturf(owner.loc))
		return
	shock_turf_windup(owner.loc)

/obj/item/clothing/suit/armor/reactive/weather/proc/shock_turf_windup(turf/target)
	after(src, 1 SECOND, GLOBAL_PROC_REF(lightning_strike), with = list(target))
