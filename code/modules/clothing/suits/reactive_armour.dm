/obj/item/clothing/suit/armor/reactive_armor_shell
	name = "reactive armor shell"
	desc = "An experimental suit of armor, awaiting installation of an anomaly core."
	icon_state = "reactiveoff"
	w_class = ITEMSIZE_COST_LARGE
	resistance_flags = FIRE_PROOF | UNACIDABLE

CAPABILITIES(/obj/item/clothing/suit/armor/reactive_armor_shell)
	op("reactive_shell_insert_core", item(/obj/item/assembly/signaler/anomaly), label("Insert anomaly core"), then(PROC_REF(reactive_shell_insert_core)))

/// Old attackby: install an anomaly core.
/obj/item/clothing/suit/armor/reactive_armor_shell/proc/reactive_shell_insert_core(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/static/list/anomaly_armour_types = list(
		/obj/effect/anomaly/grav = /obj/item/clothing/suit/armor/reactive/repulse,
		/obj/effect/anomaly/flux = /obj/item/clothing/suit/armor/reactive/tesla,
		/obj/effect/anomaly/bluespace = /obj/item/clothing/suit/armor/reactive/teleport,
		//obj/effect/anomaly/bioscrambler = /obj/item/clothing/suit/armor/reactive/bioscrambling,
		/obj/effect/anomaly/hallucination = /obj/item/clothing/suit/armor/reactive/hallucinating,
		/obj/effect/anomaly/dimensional = /obj/item/clothing/suit/armor/reactive/barricade,
		/obj/effect/anomaly/pyro = /obj/item/clothing/suit/armor/reactive/fire,
		/obj/effect/anomaly/weather = /obj/item/clothing/suit/armor/reactive/weather
	)

	if(istype(I, /obj/item/assembly/signaler/anomaly))
		var/obj/item/assembly/signaler/anomaly/anomaly = I
		var/armour_path = is_path_in_list(anomaly.anomaly_type, anomaly_armour_types, TRUE)
		if(!armour_path)
			armour_path = /obj/item/clothing/suit/armor/reactive/stealth
		var/anomaly_name = "[anomaly]"
		if(!consume(anomaly, user))
			return TRUE
		to_chat(user, span_notice("You insert [anomaly_name] into the chest plate, and the armour gently hums to life."))
		replace_with(src, armour_path)
		return TRUE
	return OP_DECLINE

/obj/item/clothing/suit/armor/reactive
	name = "reactive armor"
	desc = "Doesn't seem to do much for some reason."
	icon_state = "reactiveoff"
	blood_overlay_type = "armor"
	armor_spec = "melee=40;bullet=35;laser=35;energy=10;bomb=10"
	var/hit_reaction_chance = 50
	///Whether the armor will try to react to hits (is it on)
	var/active = FALSE
	///This will be true for 30 seconds after an EMP, it makes the reaction effect dangerous to the user.
	COOLDOWN_DECLARE(bad_effect)
	///Message sent when the armor is emp'd. It is not the message for when the emp effect goes off.
	var/emp_message = span_warning("The reactive armor has been emp'd! Damn, now it's REALLY gonna not do much!")
	///Message sent when the armor is still on cooldown, but activates.
	var/cooldown_message = span_danger("The reactive armor fails to do much, as it is recharging! From what? Only the reactive armor knows.")
	///Duration of the cooldown specific to reactive armor for when it can activate again.
	var/reactivearmor_cooldown_duration = 10 SECONDS
	///The cooldown itself of the reactive armor for when it can activate again.
	var/reactivearmor_cooldown = 0

	special_handling = TRUE

APPEARANCE_TEMPLATE(/obj/item/clothing/suit/armor/reactive, "reactive{active?:off}")

TRACKED(/obj/item/clothing/suit/armor/reactive, active)

CAPABILITIES(/obj/item/clothing/suit/armor/reactive)
	op("toggle", in_hand(), label("Toggle"), then(PROC_REF(reactive_toggled)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(reactive_emp_glitch)))

/obj/item/clothing/suit/armor/reactive/proc/reactive_toggled(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	to_chat(user, span_notice("[src] is now [active ? "active" : "inactive"]."))
	update_icon()
	add_fingerprint(user)

/obj/item/clothing/suit/armor/reactive/handle_shield(mob/user, damage, atom/damage_source, mob/attacker, def_zone, attack_text)
	if(!active || !prob(hit_reaction_chance))
		return FALSE
	if(!COOLDOWN_FINISHED(src, reactivearmor_cooldown))
		cooldown_activation(user)
		return FALSE
	if(!COOLDOWN_FINISHED(src, bad_effect))
		return emp_activation(user, damage_source, attack_text, damage)
	else
		return reactive_activation(user, damage_source, attack_text, damage)

/obj/item/clothing/suit/armor/reactive/proc/cooldown_activation(mob/living/carbon/human/owner)
	owner.visible_message(cooldown_message)

/obj/item/clothing/suit/armor/reactive/proc/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor doesn't do much! No surprises here."))
	return TRUE

/obj/item/clothing/suit/armor/reactive/proc/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor doesn't do much, despite being emp'd! Besides giving off a special message, of course."))
	return TRUE


/// A pulse makes active armour act up (at most once per cooldown).
/obj/item/clothing/suit/armor/reactive/proc/reactive_emp_glitch(datum/act/A)
	if(!COOLDOWN_FINISHED(src, bad_effect) || !active)
		return
	visible_message(emp_message)
	COOLDOWN_START(src, bad_effect, 30 SECONDS)

/obj/item/clothing/suit/armor/reactive/teleport
	name = "reactive teleport armor"
	desc = "Someone separated our Research Director from his own head!"
	emp_message = span_warning("The reactive armor's teleportation calculations begin spewing errors!")
	cooldown_message = span_danger("The reactive teleport system is still recharging! It fails to activate!")
	reactivearmor_cooldown_duration = 10 SECONDS
	var/tele_range = 6

/obj/item/clothing/suit/armor/reactive/teleport/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", final_block_chance = 0, damage = 0)
	act_message(owner, null, others = span_danger("The reactive teleport system flings %U% clear of [attack_text]!"))
	play_sfx(get_turf(owner), SFX_EFFECTS_PHASEIN)
	do_teleport(owner, get_turf(owner), tele_range, no_effects = TRUE, channel = TELEPORT_CHANNEL_BLUESPACE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/teleport/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", final_block_chance = 0, damage = 0)
	owner.visible_message(span_danger("The reactive teleport system flings itself clear of [attack_text], leaving someone behind in the process!"))
	owner.drop_from_inventory(src, get_turf(src))
	play_sfx(get_turf(owner), SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
	play_sfx(get_turf(owner), SFX_EFFECTS_PHASEIN)
	do_teleport(src, get_turf(owner), tele_range, no_effects = TRUE, channel = TELEPORT_CHANNEL_BLUESPACE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE


/obj/item/clothing/suit/armor/reactive/repulse
	name = "reactive repulse armor"
	desc = "An experimental suit of armor that violently throws back attackers."
	cooldown_message = span_danger("The repulse generator is still recharging! It fails to generate a strong enough wave!")
	emp_message = span_warning("The repulse generator is reset to default settings...")

/obj/item/clothing/suit/armor/reactive/repulse/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	play_sfx(get_turf(owner), SFX_EFFECTS_REPULSE)
	owner.visible_message(span_danger("[src] blocks [attack_text], converting the attack into a wave of force!"))
	var/turf/owner_turf = get_turf(owner)
	var/list/thrown_items = list()
	for(var/atom/movable/repulsed in range(owner_turf, 5))
		if(repulsed == owner || repulsed.anchored || thrown_items[repulsed])
			continue
		var/throwtarget = get_edge_target_turf(owner_turf, get_dir(owner_turf, get_step_away(repulsed, owner_turf)))
		repulsed.throw_at(throwtarget, 10, 1)
		thrown_items[repulsed] = repulsed

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/repulse/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	play_sfx(get_turf(owner), SFX_EFFECTS_REPULSE)
	owner.visible_message(span_danger("[src] does not block [attack_text], and instead generates an attracting force!"))
	var/turf/owner_turf = get_turf(owner)
	var/list/thrown_items = list()
	for(var/atom/movable/repulsed in range(owner_turf, 5))
		if(repulsed == owner || repulsed.anchored || thrown_items[repulsed])
			continue
		repulsed.throw_at(owner, 10, 1)
		thrown_items[repulsed] = repulsed

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE


// Tesla

/obj/item/clothing/suit/armor/reactive/tesla
	name = "reactive tesla armor"
	desc = "An experimental suit of armor with sensitive detectors hooked up to a huge capacitor grid, with emitters strutting out of it. Zap."
	siemens_coefficient = -1
	cooldown_message = span_danger("The tesla capacitors on the reactive tesla armor are still recharging! The armor merely emits some sparks.")
	emp_message = span_warning("The tesla capacitors beep ominously for a moment.")
	clothing_traits = list(TRAIT_TESLA_SHOCKIMMUNE)
	/// How strong are the zaps we give off?
	var/zap_power = 2.5e4
	/// How far to the zaps we give off go?
	var/zap_range = 20

/obj/item/clothing/suit/armor/reactive/tesla/cooldown_activation(mob/living/carbon/human/owner)
	fx_sparks(src, 1)
	..()

/obj/item/clothing/suit/armor/reactive/tesla/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("[src] blocks [attack_text], sending out arcs of lightning!"))
	tesla_zap(owner, zap_range, zap_power, current_jumps = 1)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/tesla/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(src, owner, others = span_danger("%U% blocks [attack_text], but pulls a massive charge of energy into %T% from the surrounding environment!"))
	REMOVE_CLOTHING_TRAIT(owner, TRAIT_TESLA_SHOCKIMMUNE)
	electrocute_mob(owner, get_area(src), src, 1)
	ADD_CLOTHING_TRAIT(owner, TRAIT_TESLA_SHOCKIMMUNE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

// Sure we could, but- Not really THAT useful. Give them the stealth one.
/obj/item/clothing/suit/armor/reactive/bioscrambling

// Hallucinating

/obj/item/clothing/suit/armor/reactive/hallucinating
	name = "reactive hallucinating armor"
	desc = "An experimental suit of armor with sensitive detectors hooked up to the mind of the wearer, sending mind pulses that causes hallucinations around you."
	cooldown_message = span_danger("The connection is currently out of sync... Recalibrating.")
	emp_message = span_warning("You feel the backsurge of a mind pulse.")
	clothing_traits = list(TRAIT_MADNESS_IMMUNE)

/obj/item/clothing/suit/armor/reactive/hallucinating/cooldown_activation(mob/living/carbon/human/owner)
	fx_sparks(src, 1)
	..()

/obj/item/clothing/suit/armor/reactive/hallucinating/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("[src] blocks [attack_text], sending out mental pulses!"))
	for(var/mob/living/carbon/human/hallucinator in viewers(5, get_turf(src)))
		if(hallucinator == owner)
			continue
		hallucinator.status_adjust(STAT_HALLUCINATING, 50)
		if(prob(10))
			to_chat(hallucinator, span_danger("Your nose bleeds!"))
			hallucinator.drip(1)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/hallucinating/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(src, owner, others = span_danger("%U% blocks [attack_text], but pulls a massive charge of mental energy into %T% from the surrounding environment!"))
	owner.status_adjust(STAT_HALLUCINATING, 75)
	to_chat(owner, span_danger("Your nose bleeds!"))
	owner.drip(1)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

// When the wearer gets hit, this armor will push people nearby and spawn some blocking objects.
/obj/item/clothing/suit/armor/reactive/barricade
	name = "reactive barricade armor"
	desc = "An experimental suit of armor that generates barriers from another world when it detects its bearer is in danger."
	emp_message = span_warning("The reactive armor's dimensional coordinates are scrambled!")
	cooldown_message = span_danger("The reactive barrier system is still recharging! It fails to activate!")
	reactivearmor_cooldown_duration = 10 SECONDS

/obj/item/clothing/suit/armor/reactive/barricade/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	play_sfx(get_turf(owner), SFX_EFFECTS_REPULSE)
	owner.visible_message(span_danger("The reactive armor interposes matter from another world between [src] and [attack_text]!"))
	for (var/atom/movable/target in repulse_targets(owner))
		repulse(target, owner)

	var/datum/armour_dimensional_theme/theme = dq_proto(/datum/armour_dimensional_theme)
	theme.apply_random(get_turf(owner), dangerous = FALSE)

	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/barricade/proc/repulse_targets(atom/source)
	var/list/push_targets = list()
	for (var/atom/movable/nearby_movable in view(1, source))
		if(nearby_movable == source)
			continue
		if(nearby_movable.anchored)
			continue
		push_targets += nearby_movable
	return push_targets

/obj/item/clothing/suit/armor/reactive/barricade/proc/repulse(atom/movable/victim, atom/source)
	var/dist_from_caster = get_dist(victim, source)

	if(dist_from_caster == 0)
		return

	if (isliving(victim))
		to_chat(victim, span_userdanger("You're thrown back by a wave of pressure!"))
	var/turf/throwtarget = get_edge_target_turf(source, get_dir(source, get_step_away(victim, source, 1)))
	victim.throw_at(throwtarget, 1, 1)

/obj/item/clothing/suit/armor/reactive/barricade/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("The reactive armor shunts matter from an unstable dimension!"))
	var/datum/armour_dimensional_theme/theme = dq_proto(/datum/armour_dimensional_theme)
	theme.apply_random(get_turf(owner), dangerous = TRUE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE

// FIRE
/obj/item/clothing/suit/armor/reactive/fire
	name = "reactive incendiary armor"
	desc = "An experimental suit of armor with a reactive sensor array rigged to a flame emitter. For the stylish pyromaniac."
	cooldown_message = span_danger("The reactive incendiary armor activates, but fails to send out flames as it is still recharging its flame jets!")
	emp_message = span_warning("The reactive incendiary armor's targeting system begins rebooting...")

/obj/item/clothing/suit/armor/reactive/fire/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	owner.visible_message(span_danger("[src] blocks [attack_text], sending out jets of flame!"))
	play_sfx(get_turf(owner), SFX_MAGIC_FIREBALL)
	for(var/mob/living/carbon_victim in range(6, get_turf(src)))
		if(carbon_victim != owner)
			carbon_victim.adjust_fire_stacks(8)
			carbon_victim.ignite_mob()
	owner.set_wet_stacks(20)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/fire/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	act_message(src, owner, others = span_danger("%U% just makes [attack_text] worse by spewing molten death on %T%!"))
	play_sfx(get_turf(owner), SFX_MAGIC_FIREBALL)
	owner.adjust_fire_stacks(12)
	owner.ignite_mob()
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE

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

/obj/item/clothing/suit/armor/reactive/stealth
	name = "reactive stealth armor"
	desc = "An experimental suit of armor that renders the wearer invisible on detection of imminent harm, and creates a decoy that runs away from the owner. You can't fight what you can't see."
	cooldown_message = span_danger("The reactive stealth system activates, but is not charged enough to fully cloak!")
	emp_message = span_warning("The reactive stealth armor's threat assessment system crashes...")
	///when triggering while on cooldown will only flicker the alpha slightly. this is how much it removes.
	var/cooldown_alpha_removal = 50
	///cooldown alpha flicker- how long it takes to return to the original alpha
	var/cooldown_animation_time = 3 SECONDS
	///how long they will be fully stealthed
	var/stealth_time = 4 SECONDS
	///how long it will animate back the alpha to the original
	var/animation_time = 2 SECONDS
	var/in_stealth = FALSE

/obj/item/clothing/suit/armor/reactive/stealth/cooldown_activation(mob/living/carbon/human/owner)
	if(in_stealth)
		return
	owner.alpha = max(0, owner.alpha - cooldown_alpha_removal)
	animate(owner, alpha = initial(owner.alpha), time = cooldown_animation_time)
	..()

/obj/item/clothing/suit/armor/reactive/stealth/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text, final_block_chance, damage)
	var/mob/living/simple_mob/illusion/decoy = new(owner.loc)
	decoy.copy_appearance(owner)
	decoy.copy_overlays(owner, TRUE)
	var/turf/rand_turf = pick(get_turf(orange(5, 10)))
	decoy.ai_brain?.give_destination(rand_turf)
	owner.alpha = 0
	in_stealth = TRUE
	act_message(owner, null, others = span_danger("%U% is hit by [attack_text] in the chest!"))
	after(src, stealth_time, PROC_REF(end_stealth), with = list(owner), keeps_dead = TRUE)
	decoy.say("*sidestep")
	after(src, stealth_time, PROC_REF(destroy_illusion), with = list(decoy))
	decoy.expire(stealth_time)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/stealth/proc/end_stealth(mob/living/carbon/human/owner)
	in_stealth = FALSE
	if(owner)
		animate(owner, alpha = initial(owner.alpha), time = animation_time)

/obj/item/clothing/suit/armor/reactive/stealth/proc/destroy_illusion(mob/illusion)
	if(QDELETED(illusion))
		return
	fx_sparks(illusion, 3, 3)
	illusion.expire(animation_time)

/obj/item/clothing/suit/armor/reactive/stealth/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", damage = 0)
	if(!isliving(hitby))
		return FALSE
	var/mob/living/attacker = hitby
	owner.visible_message(span_danger("[src] activates, cloaking the wrong person!"))
	attacker.alpha = 0
	after(attacker, 4 SECONDS, GLOBAL_PROC_REF(reactive_cloak_wear_off), with = list(attacker, initial(attacker.alpha)))
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE

/// after() target: the misfired cloak wears off.
/proc/reactive_cloak_wear_off(mob/living/attacker, old_alpha)
	attacker.alpha = old_alpha
