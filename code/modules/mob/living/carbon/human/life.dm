//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

//NOTE: Breathing happens once per FOUR TICKS, unless the last breath fails. In which case it happens once per ONE TICK!
//A breath doesn't harm or heal: it reports its quality (0..1) to the physiology, which decides whether the patient suffocates.

#define HEAT_DAMAGE_LEVEL_1 2 //Amount of damage applied when your body temperature just passes the 360.15k safety point
#define HEAT_DAMAGE_LEVEL_2 4 //Amount of damage applied when your body temperature passes the 400K point
#define HEAT_DAMAGE_LEVEL_3 8 //Amount of damage applied when your body temperature passes the 1000K point

#define COLD_DAMAGE_LEVEL_1 0.5 //Amount of damage applied when your body temperature just passes the 260.15k safety point
#define COLD_DAMAGE_LEVEL_2 1.5 //Amount of damage applied when your body temperature passes the 200K point
#define COLD_DAMAGE_LEVEL_3 3 //Amount of damage applied when your body temperature passes the 120K point

#define HUMAN_COMBUSTION_TEMP 524 //524k is the sustained combustion temperature of human fat

/mob/living/carbon/human
	var/heartbeat = 0
	var/chemical_darksight = 0
	/// world.time of the next periodic full HUD refresh (hud refresh system).
	EXPIRY_DECLARE(hud_full_refresh_at)

// Human Life (doc/rewrite/life_sequences.md; declared in life_steps.dm). The living core runs first; the human-only
// steps that followed ..() in the old Life() run in the LIFE_TAIL band below, in their old order (the HUD and its
// periodic full refresh are reactions: life_hud_pass() below and living_systems.dm):
//	voice, stasis sleep, fall,
//	[alive, not in stasis] changeling, organs, thermoregulation, weight, shock, pain, medical,
//	                       heartbeat, NIF, phobias, NPC       (when = list("!in_stasis", "alive"))
//	species components, visible name, pulse

/// The code before ..() in the old human Life().
/mob/living/carbon/human/life_type_pre_due()
	return TRUE

/mob/living/carbon/human/life_type_pre(datum/seq_frame/life/F)
	if (src.transforming)
		return F.abort()

	//Apparently, the person who wrote this code designed it so that
	//blinded get reset each cycle and then get activated later in the
	//code. Very ugly. I dont care. Moving this stuff here so its easy
	//to find it.
	src.set_blinded(0)

	//TODO: seperate this out
	// update the current life tick, can be used to e.g. only do something every 4 ticks
	src.life_tick++
	return ..()

/// Periodic safety refresh of every HUD: once a minute every hud_updateflag bit is set. It follows
/// each reactive HUD pass and wakes on its own keyed timer while the human has a client.
#define LIFE_HUD_FULL_REFRESH_REWAKE "life_hud_full_refresh"

/mob/living/carbon/human/life_hud_pass()
	..()
	life_hud_full_refresh_pass()

/mob/living/carbon/human/proc/life_hud_full_refresh_pass()
	if(!life_placed())
		return
	life_hud_full_refresh()
	if(client)
		after(src, max(1 SECONDS, hud_full_refresh_at - world.time), PROC_REF(life_hud_full_refresh_rewake), key = LIFE_HUD_FULL_REFRESH_REWAKE, clock = CLOCK_WORLD)

/mob/living/carbon/human/proc/life_hud_full_refresh_rewake()
	if(QDELETED(src) || !life_hud_wanted())
		return
	life_hud_full_refresh_pass()

/mob/living/carbon/human/proc/life_hud_full_refresh()
	// The periodic safety refresh is intentionally rare (once a minute); state-changing
	// code continues to set its exact HUD dirty bits.
	if(!BEFORE(src, hud_full_refresh_at, CLOCK_WORLD))
		EXPIRY_SET(src, hud_full_refresh_at, 1 MINUTES, CLOCK_WORLD)
		hud_updateflag = (1 << TOTAL_HUDS) - 1
		PUBLISH_CHANGE(src, MOB_KEY_HUD_FLAGS)

/// The voice others hear.
/mob/living/carbon/human/proc/life_voice(datum/seq_frame/life/F)
	src.voice = src.GetVoice()

/// Event-driven: equipment (masks, voice changers, rigs), the body, stat and moving (belly
/// absorb) wake it. Voice changers, changeling mimicry and disguises toggle from scattered
/// sites, so a slow timer backs the events up.

/mob/living/carbon/human/proc/life_voice_rewake()
	return 10 SECONDS

/// Deep stasis (BF_STASIS above STASIS_SLEEP_THRESHOLD) puts the body to sleep.
/mob/living/carbon/human/proc/life_stasis_sleep(datum/seq_frame/life/F)
	if(src.factor(BF_STASIS) > STASIS_SLEEP_THRESHOLD)
		src.status_at_least(STAT_SLEEPING, 20)

/// Factor changes (body invalidate, CHANGE_MOB_HEALTH) wake it.
/mob/living/carbon/human/proc/life_stasis_sleep_due()
	return src.factor(BF_STASIS) > STASIS_SLEEP_THRESHOLD

/// Falling (prevents people from floating).
/mob/living/carbon/human/proc/life_fall(datum/seq_frame/life/F)
	src.fall()

/// Event-driven: moving wakes it. A floor removed from under a standing player is caught by
/// the rewake.

/mob/living/carbon/human/proc/life_fall_rewake()
	return src.client ? 10 SECONDS : 0

/// Allergens, medication side effects, ischemia and the dirty medical domains.
/// MED-6: nothing to do while no trigger domain is dirty, no side effect runs, no allergen
/// reacts and the oxygen debt is below the ischemia threshold.
/mob/living/carbon/human/proc/life_medical_due()
	var/datum/body/B = src.body
	if(!B)
		return FALSE
	if((B.dirty & BODY_DIRTY_CONDITIONS) || B.factors_stale())
		return TRUE
	if(LAZYLEN(src.side_effects))
		return TRUE
	if(B.factors?[BF_ALLERGY] > 0)
		return TRUE
	return src.oxygen_debt() >= MEDICAL_STAGE_ISCHEMIA_DEBT

/// The metric triggers read body temperature and radiation, which many places write raw.
/mob/living/carbon/human/proc/life_medical_rewake()
	return 5 SECONDS

/mob/living/carbon/human/proc/life_medical(datum/seq_frame/life/F)
	if(src.has_allergies())
		src.handle_allergic_reaction(src.factor(BF_ALLERGY))

	life_medical_side_effects()
	src.dq_check_ischemic_damage()
	src.dq_process_dirty_medical_conditions()

/// Species NPC behaviour for client-less humans.
/// MED-6: a player, or a species with nothing to do for this body, has no NPC work.
/mob/living/carbon/human/proc/life_npc_due()
	return !src.client && src.species.npc_behaviour_active(src)

/mob/living/carbon/human/proc/life_npc_rewake()
	return 10 SECONDS

/mob/living/carbon/human/proc/life_npc(datum/seq_frame/life/F)
	if(!src.client)
		src.species.npc_behaviour(src)

/// The name others see: obscured or disfigured faces hide it.
/mob/living/carbon/human/proc/life_visible_name(datum/seq_frame/life/F)
	//Update our name based on whether our face is obscured/disfigured
	src.name = src.get_visible_name()

/// Event-driven like the voice system, with the same slow timer behind it.

/mob/living/carbon/human/proc/life_visible_name_rewake()
	return 10 SECONDS

// Calculate how vulnerable the human is to the current pressure.
// Returns 0 (equals 0 %) if sealed in an undamaged suit that's rated for the pressure, 1 if unprotected (equals 100%).
// Suitdamage can modifiy this in 10% steps.
// Protection scales down from 100% at the boundary to 0% at 10% in excess of the boundary
/mob/living/carbon/human/proc/get_pressure_weakness(pressure)
	if(pressure == null)
		return 1 // No protection if someone forgot to give a pressure

	var/pressure_adjustment_coefficient = 1 // Assume no protection at first.

	// Check suit
	if(get_equipped_item(SLOT_ID_SUIT) && get_equipped_item(SLOT_ID_SUIT).max_pressure_protection != null && get_equipped_item(SLOT_ID_SUIT).min_pressure_protection != null)
		pressure_adjustment_coefficient = 0
		// Pressure is too high
		if(get_equipped_item(SLOT_ID_SUIT).max_pressure_protection < pressure)
			// Protection scales down from 100% at the boundary to 0% at 10% in excess of the boundary
			pressure_adjustment_coefficient += round((pressure - get_equipped_item(SLOT_ID_SUIT).max_pressure_protection) / (get_equipped_item(SLOT_ID_SUIT).max_pressure_protection/10))

		// Pressure is too low
		if(get_equipped_item(SLOT_ID_SUIT).min_pressure_protection > pressure)
			pressure_adjustment_coefficient += round((get_equipped_item(SLOT_ID_SUIT).min_pressure_protection - pressure) / (get_equipped_item(SLOT_ID_SUIT).min_pressure_protection/10))

		// Handles breaches in your space suit. 10 suit damage equals a 100% loss of pressure protection.
		if(istype(get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
			var/obj/item/clothing/suit/space/S = get_equipped_item(SLOT_ID_SUIT)
			if(S.can_breach && S.damage)
				pressure_adjustment_coefficient += S.damage * 0.1

	else
		// Missing key protection
		pressure_adjustment_coefficient = 1

	// Check hat
	if(get_equipped_item(SLOT_ID_HEAD) && get_equipped_item(SLOT_ID_HEAD).max_pressure_protection != null && get_equipped_item(SLOT_ID_HEAD).min_pressure_protection != null)
		// Pressure is too high
		if(get_equipped_item(SLOT_ID_HEAD).max_pressure_protection < pressure)
			// Protection scales down from 100% at the boundary to 0% at 20% in excess of the boundary
			pressure_adjustment_coefficient += round((pressure - get_equipped_item(SLOT_ID_HEAD).max_pressure_protection) / (get_equipped_item(SLOT_ID_HEAD).max_pressure_protection/20))

		// Pressure is too low
		if(get_equipped_item(SLOT_ID_HEAD).min_pressure_protection > pressure)
			pressure_adjustment_coefficient += round((get_equipped_item(SLOT_ID_HEAD).min_pressure_protection - pressure) / (get_equipped_item(SLOT_ID_HEAD).min_pressure_protection/20))

	else
		// Missing key protection
		pressure_adjustment_coefficient = 1

	pressure_adjustment_coefficient = min(pressure_adjustment_coefficient, 1)
	return pressure_adjustment_coefficient

// Calculate how much of the enviroment pressure-difference affects the human.
/mob/living/carbon/human/calculate_affecting_pressure(pressure)
	var/pressure_difference

	// First get the absolute pressure difference.
	if(pressure < species.safe_pressure) // We are in an underpressure.
		pressure_difference = species.safe_pressure - pressure

	else //We are in an overpressure or standard atmosphere.
		pressure_difference = pressure - species.safe_pressure

	if(pressure_difference < 5) // If the difference is small, don't bother calculating the fraction.
		pressure_difference = 0

	else
		// Otherwise calculate how much of that absolute pressure difference affects us, can be 0 to 1 (equals 0% to 100%).
		// This is our relative difference.
		pressure_difference *= get_pressure_weakness(pressure)

	// The difference is always positive to avoid extra calculations.
	// Apply the relative difference on a standard atmosphere to get the final result.
	// The return value will be the adjusted_pressure of the human that is the basis of pressure warnings and damage.
	if(pressure < species.safe_pressure)
		return species.safe_pressure - pressure_difference
	else
		return species.safe_pressure + pressure_difference

/// The base hold work, or brain damage enough for its random fits (below 5 none of them can happen). Injuries wake the step (body invalidate):
/// always TRUE here made every human's step "have work" while its sequence slept it, a missed wake in the life audit.
/mob/living/carbon/human/life_disabilities_due()
	if(..())
		return TRUE
	return stat == CONSCIOUS && !isbelly(loc) && injury_load(INJURY_CATEGORY_NEURAL) >= 5

/mob/living/carbon/human/life_disabilities(datum/seq_frame/life/F)
	..()

	if(src.stat != CONSCIOUS) //Let's not worry about tourettes if you're not conscious.
		return

	if(isbelly(src.loc)) //Let's not have you seizing, coughing, or falling apart if you're in a belly.
		return

	var/rn = rand(0, 200)
	var/brain_damage = src.injury_load(INJURY_CATEGORY_NEURAL)
	if(brain_damage >= 5)
		if(0 <= rn && rn <= 3)
			src.custom_pain("Your head feels numb and painful.", 10)
	if(brain_damage >= 15)
		if(4 <= rn && rn <= 6) if(!src.has_status(STAT_BLURRY))
			to_chat(src, span_warning("It becomes hard to see for some reason."))
			src.status_set(STAT_BLURRY, 10)
	if(brain_damage >= 35)
		if(7 <= rn && rn <= 9) if(src.get_active_hand())
			to_chat(src, span_danger("Your hand won't respond properly, you drop what you're holding!"))
			src.drop_item()
	if(brain_damage >= 45)
		if(10 <= rn && rn <= 12)
			if(prob(50))
				to_chat(src, span_danger("You suddenly black out!"))
				src.status_at_least(STAT_PARALYZED, 10)
				src.status_at_least(STAT_SLEEPING, 10)
			else if(!src.lying)
				to_chat(src, span_danger("Your legs won't respond properly, you fall down!"))
				src.status_at_least(STAT_WEAKENED, 10)

/mob/living/carbon/human/life_mutations_due()
	return TRUE

/mob/living/carbon/human/life_mutations(datum/seq_frame/life/F)
	. = ..()
	if(.)
		return

	// Slow natural healing of wounds; cold-resistant bodies shrug off burns.
	if(src.injury_load(INJURY_CATEGORY_THERMAL))
		if((src.has_mutation(COLD_RESISTANCE)) || (prob(1)))
			src.mend(TREAT_BURN_CARE, 1)
	if(src.injury_load(INJURY_CATEGORY_PHYSICAL))
		if(prob(1))
			src.mend(TREAT_TISSUE_REPAIR, 1)

	if((src.has_mutation(mRegen)))
		var/heal = rand(0.2,1.3)
		if(prob(50))
			for(var/obj/item/organ/external/O as anything in src.organs)
				src.mend(TREAT_RESTORATION, heal, O)
		else
			src.mend(TREAT_TISSUE_REPAIR, heal)
			src.mend(TREAT_BURN_CARE, heal)


// RADIATION! Everyone's favorite thing in the world! So let's get some numbers down off the bat.
// 50 rads = 1Bq. This means 1 rad = 0.02Bq.
// However, unless I am a smoothbrained dumbo, absorbed rads are in Gy. Not Bq.
// So let's just assume that 50 rads = 1Gy. Make life easier!

// ACUTE RADIATION (The stuff that the 'radiation' variable takes care of. Remember, 50radiation=1Gy.):
// Without care: 1-2Gy has a (0-5%) mortality chance. 2-6 (5-95%) 6-8 (95-100)% 8-30 (100%) >30 (100%)
// With care: 1-2Gy (0-5%), 2-6 (5-50%), 6-8 (50-100%), 8-30 (99-100%) >30 (100%)
// So let's make our thresholds based on this! 50-100, 100-300, 300-400, 400-1500, and anything above 1500!
// In reality, however, nobody should ever go above 300 radiation, which is why the cutoff before the really bad effects start to happen being
// 300 radiation is good. For reference: Breaking an artifact deals ~300 rads with no resistance. Getting shot with a lvl 3 PA deals 300 rads with no resistance.
// Nobody outside of engineering should ever have to worry about being irradiated over 300 and start getting organ damage..


// CHRONIC RADIATION (The stuff that 'accumulated_rads' takes care of):
// This is more or less for if someone was exposed for a long time to radiation or just finished being treated for extreme ARS.
// These are meant to be annoying effects to nudge someone towards medical, but not lethal or deadly.
// Things such as loss of taste, eye damage, dropping items in your hand, being temporaily weakened, etc. Stuff to annoy them and get them to fix their rads.

// Additionally, RADIATION_SPEED_COEFFICIENT = 0.1

/// Radiation burns on a random organic limb: skin sloughing from a heavy dose.
/mob/living/carbon/human/proc/radiation_burn(amount, flags = NONE)
	var/list/candidates = list()
	for(var/obj/item/organ/external/E as anything in organs)
		if(!E.is_robotic() && !E.is_stump())
			candidates += E
	if(!length(candidates))
		return 0
	var/obj/item/organ/external/E = pick(candidates)
	return injure(INJURY_BURN, amount, E.organ_tag, null, 0, /datum/affliction/radiation_burns, flags)

/// MED-6: no dose and nothing accumulated to dissipate.
/mob/living/carbon/human/life_radiation_due()
	return src.radiation || src.accumulated_rads || act_wanted(src, /datum/act/live_radiation)

/mob/living/carbon/human/life_radiation_rewake()
	return 5 SECONDS

/mob/living/carbon/human/life_radiation(datum/seq_frame/life/F)
	. = ..()
	if(.)
		return

	// B14 / P2-S12: anti-radiation treatment (reagent tags) purges through the
	// one writer instead of each drug writing the dose itself.
	var/antirad = src.body?.treatment_levels()?[TREAT_ANTIRADIATION]
	if(antirad)
		src.purge_radiation(antirad * DQ_ANTIRAD_RADS_PER_LEVEL)
	if(!src.radiation)
		src.clear_alert("irradiated")
		if(src.accumulated_rads)
			src.decay_radiation(0, -RADIATION_SPEED_COEFFICIENT) //Accumulated rads slowly dissipate very slowly. Get to medical to get it treated!
	//Radiation is a slow, insidious killer. Unless you get a massive dose, then the onset is sudden!
	else if((src.life_tick % 5 == 0) || (src.radiation > 600))
		if(has_trait(src, TRAIT_HALT_RADIATION_EFFECTS)) //If we have a trait that halts radiation effects, then we just stop here.
			return
		life_radiation_acute_radiation()
	life_radiation_chronic_radiation()

/// A23: the acute dose tier, 0 (below "safe") to 5 (above "danger_4"), from the species' radiation levels.
/mob/living/carbon/human/proc/life_radiation_dose_tier()
	var/list/levels = GLOB.radiation_levels[src.species.rad_levels]
	var/static/list/tier_keys = list("safe", "danger_1", "danger_2", "danger_3", "danger_4")
	. = 0
	for(var/key in tier_keys)
		if(src.radiation < levels[key])
			return
		.++

/// Acute radiation sickness for this tick: dose decay, then the tier's effects. The organic
/// effects apply only to a body whose systemic biology is organic; the toxin load applies to
/// every body (the species radiation_mod decides who is affected at all).
/mob/living/carbon/human/proc/life_radiation_acute_radiation()
	// Per tier (index tier + 1): base damage and dose decay (rads per RADIATION_SPEED_COEFFICIENT).
	var/static/list/tier_damage = list(0, 1, 3, 5, 10, 30)
	var/static/list/tier_decay = list(10, 10, 30, 50, 100, 300)
	var/rad_mod = src.species.radiation_mod
	if(!rad_mod) //If we are rad immune, stop here and remove rads if we have any.
		src.decay_radiation(10 * RADIATION_SPEED_COEFFICIENT * src.species.rad_removal_mod)
		return

	var/tier = life_radiation_dose_tier()
	var/decay = tier_decay[tier + 1]
	var/damage = tier_damage[tier + 1]
	src.decay_radiation(decay * RADIATION_SPEED_COEFFICIENT * src.species.rad_removal_mod, decay * RADIATION_SPEED_COEFFICIENT) //No escape from accumulated rads.
	if(tier == 4)
		src.throw_alert("irradiated", /atom/movable/screen/alert/irradiated)
	if(!tier)
		return

	var/organic = src.biology() & BIOLOGY_ORGANIC
	if(organic)
		switch(tier)
			if(1)
				life_radiation_sickness_mild()
			if(2)
				life_radiation_sickness_moderate()
			if(3)
				life_radiation_sickness_severe(damage, rad_mod)
			if(4)
				life_radiation_sickness_critical(damage, rad_mod)
			else
				life_radiation_sickness_lethal(damage, rad_mod)

	damage *= rad_mod
	src.injure(INJURY_TOXIN, damage * RADIATION_SPEED_COEFFICIENT, null, null, 0, /datum/affliction/radiation_poisoning, INJURE_CONTINUOUS)
	if(organic && length(src.organs))
		var/obj/item/organ/external/O = pick(src.organs)
		if(istype(O))
			O.add_autopsy_data("Radiation Poisoning", damage)

/// Radiation damage to one internal organ (`organ_tag`, or a random one), logged for autopsy.
/// Returns the organ hit, or null.
/mob/living/carbon/human/proc/life_radiation_irradiate_organ(amount, autopsy_label, organ_tag, flags = NONE)
	var/obj/item/organ/internal/I
	if(organ_tag)
		I = src.organ_in(organ_tag)
	else if(length(src.internal_organ_list()))
		I = pick(src.internal_organ_list())
	if(!istype(I))
		return null
	I.add_autopsy_data(autopsy_label, amount)
	src.injure(INJURY_RADIATION, amount, I, flags = INJURE_IGNORE_RESISTANCE | flags)
	return I

/// Organ damage or, rarely, a malignant growth.
/mob/living/carbon/human/proc/life_radiation_organ_mutation(damage, rad_mod, malignant_spread_chance)
	if(!length(src.internal_organ_list()))
		return
	if(prob(2))
		src.random_malignant_organ(TRUE, FALSE, prob(malignant_spread_chance))
		return
	life_radiation_irradiate_organ(damage * rad_mod * RADIATION_SPEED_COEFFICIENT, "Radiation Induced Cancerous Growth")

/mob/living/carbon/human/proc/life_radiation_vomit()
	src.vomit() // vomit() schedules the retch itself (om_after); it doesn't sleep.

/mob/living/carbon/human/proc/life_radiation_seizure()
	to_chat(src, span_critical("You have a seizure!"))
	src.status_at_least(STAT_PARALYZED, 10)
	src.status_at_least(STAT_SLEEPING, 10)
	src.status_adjust(STAT_JITTERY, 1000)
	if(!src.lying)
		src.emote("collapse")

/// Tier 1 (1-2 Gy): fatigue, hair loss, the odd vomit.
/mob/living/carbon/human/proc/life_radiation_sickness_mild()
	if(prob(5) && prob(100 * RADIATION_SPEED_COEFFICIENT) && !src.has_status(STAT_WEAKENED))
		to_chat(src, span_warning("You feel exhausted."))
		src.status_adjust(STAT_WEAKENED, 3)
	if(prob(5) && prob(100 * RADIATION_SPEED_COEFFICIENT) && src.species.get_bodytype() == SPECIES_HUMAN) //apes go bald
		if((src.h_style != "Bald" || src.f_style != "Shaved" ))
			to_chat(src, span_warning("Your hair falls out."))
			src.h_style = "Bald"
			src.f_style = "Shaved"
			src.update_hair()
	if(prob(1) && prob(100 * RADIATION_SPEED_COEFFICIENT)) //Rare chance of vomiting.
		life_radiation_vomit()

/// Tier 2 (2-6 Gy): burns, cellular damage, sickness.
/mob/living/carbon/human/proc/life_radiation_sickness_moderate()
	if(prob(5))
		src.radiation_burn(5 * RADIATION_SPEED_COEFFICIENT)
	if(prob(1))
		src.injure(INJURY_CELLULAR, 5 * RADIATION_SPEED_COEFFICIENT)
		src.emote("gasp")
	if(prob(5) && prob(100 * RADIATION_SPEED_COEFFICIENT))
		life_radiation_vomit()
	if(prob(10) && !src.has_status(STAT_WEAKENED))
		to_chat(src, span_warning("You feel sick."))
		src.status_adjust(STAT_WEAKENED, 3)

/// Tier 3 (6-8 Gy): heavier burns; organ damage begins.
/mob/living/carbon/human/proc/life_radiation_sickness_severe(damage, rad_mod)
	if(prob(15))
		src.radiation_burn(10 * RADIATION_SPEED_COEFFICIENT)
	if(prob(2))
		src.injure(INJURY_CELLULAR, 5 * RADIATION_SPEED_COEFFICIENT)
		src.emote("gasp")
	if(prob(10) && prob(100 * RADIATION_SPEED_COEFFICIENT))
		life_radiation_vomit()
	if(prob(15) && !src.has_status(STAT_WEAKENED))
		to_chat(src, span_warning("You feel horribly ill."))
		src.status_adjust(STAT_WEAKENED, 3)
	if(prob(5))
		life_radiation_organ_mutation(damage, rad_mod, 40)

/// Tier 4 (8-30 Gy): eye burns, pain, frequent organ damage.
/mob/living/carbon/human/proc/life_radiation_sickness_critical(damage, rad_mod)
	if(prob(25))
		src.radiation_burn(15 * RADIATION_SPEED_COEFFICIENT)
		if(prob(5) && life_radiation_irradiate_organ(damage * rad_mod * RADIATION_SPEED_COEFFICIENT, "Radiation Burns", O_EYES))
			to_chat(src, span_warning("Your eyes burn!"))
			src.status_adjust(STAT_BLURRY, 10)
	if(prob(4))
		src.injure(INJURY_CELLULAR, 5 * RADIATION_SPEED_COEFFICIENT)
		src.emote("gasp")
	if(prob(25) && prob(100 * RADIATION_SPEED_COEFFICIENT))
		life_radiation_vomit()
	if(prob(20) && !src.has_status(STAT_WEAKENED))
		to_chat(src, span_critical("You feel like your insides are burning!"))
		src.status_adjust(STAT_WEAKENED, 5)
	if(prob(5))
		to_chat(src, span_critical("Your entire body feels like it's on fire!"))
		src.injure(INJURY_PAIN, 5)
	if(prob(10))
		life_radiation_organ_mutation(damage, rad_mod, 60)

/// Tier 5 (above 30 Gy): the body melts down and the CNS fails.
/mob/living/carbon/human/proc/life_radiation_sickness_lethal(damage, rad_mod)
	var/organ_damage = damage * rad_mod * RADIATION_SPEED_COEFFICIENT
	src.radiation_burn(damage * RADIATION_SPEED_COEFFICIENT, INJURE_CONTINUOUS) //3 burn damage a tick as your body melts.
	src.injure(INJURY_CELLULAR, 15 * RADIATION_SPEED_COEFFICIENT, flags = INJURE_CONTINUOUS) //1.5 cellular damage a tick as your cells mutate and break down.
	if(life_radiation_irradiate_organ(organ_damage, "Radiation Burns", O_EYES, INJURE_CONTINUOUS)) //3 eye damage a tick as your eyes melt down.
		src.status_adjust(STAT_BLURRY, 10)
	if(prob(50) && prob(100 * RADIATION_SPEED_COEFFICIENT))
		life_radiation_vomit()
	if(!src.has_status(STAT_PARALYZED) && prob(30) && prob(100 * RADIATION_SPEED_COEFFICIENT)) //CNS is shutting down.
		life_radiation_seizure()
	if(src.get_active_hand() && prob(15)) //CNS is shutting down.
		to_chat(src, span_danger("Your hand won't respond properly, you drop what you're holding!"))
		src.drop_item()
	life_radiation_irradiate_organ(organ_damage, "Radiation Induced Cancerous Growth")

/// Long-term (accumulated) radiation effects: annoying, not lethal, a nudge toward medical.
/// Loss of taste at 100 (2 Gy) is handled in taste.dm. Effects stack by threshold. Only
/// organic bodies have them, and never while a live dose is still being taken.
/mob/living/carbon/human/proc/life_radiation_chronic_radiation()
	if(src.radiation || src.accumulated_rads < 100 || src.reagents.has_reagent(REAGENT_ID_PRUSSIANBLUE))
		return
	if(!(src.biology() & BIOLOGY_ORGANIC))
		return
	var/rads = src.accumulated_rads
	if(src.organ_in(O_EYES))
		if(prob(5) && prob(rads * RADIATION_SPEED_COEFFICIENT))
			to_chat(src, span_warning("Your eyes water."))
			src.status_adjust(STAT_BLURRY, 5)
		if(rads > 300 && prob(2) && prob(rads * RADIATION_SPEED_COEFFICIENT)) // (6Gy)
			to_chat(src, span_warning("Your eyes burn."))
			//0.1 damage. Not a lot, but enough to tell you to get to medical.
			life_radiation_irradiate_organ(1 * src.species.radiation_mod * RADIATION_SPEED_COEFFICIENT, "Radiation Burns", O_EYES)
			src.status_adjust(STAT_BLURRY, 10)
	if(rads > 200) // (4Gy)
		if(prob(5) && prob(rads * RADIATION_SPEED_COEFFICIENT))
			to_chat(src, span_warning("Your feel nauseated."))
			life_radiation_vomit()
		if(!src.has_status(STAT_WEAKENED) && prob(2) && prob(rads * RADIATION_SPEED_COEFFICIENT))
			to_chat(src, span_warning("Your feel exhausted."))
			src.status_adjust(STAT_WEAKENED, 3)
	if(rads > 300 && src.get_active_hand() && prob(15) && prob(100 * RADIATION_SPEED_COEFFICIENT)) // (6Gy) CNS is shutting down.
		to_chat(src, span_danger("Your hand won't respond properly, you drop what you're holding!"))
		src.drop_item()
	if(rads > 700 && !src.has_status(STAT_PARALYZED) && prob(1) && prob(100 * RADIATION_SPEED_COEFFICIENT)) // (12Gy) 1 in 1000 chance per tick.
		life_radiation_seizure()

	/** breathing **/

/mob/living/carbon/human/life_breathing_inhale_smoke(datum/gas_mixture/environment)
	if(src.get_equipped_item(SLOT_ID_MASK) && (src.get_equipped_item(SLOT_ID_MASK).item_flags & BLOCK_GAS_SMOKE_EFFECT))
		return
	if(src.get_equipped_item(SLOT_ID_EYES) && (src.get_equipped_item(SLOT_ID_EYES).item_flags & BLOCK_GAS_SMOKE_EFFECT))
		return
	if(src.get_equipped_item(SLOT_ID_HEAD) && (src.get_equipped_item(SLOT_ID_HEAD).item_flags & BLOCK_GAS_SMOKE_EFFECT))
		return
	..()

/mob/living/carbon/human/get_breath_from_internal(volume_needed=BREATH_VOLUME)
	if(internal)
		//Because rigs store their tanks out of reach of contents.Find(), a check has to be made to make
		//sure the rig is still worn, still online, and that its air supply still exists.
		var/obj/item/tank/suit_supply
		var/obj/item/rig/Rig = get_rig()
		var/obj/item/clothing/suit/space/void/Void = get_voidsuit()

		if(Rig)
			suit_supply = Rig.air_supply
		else if(Void)
			suit_supply = Void.tank

		if ((!suit_supply && !contents.Find(internal)) || !((get_equipped_item(SLOT_ID_MASK) && (get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT)) || (get_equipped_item(SLOT_ID_HEAD) && (get_equipped_item(SLOT_ID_HEAD).item_flags & AIRTIGHT))))
			rel_clear(src, nameof(internal))

		if(internal)
			return internal.remove_air_volume(volume_needed)
		else if(internals)
			internals.icon_state = "internal0"
	return null


/// One lung breath's gas exchange (P2-F1: split into the steps below). Reports the breath's
/// quality (0..1) to the physiology, which decides whether the body suffocates.
/mob/living/carbon/human/life_breathing_exchange(datum/gas_mixture/breath)
	if(in_godmode(src))
		return 0	// Cancelled by a component

	if(src.suiciding)
		// Holding the breath: nothing is drawn in.
		src.failed_last_breath = 1
		src.body?.set_breath_quality(0)
		src.suiciding--
		return 0

	if(src.get_equipped_item(SLOT_ID_MASK) && (src.get_equipped_item(SLOT_ID_MASK).item_flags & INFINITE_AIR))
		src.failed_last_breath = 0
		src.body?.set_breath_quality(1)
		return

	// XGM .total_moles var → LINDA proc. Cache to avoid 12 proc calls.
	var/breath_moles = breath ? breath.total_moles() : 0
	if(!breath_moles)
		// Nothing to breathe: a closed airway, apnea, or vacuum.
		src.failed_last_breath = 1
		src.body?.set_breath_quality(0)
		src.throw_alert("oxy", /atom/movable/screen/alert/not_enough_atmos)
		return 0
	src.clear_alert("oxy")

	var/breath_pressure = (breath_moles*R_IDEAL_GAS_EQUATION*breath.return_temperature())/BREATH_VOLUME

	// Each step returns a quality multiplier; below 1 means that part of the breath failed.
	var/inhale_quality = life_breathing_inhale_breath_gas(breath, breath_moles, breath_pressure)
	var/exhale_quality = life_breathing_exhaled_gas_buildup(breath, breath_moles, breath_pressure)
	var/quality = inhale_quality * exhale_quality * life_breathing_methane_displacement(breath, breath_moles, breath_pressure)
	src.breathe_poison(breath, src.species.poison_type || GAS_PHORON, breath_moles, breath_pressure)
	src.breathe_sleeping_gas(breath, breath_moles, breath_pressure)
	life_breathing_hallucinated_breath_alerts()

	// Were we able to breathe?
	var/failed_inhale = inhale_quality < 1
	var/failed_exhale = exhale_quality < 1
	src.failed_last_breath = (failed_inhale || failed_exhale) ? 1 : 0
	src.body?.set_breath_quality(quality)

	life_breathing_suit_breath_sounds(failed_inhale, failed_exhale)
	life_breathing_breath_temperature_effects(breath, breath_moles)
	return 1

/// The species' breath gas. Too little: the breath is only as good as its share (and a vacuum
/// pops the lungs). Uses up a sixth of it. Returns the quality multiplier.
/mob/living/carbon/human/proc/life_breathing_inhale_breath_gas(datum/gas_mixture/breath, breath_moles, breath_pressure)
	// Minimum safe partial pressure of breathable gas in kPa. Lung damage is
	// the physiology's business (gas exchange), not the air's.
	var/safe_pressure_min = src.species.minimum_breath_pressure
	var/breath_type = src.species.breath_type || GAS_O2
	var/inhaling = LINDA_GAS_AMT(breath, breath_type)
	var/inhale_pp = (inhaling/breath_moles)*breath_pressure
	. = 1
	if(inhale_pp < safe_pressure_min)
		if(prob(20))
			src.emote("gasp")
		if(is_below_sound_pressure(get_turf(src)))	//No more popped lungs from choking/drowning. You also have ~20 seconds to get internals on before your lungs pop.
			src.rupture_lung(TRUE)
		// Too little of the breath gas: the breath is only as good as its share.
		. = safe_pressure_min > 0 ? clamp(inhale_pp / safe_pressure_min, 0, 1) : 0
		var/static/list/low_breath_alerts = list(
			GAS_O2 = /atom/movable/screen/alert/not_enough_oxy,
			GAS_PHORON = /atom/movable/screen/alert/not_enough_tox,
			GAS_N2 = /atom/movable/screen/alert/not_enough_nitro,
			GAS_CO2 = /atom/movable/screen/alert/not_enough_co2,
			GAS_CH4 = /atom/movable/screen/alert/not_enough_methane,
			GAS_VOLATILE_FUEL = /atom/movable/screen/alert/not_enough_fuel,
			GAS_N2O = /atom/movable/screen/alert/not_enough_n2o,
		)
		var/alert_type = low_breath_alerts[breath_type]
		if(alert_type)
			src.throw_alert("oxy", alert_type)
	else
		src.clear_alert("oxy")

	var/inhaled_gas_used = inhaling/6
	breath.adjust_gas(breath_type, -inhaled_gas_used, update = 0) //update afterwards
	if(src.species.exhale_type)
		breath.adjust_gas_temp(src.species.exhale_type, inhaled_gas_used, src.body_temperature(), update = 0) //update afterwards

/// Too much of the species' exhale gas in the air: hypercapnia crowds out the breath.
/// Returns the quality multiplier.
/mob/living/carbon/human/proc/life_breathing_exhaled_gas_buildup(datum/gas_mixture/breath, breath_moles, breath_pressure)
	. = 1
	var/exhale_type = src.species.exhale_type
	if(!exhale_type)
		return
	var/safe_exhaled_max = 10
	// To be clear, this isn't how much they're exhaling -- it's the amount of the species exhale gas in the breath.
	var/exhaled_pp = (LINDA_GAS_AMT(breath, exhale_type)/breath_moles)*breath_pressure
	if(exhaled_pp > safe_exhaled_max)
		if (prob(15))
			var/word = pick("extremely dizzy","short of breath","faint","confused")
			to_chat(src, span_danger("You feel [word]."))
		// Hypercapnia: the exhaled gas crowds out the breath.
		return 0.4
	if(exhaled_pp > safe_exhaled_max * 0.7)
		if (!prob(1))
			var/word = pick("dizzy","short of breath","faint","momentarily confused")
			to_chat(src, span_warning("You feel [word]."))
		//scale linearly from 0 to 1 between safe_exhaled_max and safe_exhaled_max*0.7
		var/ratio = 1.0 - (safe_exhaled_max - exhaled_pp)/(safe_exhaled_max*0.3)
		// Mild hypercapnia: the breath worsens as the exhaled gas nears its limit.
		return 1 - 0.5 * ratio
	if(exhaled_pp > safe_exhaled_max * 0.6)
		if(prob(0.3))
			var/word = pick("a little dizzy","short of breath")
			to_chat(src, span_warning("You feel [word]."))

/// Methane displaces the breath (unless the species breathes it): slow suffocation.
/// Returns the quality multiplier.
/mob/living/carbon/human/proc/life_breathing_methane_displacement(datum/gas_mixture/breath, breath_moles, breath_pressure)
	. = 1
	if(src.species.breath_type == GAS_CH4)
		return
	var/safe_toxins_min = 0.05
	var/safe_toxins_max = 0.2
	var/poison_methane = LINDA_GAS_AMT(breath, GAS_CH4)
	var/methane_pp = (poison_methane/breath_moles)*breath_pressure
	if(methane_pp > safe_toxins_min && prob(5))
		to_chat(src,span_warning("You smell rotten eggs."))
	if(methane_pp > safe_toxins_max)
		. = 1 - clamp(methane_pp / (safe_toxins_max * 20), 0.1, 0.8)
		if(prob(20))
			src.emote("gasp")
		breath.adjust_gas(GAS_CH4, -poison_methane/6, update = 0) // update after
		src.throw_alert("methane_in_air", /atom/movable/screen/alert/methane_in_air)
	else
		src.clear_alert("methane_in_air")

/mob/living/carbon/human/proc/life_breathing_hallucinated_breath_alerts()
	var/hud_state = src.get_hallucination_state()?.get_hud_state()
	if(hud_state == HUD_HALLUCINATION_OXY)
		src.throw_alert("oxy", /atom/movable/screen/alert/not_enough_atmos)
	else if(hud_state == HUD_HALLUCINATION_TOXIN)
		src.throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)

/// Suit breathing sounds for organic lungs on internals below audible pressure.
/mob/living/carbon/human/proc/life_breathing_suit_breath_sounds(failed_inhale, failed_exhale)
	if(!src.client || !src.internal)
		return
	var/obj/item/organ/internal/lungs/L = src.organ_in(O_LUNGS)
	if(!L || L.is_robotic() || !is_below_sound_pressure(get_turf(src)))
		return
	if(!failed_inhale && COOLDOWN_FINISHED(src, breath_sound_cooldown)) // Were we able to inhale successfully? Play inhale.
		src.play_inhale(src, failed_exhale) // Pass through if we passed exhale or not
		COOLDOWN_START(src, breath_sound_cooldown, 7 SECONDS)

/// Hot or cold breath: burns or frostbite to the airway, temperature alerts, and a little body heat exchange.
/mob/living/carbon/human/proc/life_breathing_breath_temperature_effects(datum/gas_mixture/breath, breath_moles)
	if(isbelly(src.loc)) //None of this happens anyway whilst inside of a belly, belly temperatures are all handled as body temperature
		return
	var/datum/species/S = src.species
	var/breath_temperature = breath.return_temperature()
	if(!(breath_temperature <= S.cold_discomfort_level || breath_temperature >= S.heat_discomfort_level) || src.has_mutation(COLD_RESISTANCE))
		src.clear_alert("temp")
		return

	if(breath_temperature <= S.breath_cold_level_1)
		if(prob(20))
			to_chat(src, span_danger("You feel your face freezing and icicles forming in your lungs!"))
	else if(breath_temperature >= S.breath_heat_level_1)
		if(prob(20))
			to_chat(src, span_danger("You feel your face burning and a searing heat in your lungs!"))

	if(breath_temperature >= S.heat_discomfort_level)
		if(breath_temperature >= S.breath_heat_level_3)
			src.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_3, BP_HEAD)
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
		else if(breath_temperature >= S.breath_heat_level_2)
			src.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_2, BP_HEAD)
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MODERATE)
		else if(breath_temperature >= S.breath_heat_level_1)
			src.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_1, BP_HEAD)
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_LOW)
		else if(S.get_environment_discomfort(src, ENVIRONMENT_COMFORT_MARKER_HOT))
			src.throw_alert("temp", /atom/movable/screen/alert/warm, HOT_ALERT_SEVERITY_LOW)
		else
			src.clear_alert("temp")
	else
		if(breath_temperature <= S.breath_cold_level_3)
			src.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_3, BP_HEAD)
			src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
		else if(breath_temperature <= S.breath_cold_level_2)
			src.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_2, BP_HEAD)
			src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MODERATE)
		else if(breath_temperature <= S.breath_cold_level_1)
			src.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_1, BP_HEAD)
			src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_LOW)
		else if(S.get_environment_discomfort(src, ENVIRONMENT_COMFORT_MARKER_COLD))
			src.throw_alert("temp", /atom/movable/screen/alert/chilly, COLD_ALERT_SEVERITY_LOW)
		else
			src.clear_alert("temp")

	//breathing in hot/cold air also heats/cools you a bit
	var/temp_adj = breath_temperature - src.body_temperature()
	if (temp_adj < 0)
		temp_adj /= (BODYTEMP_COLD_DIVISOR * 5)	//don't raise temperature as much as if we were directly exposed
	else
		temp_adj /= (BODYTEMP_HEAT_DIVISOR * 5)	//don't raise temperature as much as if we were directly exposed
	temp_adj *= breath_moles / (MOLES_CELLSTANDARD * BREATH_PERCENTAGE)
	src.adjust_bodytemperature(clamp(temp_adj, BODYTEMP_COOLING_MAX, BODYTEMP_HEATING_MAX))

/mob/living/carbon/human/proc/play_inhale(mob/living/M, exhale)
	var/suit_inhale_sound
	if(species.suit_inhale_sound)
		suit_inhale_sound = species.suit_inhale_sound
	else // Failsafe
		suit_inhale_sound = SFX_EFFECTS_MOB_EFFECTS_SUIT_BREATHE_IN

	playsound_local(get_turf(src), suit_inhale_sound, 100, pressure_affected = FALSE, volume_channel = VOLUME_CHANNEL_AMBIENCE)
	if(!exhale) // Did we fail exhale? If no, play it after inhale finishes.
		after(src, 5 SECONDS, PROC_REF(play_exhale), with = list(M))

/mob/living/carbon/human/proc/play_exhale(mob/living/M)
	var/suit_exhale_sound
	if(species.suit_exhale_sound)
		suit_exhale_sound = species.suit_exhale_sound
	else // Failsafe
		suit_exhale_sound = SFX_EFFECTS_MOB_EFFECTS_SUIT_BREATHE_OUT

	playsound_local(get_turf(src), suit_exhale_sound, 100, pressure_affected = FALSE, volume_channel = VOLUME_CHANNEL_AMBIENCE)

/// Species components (xenochimera, shadekin). Not stat checked: those check in their own code.
/mob/living/carbon/human/proc/life_species_components(datum/seq_frame/life/F)
	//Xenochimera Species Component
	var/datum/xenochimera/xc = src.xenochimera
	if(xc)
		if(!src.stat || !(xc.revive_ready == REVIVING_NOW || xc.revive_ready == REVIVING_DONE))
			xc.handle_comp()

	//Shadekin Species Component.
	var/datum/shadekin/sk = src.shadekin
	if(sk)
		if(!src.stat)
			sk.handle_comp()

/mob/living/carbon/human
	/// TRUE when the last environment exchange found comfortable air (its idle rule).
	var/environment_steady = FALSE

/// Idle after an exchange that found comfortable air on a turf (the pressure inside the warning
/// band, the air within 20 K of the body, the body inside its comfort band). Only the mob's own
/// state is read, so the air is re-sampled by the rewake; moving and equipment wake it sooner.
/// Species and traits with their own environment effects stay awake.
/mob/living/carbon/human/life_environment_due()
	var/static/list/active_environment_species = typecacheof(list(
		/datum/species/grey,
		/datum/species/spider,
		/datum/species/xenochimera,
		/datum/species/xenomorph_hybrid,
		/datum/species/xenos,
	))
	if(!src.environment_steady || !isturf(src.loc) || src.alerts?["pressure"])
		return TRUE
	if(LAZYLEN(src.species.env_traits) || is_type_in_typecache(src.species, active_environment_species))
		return TRUE
	return src.body_temperature() >= src.species.heat_level_1 || src.body_temperature() <= src.species.cold_level_1

/mob/living/carbon/human/life_environment_rewake()
	return ENVIRONMENT_STEADY_RESAMPLE

/// P2-F1: body vs environment, split into heat exchange, temperature harm and pressure harm.
/mob/living/carbon/human/life_environment_exchange(datum/gas_mixture/environment)
	src.environment_steady = FALSE
	if(!environment)
		return

	if(src.is_incorporeal()) //Not in this plane of existance right now, tbh.
		return

	//Stuff like the xenomorph's plasma regen happens here.
	src.species.environment_effects(src)

	//Moved pressure calculations here for use in skip-processing check.
	var/pressure = environment.return_pressure()
	var/adjusted_pressure = src.calculate_affecting_pressure(pressure)

	if(istype(src.loc, /turf/space)) //No FBPs overheating on space turfs inside mechs or people.
		src.set_surroundings(0, 0, life_environment_sky_area(TCMB))
	else
		var/loc_temp = life_environment_location_temperature(environment)
		if(adjusted_pressure < src.species.warning_high_pressure && adjusted_pressure > src.species.warning_low_pressure && abs(loc_temp - src.body_temperature()) < 20 && src.body_temperature() < src.species.heat_level_1 && src.body_temperature() > src.species.cold_level_1 && (!isbelly(src.loc) || !src.allowtemp))
			src.clear_alert("pressure")
			src.environment_steady = TRUE
			src.set_surroundings(0, 0) // inside its comfort range the body trades no heat with the room (intended_changes.md)
			return // Temperatures are within normal ranges, fuck all this processing. ~Ccomp
		life_environment_convect(loc_temp, environment)

	var/godmode = in_godmode(src)
	if(isbelly(src.loc) && src.allowtemp)
		life_environment_belly_temperature_harm()
	else if(!godmode) // Cancelled by a component
		life_environment_body_temperature_harm()
	if(godmode)
		return
	life_environment_pressure_harm(adjusted_pressure)

/// The area the body radiates to the sky through what it wears, m²: its exposed surface less its protection against `sky` K.
/mob/living/carbon/human/proc/life_environment_sky_area(sky)
	return HUMAN_EXPOSED_SURFACE_AREA * (1 - src.get_cold_protection(sky))

/// The temperature the body is exposed to where it is (mech cabin, cryo cell, belly or the air).
/mob/living/carbon/human/proc/life_environment_location_temperature(datum/gas_mixture/environment)
	if(istype(src.loc, /obj/mecha))
		var/obj/mecha/M = src.loc
		return M.get_interior_temperature()
	if(istype(src.loc, /obj/machinery/atmospherics/unary/cryo_cell))
		var/obj/machinery/atmospherics/unary/cryo_cell/cc = src.loc
		return cc.air_contents.return_temperature()
	if(isbelly(src.loc))
		var/obj/belly/b = src.loc
		if(src.allowtemp)
			return b.bellytemperature
		// The predator's body temperature, kept within this prey's comfort: harmless unless they opted into temperature play.
		return clamp(b.get_interior_temperature(), src.species.cold_discomfort_level, src.species.heat_discomfort_level)
	if(isturf(src.loc))
		return life_environment_plume_temperature(src.loc, environment)
	return environment.return_temperature()

/// The air temperature the body's convection meets on a turf: its tile's and the open neighbours' mean, the plume it exchanges with.
/mob/living/carbon/human/proc/life_environment_plume_temperature(turf/T, datum/gas_mixture/environment)
	var/total = environment.return_temperature()
	var/count = 1
	for(var/turf/N as anything in vg_atmos_adjacent_turfs(T))
		if(N.z != T.z || !N.heat_has_air())
			continue
		var/datum/gas_mixture/air = N.return_air()
		if(air?.total_moles() > 0)
			total += air.return_temperature()
			count++
	return total / count

/// Body temperature follows the surroundings through clothing: convection to the air around it (at the old rate, BODYTEMP_*_DIVISOR of the
/// gap per Life frame, scaled by the air's density), contact with the floor and the walls beside it, and radiation to the sky in near vacuum.
/// Rust moves the heat both ways and conserves it.
/mob/living/carbon/human/proc/life_environment_convect(loc_temp, datum/gas_mixture/environment)
	var/body = src.body_temperature()
	var/thermal_protection = loc_temp < body ? src.get_cold_protection(loc_temp) : src.get_heat_protection(loc_temp)
	var/relative_density = environment.total_moles() / MOLES_CELLSTANDARD
	var/sky = (isturf(src.loc) && relative_density < BODY_SKY_DENSITY) ? life_environment_sky_area(TCMB) : 0
	if(thermal_protection >= 0.99)
		src.set_surroundings(0, 0, sky)
		return
	var/divisor = loc_temp < body ? BODYTEMP_COLD_DIVISOR : BODYTEMP_HEAT_DIVISOR
	var/air = src.body_heat_capacity() * (1 - thermal_protection) * relative_density / (divisor * LIFE_ENVIRONMENT_SECONDS)
	var/surface = isturf(src.loc) ? BODY_FLOOR_CONDUCTANCE * (1 - thermal_protection) : 0
	src.set_surroundings(air, surface, sky)

/// Temperature play in a belly (the prey opted in): the belly's temperature against the species' levels.
/mob/living/carbon/human/proc/life_environment_belly_temperature_harm()
	var/obj/belly/b = src.loc
	var/datum/species/S = src.species
	var/belly_temp = b.bellytemperature
	if(belly_temp >= S.heat_discomfort_level) //A bit more easily triggered than normal, intentionally
		var/heat_dam = 0
		if(belly_temp >= S.heat_level_3)
			heat_dam = HEAT_DAMAGE_LEVEL_3
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
		else if(belly_temp >= S.heat_level_2)
			heat_dam = HEAT_DAMAGE_LEVEL_2
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MODERATE)
		else if(belly_temp >= S.heat_level_1)
			heat_dam = HEAT_DAMAGE_LEVEL_1
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_LOW)
		else
			src.throw_alert("temp", /atom/movable/screen/alert/warm, HOT_ALERT_SEVERITY_LOW)
		if(src.digestable && b.temperature_damage)
			src.injure(INJURY_BURN, heat_dam, flags = INJURE_CONTINUOUS) // High body temperature
	else if(belly_temp <= S.cold_discomfort_level)
		var/cold_dam = 0
		if(belly_temp <= S.cold_level_3)
			cold_dam = COLD_DAMAGE_LEVEL_3
			src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
		else if(belly_temp <= S.cold_level_2)
			cold_dam = COLD_DAMAGE_LEVEL_2
			src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MODERATE)
		else if(belly_temp <= S.cold_level_1)
			cold_dam = COLD_DAMAGE_LEVEL_1
			src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_LOW)
		else
			src.throw_alert("temp", /atom/movable/screen/alert/chilly, COLD_ALERT_SEVERITY_LOW)
		if(src.digestable && b.temperature_damage)
			src.injure(INJURY_FROSTBITE, cold_dam, flags = INJURE_CONTINUOUS) // Low body temperature
	else
		src.clear_alert("temp")

/// Body temperature outside the species' comfort band burns or freezes. +/- 50 degrees from
/// 310.15K is the 'safe' zone, where no damage is dealt.
/mob/living/carbon/human/proc/life_environment_body_temperature_harm()
	var/datum/species/S = src.species
	var/body_temp = src.body_temperature()
	if(body_temp >= S.heat_discomfort_level)
		var/heat_dam = 0
		if(body_temp >= S.heat_level_3)
			heat_dam = HEAT_DAMAGE_LEVEL_3
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
		else if(body_temp >= S.heat_level_2)
			heat_dam = HEAT_DAMAGE_LEVEL_2
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MODERATE)
		else if(body_temp >= S.heat_level_1)
			heat_dam = HEAT_DAMAGE_LEVEL_1
			src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_LOW)
		src.injure(INJURY_BURN, heat_dam, flags = INJURE_CONTINUOUS) // High body temperature
	else if(body_temp <= S.cold_discomfort_level)
		if(istype(src.loc, /obj/machinery/atmospherics/unary/cryo_cell))
			return
		var/cold_dam = 0
		if(body_temp <= S.cold_level_3)
			cold_dam = COLD_DAMAGE_LEVEL_3
		else if(body_temp <= S.cold_level_2)
			cold_dam = COLD_DAMAGE_LEVEL_2
		else if(body_temp <= S.cold_level_1)
			cold_dam = COLD_DAMAGE_LEVEL_1
		src.injure(INJURY_FROSTBITE, cold_dam, flags = INJURE_CONTINUOUS) // Low body temperature
	else
		src.clear_alert("temp")

/// Crushing or decompressing pressure. Made it possible to actually have something that can
/// protect against high pressure... Done by Errorage.
/mob/living/carbon/human/proc/life_environment_pressure_harm(adjusted_pressure)
	var/datum/species/S = src.species
	if(adjusted_pressure >= S.hazard_high_pressure)
		var/pressure_damage = min( ( (adjusted_pressure / S.hazard_high_pressure) -1 )*PRESSURE_DAMAGE_COEFFICIENT , MAX_HIGH_PRESSURE_DAMAGE)
		if(src.stat == DEAD)
			pressure_damage = pressure_damage/2
		if(!istype(src.loc, /obj/structure/closet/body_bag/cryobag))
			src.injure(INJURY_BLUNT, pressure_damage, flags = INJURE_CONTINUOUS) // Crushing pressure
		src.throw_alert("pressure", /atom/movable/screen/alert/highpressure, 2)
	else if(adjusted_pressure >= S.warning_high_pressure)
		src.throw_alert("pressure", /atom/movable/screen/alert/highpressure, 1)
	else if(adjusted_pressure >= S.warning_low_pressure)
		src.clear_alert("pressure")
	else if(adjusted_pressure >= S.hazard_low_pressure)
		src.throw_alert("pressure", /atom/movable/screen/alert/lowpressure, 1)
	else if(src.has_mutation(COLD_RESISTANCE) || istype(src.loc, /obj/structure/closet/body_bag/cryobag))
		src.clear_alert("pressure")
	else
		life_environment_decompression(adjusted_pressure)
		src.throw_alert("pressure", /atom/movable/screen/alert/lowpressure, 2)

/// Hazardously low pressure: ruptured capillaries, and ebullition in the lungs. A NIF pressure
/// seal protects a synthetic body.
/mob/living/carbon/human/proc/life_environment_decompression(adjusted_pressure)
	if(HAS_SYNTHETIC_BIOLOGY(src) && src.nif?.flag_check(NIF_O_PRESSURESEAL, NIF_FLAGS_OTHER))
		return
	var/pressure_damage = LOW_PRESSURE_DAMAGE
	if(src.stat==DEAD)
		pressure_damage = pressure_damage/2
	src.injure(INJURY_BLUNT, pressure_damage, flags = INJURE_CONTINUOUS) // Decompression: ruptured capillaries and tissue
	// Ebullition in the lungs: gas exchange fails even on internals,
	// less the better the suit holds pressure.
	var/exposure = (ONE_ATMOSPHERE - adjusted_pressure) / ONE_ATMOSPHERE
	var/obj/item/suit = src.get_equipped_item(SLOT_ID_SUIT)
	var/obj/item/helmet = src.get_equipped_item(SLOT_ID_HEAD)
	if(suit?.min_pressure_protection && helmet?.min_pressure_protection)
		exposure *= max(suit.min_pressure_protection, helmet.min_pressure_protection) / ONE_ATMOSPHERE
	src.body?.add_restriction(src, BF_GAS_EXCHANGE, clamp(1 - exposure, 0.1, 1), 4 SECONDS)

/// MED-6: at its set point, with no heat source of its own, the body has nothing to regulate.
/mob/living/carbon/human/proc/life_thermoregulation_due()
	if(src.body?.metabolic_power)
		return TRUE // it runs once more to stop its own power
	if(src.species.passive_temp_gain)
		return TRUE
	if(isnull(src.species.body_temperature))
		return FALSE
	if(src.stat != DEAD && src.robobody_count)
		return TRUE
	return !src.on_fire && abs(src.thermal_setpoint() - src.body_temperature()) >= 0.5

/// C16 / P2-S10: the temperature this body regulates toward — the species norm
/// plus BF_TEMPERATURE (fevers and chills are factors on afflictions, not
/// per-tick temperature writes).
/mob/living/carbon/human/proc/thermal_setpoint()
	return species.body_temperature + factor(BF_TEMPERATURE)

/// Body temperature is written raw by the environment, reagents and afflictions.
/mob/living/carbon/human/proc/life_thermoregulation_rewake()
	return 4 SECONDS

/// Body temperature adjusts itself (self-regulation): metabolism is the body's own power, W, held until the next run (the old per-run
/// temperature steps, as the power that makes them over LIFE_ENVIRONMENT_SECONDS).
/mob/living/carbon/human/proc/life_thermoregulation(datum/seq_frame/life/F)
	var/per_kelvin = src.body_heat_capacity() / LIFE_ENVIRONMENT_SECONDS // W that make one kelvin per run
	var/watts = 0
	// We produce heat naturally.
	if (src.species.passive_temp_gain)
		watts += src.species.passive_temp_gain * per_kelvin
	if (src.species.body_temperature == null)
		src.set_metabolic_power(watts)
		return //this species doesn't have metabolic thermoregulation

	// FBPs will overheat when alive, prosthetic limbs are fine.
	if(src.stat != DEAD && src.robobody_count)
		if(!src.nif || !src.nif.flag_check(NIF_O_HEATSINKS,NIF_FLAGS_OTHER))
			watts += round(src.robobody_count*1.15) * per_kelvin
		var/obj/item/organ/internal/robotic/heatsink/HS = src.organ_in(O_HEATSINK)
		if(!HS || HS.is_broken()) // However, NIF Heatsinks will not compensate for a core FBP component (your heatsink) being lost.
			watts += round(src.robobody_count*0.5) * per_kelvin

	var/body = src.body_temperature()
	var/setpoint = src.thermal_setpoint()
	var/body_temperature_difference = setpoint - body

	if (abs(body_temperature_difference) < 0.5)
		src.set_metabolic_power(watts)
		return //fuck this precision

	// B15: thermoregulating drugs (leporazine) act through their tag, here.
	var/thermo = src.body?.treatment_levels()?[TREAT_THERMOREGULATION]
	if(thermo)
		var/step = min(abs(body_temperature_difference), thermo * DQ_THERMOREG_K_PER_LEVEL)
		watts += (body_temperature_difference > 0 ? step : -step) * per_kelvin
		body_temperature_difference -= body_temperature_difference > 0 ? step : -step
		if (abs(body_temperature_difference) < 0.5)
			src.set_metabolic_power(watts)
			return

	if (src.on_fire)
		src.set_metabolic_power(watts)
		return //too busy for pesky metabolic regulation

	var/recovery_amt = 0
	if(body < src.species.cold_level_1) //260.15 is 310.15 - 50, the temperature where you start to feel effects.
		if(src.nutrition >= 2) //If we are very, very cold we'll use up quite a bit of nutriment to heat us up.
			src.adjust_nutrition(-2)
		recovery_amt = max((body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR), BODYTEMP_AUTORECOVERY_MINIMUM)
	else if(src.species.cold_level_1 <= body && body <= src.species.heat_level_1)
		recovery_amt = body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR
	else if(body > src.species.heat_level_1) //360.15 is 310.15 + 50, the temperature where you start to feel effects.
		//We totally need a sweat system cause it totally makes sense...~
		recovery_amt = min((body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR), -BODYTEMP_AUTORECOVERY_MINIMUM)	//We're dealing with negative numbers
	src.set_metabolic_power(watts + recovery_amt * per_kelvin)

/// Body part flags protected from heat at `temperature` (worn protection cache).
/mob/living/carbon/human/proc/get_heat_protection_flags(temperature)
	return body ? body.worn_heat_flags(temperature) : 0

/// Body part flags protected from cold at `temperature` (worn protection cache).
/mob/living/carbon/human/proc/get_cold_protection_flags(temperature)
	return body ? body.worn_cold_flags(temperature) : 0

/// 0..1 protection from air at `temperature` (1 = immune): the surface share
/// worn layers seal, then BF_HEAT_EXPOSURE, which stacks multiplicatively.
/mob/living/carbon/human/get_heat_protection(temperature)
	var/exposed = 1 - (body ? body.worn_thermal_protection(temperature, FALSE) : 0)
	return min(1 - exposed * factor(BF_HEAT_EXPOSURE), 1)

/mob/living/carbon/human/get_cold_protection(temperature)
	if(has_mutation(COLD_RESISTANCE))
		return 1
	// Space is 2.7 K; low-moles tiles occasionally report less, and cold-rated suits protect to 2 K.
	temperature = max(temperature, 2.7)
	var/exposed = 1 - (body ? body.worn_thermal_protection(temperature, TRUE) : 0)
	return min(1 - exposed * factor(BF_COLD_EXPOSURE), 1)

/mob/living/carbon/human/life_chemicals(datum/seq_frame/life/F)
	if(src.reagents)
		if(src.touching)
			src.touching.metabolize()
		if(src.ingested)
			src.ingested.metabolize()
		if(src.bloodstr)
			src.bloodstr.metabolize()

		// ZAS-era phoron-contamination damage path removed. It read
		// `I.contaminated` (which has no setter under LINDA) and
		// `GLOB.vsc.plc.CONTAMINATION_LOSS` (config holder that's also gone).
		// Whole branch was inert; restore properly if/when contamination
		// machinery is rebuilt on the LINDA gas model.

	if(in_godmode(src))
		return 0	// Cancelled by a component

	// nutrition decrease, for the biological time since the last one (the stage idles between
	// reagents and comes back on its rewake to catch up). Species controls hunger rate for humans.
	var/bio_now = om_clock_now(src, CLOCK_BIO)
	var/hunger_cycles = src.nutrition_drained_at ? clamp((bio_now - src.nutrition_drained_at) / LIFE_CYCLE, 0, NUTRITION_CATCHUP_CYCLES) : 1
	src.nutrition_drained_at = bio_now
	if(src.nutrition > 0 && src.stat != DEAD)
		var/nutrition_reduction = src.species.hunger_factor * hunger_cycles
		// Metabolism above or below the species' own (hunger_factor already
		// covers the species) raises or lowers nutrition cost.
		var/species_metabolism = src.species.baseline_factor(BF_METABOLISM)
		if(species_metabolism > 0)
			nutrition_reduction *= src.factor(BF_METABOLISM) / species_metabolism
		var/datum/trait_state/nutrition_size_change/comp = src.get_trait_state(/datum/trait_state/nutrition_size_change)
		if(comp)
			nutrition_reduction *= comp.get_nutrition_multiplier()
		src.adjust_nutrition(-nutrition_reduction)

	if(src.noisy == TRUE && src.nutrition < 250 && prob(10))
		var/sound/growlsound = sound(get_sfx(SFX_HUNGER_SOUNDS))
		var/growlmultiplier = 100 - (src.nutrition / 250 * 100)
		playsound(src, growlsound, vol = growlmultiplier, vary = 1, falloff = 0.1, ignore_walls = TRUE, preference = /datum/preference/toggle/digestion_noises)
	if(src.nutrition > 500 && src.noisy_full == TRUE)
		var/belch_prob = 5 //Maximum belch prob.
		if(src.nutrition < 4075)
			belch_prob = ((src.nutrition-500)/3575)*5 //Scale belch prob with fullness if not already at max. If editing make sure the multiplier matches the max prob above.
		if(prob(belch_prob))
			src.emote("belch")
	if(src.factor(BF_DARKSIGHT) && src.chemical_darksight == 0)
		src.recalculate_vis()
		src.chemical_darksight = 1
	if(!src.factor(BF_DARKSIGHT) && src.chemical_darksight == 1)
		src.recalculate_vis()
		src.chemical_darksight = 0

	// TODO: stomach and bloodstream organ.
	if(!HAS_SYNTHETIC_BIOLOGY(src))
		src.handle_trace_chems()

	return

/mob/living/carbon/human
	/// Biological time (om_clock_now(CLOCK_BIO), ds) of the last nutrition drain.
	var/nutrition_drained_at = 0

/// Idle with nothing to metabolise and no digestion noises due; reagent changes invalidate the
/// body (CHANGE_MOB_HEALTH). Hunger is integrated over the idle time on the rewake.
/mob/living/carbon/human/life_chemicals_due()
	if(src.touching?.total_volume || src.ingested?.total_volume || src.bloodstr?.total_volume)
		return TRUE
	if(!src.factor(BF_DARKSIGHT) != !src.chemical_darksight)
		return TRUE
	if((src.noisy && src.nutrition < 250) || (src.noisy_full && src.nutrition > 500))
		return TRUE
	return FALSE

/mob/living/carbon/human/life_chemicals_rewake()
	return src.stat == DEAD ? 0 : NUTRITION_RESAMPLE

//DO NOT run the statuses system from this proc: it runs after this one as long as this returns a true value.
/// A24: the dead have nothing to update; the living idle while nothing in update_status() has
/// work: conscious, no afflictions or pain, no status it tops up, senses intact, no fear or
/// tiredness counting down.
/mob/living/carbon/human/life_status_due()
	if(src.stat == DEAD)
		return FALSE
	if(src.stat != CONSCIOUS || has_trait(src, TRAIT_CRITICAL_CONDITION))
		return TRUE
	var/datum/body/B = src.body
	if(!B || LAZYLEN(B.afflictions) || B.dirty || src.current_pain() || src.oxygen_debt() || src.is_critical())
		return TRUE
	// blinded is reset every frame (type_pre) and set again here, so anything that blinds keeps it awake.
	if(src.tiredness || src.fear || src.embedded_flag || src.resting || src.wearing_blindfold() || life_status_rig_visor_blinds())
		return TRUE
	if(src.has_status(STAT_SLEEPING) || src.has_status(STAT_DROWSY) || src.has_status(STAT_HALLUCINATING) || src.has_status(STAT_BLINDED) || src.has_status(STAT_DEAFENED))
		return TRUE
	if((src.sdisabilities & (BLIND | DEAF)) || src.ear_damage)
		return TRUE
	if(src.species.get_ssd(src) && !src.client && !src.teleop)
		return TRUE
	if(src.species.vision_organ)
		var/obj/item/organ/vision = src.organ_in(src.species.vision_organ)
		if(!vision || vision.is_bruised())
			return TRUE
	return FALSE

/// Raw fear / tiredness writes and slow drift are caught by the rewake.
/mob/living/carbon/human/life_status_rewake()
	return src.stat == DEAD ? 0 : 5 SECONDS

/// P2-F1: the status update, split into one proc per concern below.
/mob/living/carbon/human/life_status_update_status()
	if(in_godmode(src))
		return 0	// Cancelled by a component

	//SSD check, if a logged player is awake put them back to sleep!
	if(src.species.get_ssd(src) && !src.client && !src.teleop)
		src.status_at_least(STAT_SLEEPING, 2)
	if(src.stat == DEAD)	//DEAD. BROWN BREAD. SWIMMING WITH THE SPESS CARP
		life_status_dead_senses()
		return 1

	//ALIVE. LIGHTS ARE ON
	// The body ticks afflictions, recomputes vitals once, and applies
	// death (organ death) and unconsciousness (consciousness model).
	src.body.life_tick()
	if(src.stat == DEAD)
		life_status_dead_senses()
		return 1

	var/in_crit = life_status_update_consciousness()
	life_status_update_hallucinations()
	life_status_update_tiredness()
	life_status_update_fear()
	life_status_update_sleep(in_crit)
	life_status_update_embedded()
	life_status_update_sight()
	life_status_update_hearing()
	life_status_update_rest()
	return 1

/mob/living/carbon/human/proc/life_status_dead_senses()
	src.set_blinded(1)
	src.status_set(STAT_MUTED, 0)
	src.deaf_loop.stop() // Ear Ringing/Deafness - Not sure if we need this, but, safety.

/// UNCONSCIOUS. NO-ONE IS HOME. Returns TRUE when the consciousness model has the body out.
/mob/living/carbon/human/proc/life_status_update_consciousness()
	if(!src.body.is_unconscious())
		return FALSE
	src.status_at_least(STAT_PARALYZED, 3)
	src.status_at_least(STAT_SLEEPING, 3)
	src.set_stat(UNCONSCIOUS)
	src.set_blinded(TRUE)
	if(!has_trait(src, TRAIT_CRITICAL_CONDITION))
		add_trait(src, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)
	return TRUE

/mob/living/carbon/human/proc/life_status_update_hallucinations()
	if(!src.has_status(STAT_HALLUCINATING))
		return
	if(src.status_units(STAT_HALLUCINATING) >= HALLUCINATION_THRESHOLD && !(src.species.flags & (NO_POISON|IS_PLANT|NO_HALLUCINATION)) && !has_trait(src, TRAIT_MADNESS_IMMUNE))
		src.handle_hallucinations()

/// Tiredness from vore drain wears off; very tired bodies fall asleep.
/mob/living/carbon/human/proc/life_status_update_tiredness()
	if(!src.tiredness)
		return
	src.set_tiredness((src.tiredness - 1))
	if(src.tiredness >= 100)
		src.status_at_least(STAT_SLEEPING, 5)

/// Fear wears off; a frightened organic body shakes, drops things and shows it.
/mob/living/carbon/human/proc/life_status_update_fear()
	if(!src.fear)
		return
	src.set_fear((src.fear - 1))
	if(src.fear >= 80 && src.client?.prefs?.read_preference(/datum/preference/toggle/play_ambience))
		if(COOLDOWN_FINISHED(src, fear_sound_cooldown))
			src << sound('sound/effects/Heart Beat.ogg',0,0,0,25)
			COOLDOWN_START(src, fear_sound_cooldown, 51 SECONDS)
	if(!(src.biology() & BIOLOGY_ORGANIC))
		return
	if(src.fear >= 80)
		if(prob(1) && src.get_active_hand())
			var/stuff_to_drop = src.get_active_hand()
			src.drop_item()
			act_message(src, null, MSG_SELF(span_warning("You drop your [stuff_to_drop]!")), \
				MSG_OTHERS(span_notice("%U% suddenly drops their [stuff_to_drop].")))
		if(prob(5))
			life_status_fear_emote()
	else if(src.fear >= 30 && prob(2))
		life_status_fear_emote()

/mob/living/carbon/human/proc/life_status_fear_emote()
	var/fear_self = pick(src.fear_message_self)
	var/fear_other = pick(src.fear_message_other)
	act_message(src, null, MSG_SELF(span_warning("[fear_self]")), MSG_OTHERS(span_notice("%U%[fear_other]")))

/// Asleep: unconscious, pain eases, dreams and snores. Otherwise (and not knocked out) conscious.
/mob/living/carbon/human/proc/life_status_update_sleep(in_crit)
	if(!src.has_status(STAT_SLEEPING))
		if(!in_crit)
			src.set_stat(CONSCIOUS)
			if(has_trait(src, TRAIT_CRITICAL_CONDITION))
				remove_trait(src, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)
		return
	src.set_blinded(TRUE)
	src.set_stat(UNCONSCIOUS)
	src.animate_tail_reset()
	src.mend(TREAT_ANALGESIC, 3) // Sleep eases pain on top of its natural fading.
	if(!src.has_status(STAT_SLEEPING))
		return
	if(prob(2))
		if(prob(50))
			src.mend(TREAT_TISSUE_REPAIR, 1)
		else
			src.mend(TREAT_BURN_CARE, 1)
	src.handle_dreams()
	// Nobody home (SSD, or no mind at all): the body stays asleep until a player returns.
	if(!src.mind || !src.client)
		src.status_at_least(STAT_SLEEPING, 1)
	if(prob(2) && !src.is_critical() && !src.get_hallucination_state()?.get_fakecrit() && src.client)
		src.emote("snore")

/// Periodically double-check embedded_flag.
/mob/living/carbon/human/proc/life_status_update_embedded()
	if(!src.embedded_flag || (src.life_tick % 10))
		return
	var/list/visible = src.get_visible_implants(0)
	if(!length(visible) || !src.embedded_needs_process())
		src.embedded_flag = 0

/// Eyes: a rig visor, the vision organ, disabilities and blindfolds.
/mob/living/carbon/human/proc/life_status_update_sight()
	//Check rig first because it's two-check and other checks will override it.
	if(life_status_rig_visor_blinds())
		src.set_blinded(1)

	if(!src.species.vision_organ) // Presumably if a species has no vision organs, they see via some other means.
		src.status_set(STAT_BLINDED, 0)
		src.set_blinded(0)
		src.status_set(STAT_BLURRY, 0)
		src.clear_alert("blind")
		return
	var/obj/item/organ/vision = src.organ_in(src.species.vision_organ)
	if(!vision || vision.is_broken())   // Vision organs cut out or broken? Permablind.
		src.status_set(STAT_BLINDED, 1)
		src.set_blinded(1)
		src.status_set(STAT_BLURRY, 1)
		src.throw_alert("blind", /atom/movable/screen/alert/blind)
		return
	//You have the requisite organs
	if(src.sdisabilities & BLIND) 	// Disabled-blind, doesn't get better on its own
		src.set_blinded(1)
		src.throw_alert("blind", /atom/movable/screen/alert/blind)
	else if(src.has_status(STAT_BLINDED) || src.wearing_blindfold())	// Blindness wears off on its own; a blindfold also heals blur faster (status_rate())
		src.set_blinded(1)
		src.throw_alert("blind", /atom/movable/screen/alert/blind)
	if(vision.is_bruised())   // Vision organs impaired? Permablurry.
		src.status_at_least(STAT_BLURRY, 1)

/// A worn rig helmet whose visor restriction blinds.
/mob/living/carbon/human/proc/life_status_rig_visor_blinds()
	var/obj/item/rig/O = src.get_equipped_item(SLOT_ID_BACK)
	if(!istype(O) || !O.helmet || O.helmet != src.get_equipped_item(SLOT_ID_HEAD) || !(O.helmet.body_parts_covered & EYES))
		return FALSE
	return (O.offline && O.offline_vision_restriction == 2) || (!O.offline && O.vision_restriction == 2)

/// Ears: disability deafness holds; ear damage heals, faster under earmuffs.
/mob/living/carbon/human/proc/life_status_update_hearing()
	if(src.sdisabilities & DEAF)	//disabled-deaf, doesn't get better on its own
		src.status_at_least(STAT_DEAFENED, 1)
		src.deaf_loop.start(skip_start_sound = TRUE) // Ear Ringing/Deafness
	else if(!src.has_status(STAT_DEAFENED))	// deafness wears off on its own; ears don't heal meanwhile
		if(src.get_ear_protection() >= 2)	//resting your ears with earmuffs heals ear damage faster
			src.set_ear_damage(max(src.ear_damage-0.15, 0))
			src.status_at_least(STAT_DEAFENED, 1)
		else if(src.ear_damage < 25)	//ear damage heals slowly under this threshold. otherwise you'll need earmuffs
			src.set_ear_damage(max(src.ear_damage-0.05, 0))

/// Resting eases pain; drowsiness blurs and nods off; dirt spreads to gloves.
/mob/living/carbon/human/proc/life_status_update_rest()
	//Resting eases pain faster than it fades on its own.
	if(src.resting)
		src.mend(TREAT_ANALGESIC, 2)
	if(src.has_status(STAT_DROWSY))
		src.status_at_least(STAT_BLURRY, 2)
		if(prob(5))
			src.status_at_least(STAT_SLEEPING, 1)
			src.status_at_least(STAT_PARALYZED, 5)
	// If you're dirty, your gloves will become dirty, too.
	var/obj/item/gloves = src.get_equipped_item(SLOT_ID_GLOVES)
	if(gloves && src.germ_level > gloves.germ_level && prob(10))
		gloves.germ_level += 1

/mob/living/carbon/human/set_stat(new_stat)
	. = ..()
	if(. && stat)
		update_skin(1)


/// A24: nothing for others to see (no hud_updateflag) and nothing on our own screen that moves
/// on its own: no client, or a settled conscious body with no fading overlay.
/mob/living/carbon/human/life_hud_idle()
	if(src.hud_updateflag || act_wanted(src, /datum/act/draw_hud))
		return FALSE
	if(!src.client)
		return TRUE
	if(src.stat != CONSCIOUS || src.is_critical() || src.oxygen_debt() || src.damageoverlaytemp)
		return FALSE
	if(src.tiredness || src.fear || src.blinded)
		return FALSE
	return !src.has_status(STAT_BLURRY) && !src.has_status(STAT_DRUGGED)

/// Nutrition drains and darksight re-adapts slowly; hud_updateflag bits are set raw.
/mob/living/carbon/human/life_hud_rewake_delay()
	return 5 SECONDS

/// P2-F1: the human screen, one proc per overlay family below.
/mob/living/carbon/human/life_hud()
	if(src.hud_updateflag) // update our mob's hud overlays, AKA what others see flaoting above our head
		life_hud_list()

	// now handle what we see on our screen
	. = ..()
	if(!.)
		return

	if(istype(src.client.eye,/obj/machinery/camera))
		var/obj/machinery/camera/cam = src.client.eye
		if(LAZYLEN(cam.client_huds))
			src.client.screen |= cam.client_huds

	if(src.stat == DEAD) //Dead
		if(!src.has_status(STAT_DRUGGED))
			src.see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else if(src.is_critical()) //Crit
		life_hud_crit_overlay()
	else //Alive
		src.clear_fullscreen("crit")
		life_hud_condition_overlays()
		life_hud_nutrition_alert()
		life_hud_sight_overlays()
		if(!src.surrounding_belly() && !src.previewing_belly) // Belly fullscreens safety
			src.clear_fullscreen("belly")
			src.belly_overlay_tgui?.hide() // hide TGUI belly overlay
		if(CONFIG_GET(flag/welder_vision) && life_hud_welder_vision())
			src.claim_global_hud(GLOB.global_hud.darkMask)

	src.reconcile_global_huds()

/// Severity band of `value` against ascending `thresholds`: 0 below the first, n at or past the nth.
/mob/living/carbon/human/proc/life_hud_overlay_band(value, list/thresholds)
	. = 0
	for(var/threshold in thresholds)
		if(value < threshold)
			return
		.++

/// Critical damage passage overlay, deeper as vitality drains (0 at the crit line, -100 at the end).
/mob/living/carbon/human/proc/life_hud_crit_overlay()
	var/depth = -100 * (2 * src.vitality() - 1) // 0 at the crit line, 100 at the end
	var/static/list/crit_bands = list(10, 20, 30, 40, 50, 60, 70, 80, 90, 95)
	src.overlay_fullscreen("crit", /atom/movable/screen/fullscreen/crit, life_hud_overlay_band(depth, crit_bands))

/// Oxygen debt, injury, tiredness (drain vore) and fear overlays.
/mob/living/carbon/human/proc/life_hud_condition_overlays()
	var/static/list/oxy_bands = list(10, 20, 25, 30, 35, 40, 45)
	var/static/list/hurt_bands = list(10, 25, 40, 55, 70, 85)
	var/static/list/tired_bands = list(10, 20, 30, 45, 60, 75, 90)
	var/static/list/fear_bands = list(10, 20, 30, 50, 70, 90)
	var/debt = src.oxygen_debt()
	if(debt)
		src.overlay_fullscreen("oxy", /atom/movable/screen/fullscreen/oxy, life_hud_overlay_band(debt, oxy_bands))
	else
		src.clear_fullscreen("oxy")

	//Fire and Brute damage overlay (BSSR)
	var/hurtdamage = src.injury_load(INJURY_CATEGORY_PHYSICAL) + src.injury_load(INJURY_CATEGORY_THERMAL) + src.damageoverlaytemp
	src.damageoverlaytemp = 0 // We do this so we can detect if someone hits us or not.
	if(hurtdamage)
		src.overlay_fullscreen("brute", /atom/movable/screen/fullscreen/brute, life_hud_overlay_band(hurtdamage, hurt_bands))
	else
		src.clear_fullscreen("brute")

	if(src.tiredness)
		src.overlay_fullscreen("tired", /atom/movable/screen/fullscreen/oxy, life_hud_overlay_band(src.tiredness, tired_bands))
	else
		src.clear_fullscreen("tired")

	if(src.fear)
		src.overlay_fullscreen("fear", /atom/movable/screen/fullscreen/fear, life_hud_overlay_band(src.fear, fear_bands))
	else
		src.clear_fullscreen("fear")

/// Hunger alerts in the body's style (P2-S5: hunger_alert_style(), not a species name check).
/mob/living/carbon/human/proc/life_hud_nutrition_alert()
	var/static/list/alerts_by_style = list(
		"[HUNGER_ALERT_ORGANIC]" = list(/atom/movable/screen/alert/fat, /atom/movable/screen/alert/hungry, /atom/movable/screen/alert/starving),
		"[HUNGER_ALERT_SYNTH]" = list(/atom/movable/screen/alert/fat/synth, /atom/movable/screen/alert/hungry/synth, /atom/movable/screen/alert/starving/synth),
		"[HUNGER_ALERT_VAMPIRE]" = list(/atom/movable/screen/alert/fat/vampire, /atom/movable/screen/alert/hungry/vampire, /atom/movable/screen/alert/starving/vampire),
	)
	var/list/alerts = alerts_by_style["[src.hunger_alert_style()]"] || alerts_by_style["[HUNGER_ALERT_ORGANIC]"]
	switch(src.nutrition)
		if(450 to INFINITY)
			src.throw_alert("nutrition", alerts[1])
		if(250 to 450)
			src.clear_alert("nutrition")
		if(150 to 250)
			src.throw_alert("nutrition", alerts[2])
		else
			src.throw_alert("nutrition", alerts[3])

/// Blindness, nearsightedness, blur and drug overlays.
/mob/living/carbon/human/proc/life_hud_sight_overlays()
	if(src.blinded)
		src.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
		src.throw_alert("blind", /atom/movable/screen/alert/blind)
	else
		src.clear_fullscreen("blind")
		src.clear_alert("blind")

	var/apply_nearsighted_overlay = FALSE
	if(src.is_nearsighted())
		apply_nearsighted_overlay = TRUE
		var/obj/item/clothing/glasses/G = src.get_equipped_item(SLOT_ID_EYES)
		if(istype(G) && G.prescription)
			apply_nearsighted_overlay = FALSE
		if(src.nif && src.nif.flag_check(NIF_V_CORRECTIVE, NIF_FLAGS_VISION))
			apply_nearsighted_overlay = FALSE
	src.set_fullscreen(apply_nearsighted_overlay, "nearsighted", /atom/movable/screen/fullscreen/impaired, 1)

	src.set_fullscreen(src.status_units(STAT_BLURRY), "blurry", /atom/movable/screen/fullscreen/blurry)
	src.set_fullscreen(src.status_units(STAT_DRUGGED), "high", /atom/movable/screen/fullscreen/high)
	if(src.has_status(STAT_DRUGGED))
		src.throw_alert("high", /atom/movable/screen/alert/high)
	else
		src.clear_alert("high")

/// Is anything dimming the view like a welding mask (short sight, welding gear, UV filter, rig visor)?
/mob/living/carbon/human/proc/life_hud_welder_vision()
	if(src.species.short_sighted || src.absorbed)
		return TRUE
	var/obj/item/clothing/glasses/welding/goggles = src.get_equipped_item(SLOT_ID_EYES)
	if(istype(goggles) && !goggles.up)
		return TRUE
	if(src.nif && src.nif.flag_check(NIF_V_UVFILTER,NIF_FLAGS_VISION))
		return TRUE
	if(istype(src.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/thinblindfold))
		return TRUE
	var/obj/item/clothing/head/welding/mask = src.get_equipped_item(SLOT_ID_HEAD)
	if(istype(mask) && !mask.up)
		return TRUE
	var/obj/item/rig/O = src.get_equipped_item(SLOT_ID_BACK)
	if(istype(O) && O.helmet && O.helmet == src.get_equipped_item(SLOT_ID_HEAD) && (O.helmet.body_parts_covered & EYES))
		if((O.offline && O.offline_vision_restriction == 1) || (!O.offline && O.vision_restriction == 1))
			return TRUE
	return FALSE

/// Pain as a fraction of the pain that knocks this body out (1 = passing
/// out from pain). Drives the HUD's softcrit / hardcrit indicators.
/mob/living/carbon/human/proc/pain_knockout_fraction()
	var/datum/body/humanoid/HB = body
	if(!istype(HB))
		return 0
	return current_pain() / max(1, HB.pain_tolerance() + 100)

/mob/living/carbon/human/life_hud_health_icons()
	. = ..()
	if(!. || !src.healths)
		return

	if(src.stat == DEAD || (src.status_flags & FAKEDEATH)) //Dead
		src.healths.icon_state = "health7"	//DEAD healthmeter
		src.health_doll_key = null
		return

	if(src.is_critical()) //Crit
		return

	if(src.factor(BF_ANALGESIA) > 100)
		src.healths.icon_state = "health_numb"
		src.health_doll_key = null
		return

	// A by-limb health display. The doll is only rebuilt when what it shows changes: each limb's
	// cached damage image and colour band, fire, and the pain indicators make up the key.
	var/trauma_val = 0 // Used in calculating softcrit/hardcrit indicators.
	if(src.can_feel_pain())
		trauma_val = src.pain_knockout_fraction()
	var/limb_trauma_val = trauma_val*0.3
	var/hallucination_hud = src.get_hallucination_state()?.get_hud_state()
	var/burning = src.on_fire || hallucination_hud == HUD_HALLUCINATION_ONFIRE
	if(hallucination_hud == HUD_HALLUCINATION_CRIT)
		trauma_val = 2

	var/no_damage = 1
	var/key = "[burning ? src.get_fire_icon_state() : ""]"
	for(var/obj/item/organ/external/E in src.organs)
		if(no_damage && (E.get_trauma() || E.get_burn()))
			no_damage = 0
		var/image/limb_image = E.get_damage_hud_image(limb_trauma_val)
		key += "|\ref[limb_image][limb_image.color]"
	var/show_pain = trauma_val && src.can_feel_pain()
	key += "|[show_pain && trauma_val > 0.7][show_pain && trauma_val >= 1][!trauma_val && no_damage]"
	if(key == src.health_doll_key)
		return
	src.health_doll_key = key

	var/mutable_appearance/healths_ma = new(src.healths)
	healths_ma.icon_state = "blank"
	healths_ma.overlays = null
	healths_ma.plane = PLANE_PLAYER_HUD
	var/list/health_images = list()
	for(var/obj/item/organ/external/E in src.organs)
		health_images += E.get_damage_hud_image(limb_trauma_val)
	if(burning)
		health_images += image('icons/mob/OnFire.dmi',"[src.get_fire_icon_state()]")
	if(show_pain)
		if(trauma_val > 0.7)
			health_images += image('icons/mob/screen1_health.dmi',"softcrit")
		if(trauma_val >= 1)
			health_images += image('icons/mob/screen1_health.dmi',"hardcrit")
	else if(!trauma_val && no_damage)
		health_images += image('icons/mob/screen1_health.dmi',"fullhealth")

	healths_ma.add_overlay(health_images)
	src.healths.appearance = healths_ma

/// The last by-limb health doll this human's HUD built (see health_icons); null forces a rebuild.
/mob/living/carbon/human/var/tmp/health_doll_key


/mob/living/carbon/human/life_vision()
	if(src.stat == DEAD)
		src.sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS|SEE_SELF
		src.see_in_dark = 8
	else //We aren't dead
		src.sight &= ~(SEE_TURFS|SEE_MOBS|SEE_OBJS)

		if(src.see_invisible_default > SEE_INVISIBLE_LEVEL_ONE)
			src.see_invisible = src.see_invisible_default
		else
			src.see_invisible = src.see_in_dark>2 ? SEE_INVISIBLE_LEVEL_ONE : src.see_invisible_default

		// Do this early so certain stuff gets turned off before vision is assigned.
		var/area/A = get_area(src)
		if(A?.flag_check(AREA_NO_SPOILERS))
			src.disable_spoiler_vision()

		if(src.has_mutation(XRAY))
			src.sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS
			src.see_in_dark = 8
			if(!src.has_status(STAT_DRUGGED))		src.see_invisible = SEE_INVISIBLE_LEVEL_TWO

		if(src.seer==1)
			var/obj/effect/rune/R = locate_within(src.loc, /obj/effect/rune)
			if(R && R.word1 == GLOB.cultwords["see"] && R.word2 == GLOB.cultwords["hell"] && R.word3 == GLOB.cultwords["join"])
				src.see_invisible = SEE_INVISIBLE_CULT
			else
				src.see_invisible = src.see_invisible_default
				src.seer = 0

		if(!src.seedarkness)
			src.sight = src.species.get_vision_flags(src)
			src.see_in_dark = 8
			src.see_invisible = SEE_INVISIBLE_NOLIGHTING

		else
			src.sight = src.species.get_vision_flags(src)
			src.see_in_dark = src.species.darksight
			if(src.see_invisible_default > SEE_INVISIBLE_LEVEL_ONE)
				src.see_invisible = src.see_invisible_default
			else
				src.see_invisible = src.see_in_dark>2 ? SEE_INVISIBLE_LEVEL_ONE : src.see_invisible_default

		var/glasses_processed = 0
		var/obj/item/rig/rig = src.get_rig()
		if(istype(rig) && rig.visor && !src.is_remote_viewing())
			if(!rig.helmet || (src.get_equipped_item(SLOT_ID_HEAD) && rig.helmet == src.get_equipped_item(SLOT_ID_HEAD)))
				if(rig.visor && rig.visor.vision && rig.visor.active && rig.visor.vision.glasses)
					glasses_processed = src.process_glasses(rig.visor.vision.glasses)

		if(src.get_equipped_item(SLOT_ID_EYES) && !glasses_processed && !src.is_remote_viewing())
			glasses_processed = src.process_glasses(src.get_equipped_item(SLOT_ID_EYES))
		if(src.has_mutation(XRAY))
			src.sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS
			src.see_in_dark = 8
			if(!src.has_status(STAT_DRUGGED))
				src.see_invisible = SEE_INVISIBLE_LEVEL_TWO

		src.sight |= src.factor(BF_SIGHT_FLAGS)

		if(!glasses_processed && src.nif)
			var/datum/nifsoft/vision_soft
			for(var/datum/nifsoft/NS in src.nif.nifsofts)
				if(NS.vision_exclusive && NS.active)
					vision_soft = NS
					break
			if(vision_soft)
				glasses_processed = src.process_nifsoft_vision(vision_soft)		//not really glasses but equitable

		if(!glasses_processed && (src.species.get_vision_flags(src) > 0))
			src.sight |= src.species.get_vision_flags(src)
		if(!src.seer && !glasses_processed && src.seedarkness)
			src.see_invisible = src.see_invisible_default

		var/mob/observer/eye/eyeobj = src?.active_eye()
		if(eyeobj && eyeobj?.eye_owner() != src)
			src.reset_perspective()

	// Call parent to handle signals
	..()

/mob/living/carbon/human/proc/process_glasses(obj/item/clothing/glasses/G)
	. = FALSE
	if(G && G.active)
		if(G.darkness_view)
			see_in_dark += G.darkness_view
			. = TRUE
		if(G.overlay())
			claim_global_hud(G.overlay())
		if(G.vision_flags)
			sight |= G.vision_flags
			. = TRUE
		if(istype(G,/obj/item/clothing/glasses/night) && !seer)
			see_invisible = SEE_INVISIBLE_MINIMUM

		if(G.see_invisible >= 0)
			see_invisible = G.see_invisible
			. = TRUE
		else if(!has_status(STAT_DRUGGED) && !seer)
			see_invisible = see_invisible_default

/mob/living/carbon/human/proc/process_nifsoft_vision(datum/nifsoft/NS)
	. = FALSE
	if(NS && NS.active)
		if(NS.darkness_view)
			see_in_dark += NS.darkness_view
			. = TRUE
		if(NS.vision_flags_mob)
			sight |= NS.vision_flags_mob
			. = TRUE

/mob/living/carbon/human/life_random_events_due()
	return TRUE

/mob/living/carbon/human/life_random_events(datum/seq_frame/life/F)
	// Puke if toxloss is too high
	if(!src.stat && !isbelly(src.loc))
		var/toxic_load = src.injury_load(INJURY_CATEGORY_TOXIC)
		if (toxic_load >= 30 && HAS_SYNTHETIC_BIOLOGY(src))
			if(!src.has_status(STAT_CONFUSED))
				if(prob(5))
					to_chat(src, span_danger("You lose directional control!"))
					src.status_at_least(STAT_CONFUSED, 10)
		if (toxic_load >= 45 && !HAS_SYNTHETIC_BIOLOGY(src))
			after(src, 0, TYPE_PROC_REF(/mob/living, vomit))


	//0.1% chance of playing a scary sound to someone who's in complete darkness
	if(isturf(src.loc) && rand(1,1000) == 1)
		var/turf/T = src.loc
		if(T.get_lumcount() <= LIGHTING_SOFT_THRESHOLD)
			/* 
			if(text2num(time2text(world.timeofday, "MM")) == 4)
				if(text2num(time2text(world.timeofday, "DD")) == 1)
					playsound_local(src,SFX_VOICE_SCAWWYSOWNDS,50, 0)
					return
			*/
			src.playsound_local(src,pick(GLOB.scarySounds),50, 1, -1)

/// MED-6: a non-changeling whose chemical display is already hidden has nothing to do.
/mob/living/carbon/human/proc/life_changeling_due()
	if(is_changeling(src))
		return TRUE
	return src.mind && src.hud_used && src.ling_chem_display?.invisibility != INVISIBILITY_ABSTRACT

/mob/living/carbon/human/proc/life_changeling_rewake()
	return 30 SECONDS

/// Updates the number of stored chemicals for powers.
/mob/living/carbon/human/proc/life_changeling(datum/seq_frame/life/F)
	var/datum/changeling/comp = is_changeling(src)
	if(!comp)
		if(src.mind && src.hud_used)
			src.ling_chem_display.invisibility = INVISIBILITY_ABSTRACT
		return
	else
		comp.regenerate()
		if(src.hud_used)
			src.ling_chem_display.invisibility = INVISIBILITY_NONE
			switch(comp.chem_storage)
				if(1 to 50)
					switch(comp.chem_charges)
						if(0 to 9)
							src.ling_chem_display.icon_state = "ling_chems0"
						if(10 to 19)
							src.ling_chem_display.icon_state = "ling_chems10"
						if(20 to 29)
							src.ling_chem_display.icon_state = "ling_chems20"
						if(30 to 39)
							src.ling_chem_display.icon_state = "ling_chems30"
						if(40 to 49)
							src.ling_chem_display.icon_state = "ling_chems40"
						if(50)
							src.ling_chem_display.icon_state = "ling_chems50"
				if(51 to 80) //This is a crappy way of checking for engorged sacs...
					switch(comp.chem_charges)
						if(0 to 9)
							src.ling_chem_display.icon_state = "ling_chems0e"
						if(10 to 19)
							src.ling_chem_display.icon_state = "ling_chems10e"
						if(20 to 29)
							src.ling_chem_display.icon_state = "ling_chems20e"
						if(30 to 39)
							src.ling_chem_display.icon_state = "ling_chems30e"
						if(40 to 49)
							src.ling_chem_display.icon_state = "ling_chems40e"
						if(50 to 59)
							src.ling_chem_display.icon_state = "ling_chems50e"
						if(60 to 69)
							src.ling_chem_display.icon_state = "ling_chems60e"
						if(70 to 79)
							src.ling_chem_display.icon_state = "ling_chems70e"
						if(80)
							src.ling_chem_display.icon_state = "ling_chems80e"

/// MED-6: no traumatic shock building and none to recover from.
/mob/living/carbon/human/proc/life_shock_due()
	return src.shock_stage > 0 || src.traumatic_shock >= 80

/mob/living/carbon/human/proc/life_shock_rewake()
	return 10 SECONDS

/// Traumatic shock stages from pain.
/mob/living/carbon/human/proc/life_shock(datum/seq_frame/life/F)
	src.updateshock()
	if(in_godmode(src))
		return 0	// Cancelled by a component
	if(src.traumatic_shock >= 80 && src.can_feel_pain())
		src.adjust_shock(1, "traumatic pain")
	else
		src.adjust_shock(-1, "recovery")
	if(!src.can_feel_pain()) return

	if(src.stat)
		return 0

	if(src.shock_stage == 10)
		if(src.traumatic_shock >= 80)
			src.custom_pain("[pick("It hurts so much", "You really need some painkillers", "Dear god, the pain")]!", 40)

	if(src.shock_stage >= 30)
		if(src.shock_stage == 30 && !isbelly(src.loc))
			src.automatic_custom_emote(VISIBLE_MESSAGE, "is having trouble keeping their eyes open.", check_stat = TRUE)
		src.status_at_least(STAT_BLURRY, 2)
		if(src.traumatic_shock >= 80)
			src.status_at_least(STAT_STUTTERING, 5)


	if(src.shock_stage == 40)
		if(src.traumatic_shock >= 80)
			to_chat(src, span_danger("[pick("The pain is excruciating", "Please&#44; just end the pain", "Your whole body is going numb")]!"))

	if (src.shock_stage >= 60)
		if(src.shock_stage == 60 && !isbelly(src.loc))
			src.automatic_custom_emote(VISIBLE_MESSAGE, "'s body becomes limp.", check_stat = TRUE)
		if (prob(2))
			if(src.traumatic_shock >= 80)
				to_chat(src, span_danger("[pick("The pain is excruciating", "Please&#44; just end the pain", "Your whole body is going numb")]!"))
			src.status_at_least(STAT_WEAKENED, 20)

	if(src.shock_stage >= 80)
		if (prob(5))
			if(src.traumatic_shock >= 80)
				to_chat(src, span_danger("[pick("The pain is excruciating", "Please&#44; just end the pain", "Your whole body is going numb")]!"))
				if(prob(20) && !isbelly(src.loc))
					src.emote("pain")
			src.status_at_least(STAT_WEAKENED, 20)

	if(src.shock_stage >= 120)
		if (prob(2))
			if(src.traumatic_shock >= 80)
				to_chat(src, span_danger("[pick("You black out", "You feel like you could die any moment now", "You are about to lose consciousness")]!"))
				if(prob(40) && !isbelly(src.loc))
					src.emote("pain")
			src.status_at_least(STAT_PARALYZED, 5)
			src.status_at_least(STAT_SLEEPING, 5)

	if(src.shock_stage == 150)
		if(!isbelly(src.loc))
			src.automatic_custom_emote(VISIBLE_MESSAGE, "can no longer stand, collapsing!", check_stat = TRUE)
			if(prob(60))
				src.emote("pain")
		src.status_at_least(STAT_WEAKENED, 20)

	if(src.shock_stage >= 150)
		src.status_at_least(STAT_WEAKENED, 20)

/mob/living/carbon/human/proc/life_pulse(datum/seq_frame/life/F)
	src.pulse = life_pulse_compute()

/// Event-driven: the heart, blood, factors, reagents and stat all reach it through the body
/// (CHANGE_MOB_HEALTH) or set_stat().

/// The pulse this body should show now.
/mob/living/carbon/human/proc/life_pulse_compute()

	var/temp = PULSE_NORM

	var/brain_modifier = 1

	var/modifier_shift = round(src.factor(BF_PULSE_SHIFT))
	// BF_PULSE_SET's baseline is -1: nothing forces the pulse.
	var/modifier_set = src.factor(BF_PULSE_SET)
	modifier_set = modifier_set < 0 ? null : round(modifier_set)

	if(!src.organ_in(O_HEART))
		temp = PULSE_NONE
		if(!isnull(modifier_set))
			temp = modifier_set
		return temp //No blood, no pulse.

	if(src.stat == DEAD)
		temp = PULSE_NONE
		if(!isnull(modifier_set))
			temp = modifier_set
		return temp	//that's it, you're dead, nothing can influence your pulse, aside from outside means.

	var/obj/item/organ/internal/heart/Pump = src.organ_in(O_HEART)

	// VF / asystole: the heart isn't moving blood (cardiac_arrhythmia).
	if(!src.has_cardiac_output())
		return isnull(modifier_set) ? PULSE_NONE : modifier_set

	var/obj/item/organ/internal/Control = src.organ_in(O_BRAIN) // any brain-slot occupant

	if(Control)
		brain_modifier = Control.get_control_efficiency()

		if(brain_modifier <= 0.7 && brain_modifier >= 0.4) // 70%-40% control, things start going weird as the brain is failing.
			brain_modifier = rand(5, 15) / 10

	if(Pump)
		temp += Pump.standard_pulse_level - PULSE_NORM

	if(round(src.vessel.get_reagent_amount(REAGENT_ID_BLOOD)) <= src.species.blood_volume*src.species.blood_level_danger)	//how much blood do we have
		temp = temp + 3	//not enough :(

	if(src.status_flags & FAKEDEATH)
		temp = PULSE_NONE		//pretend that we're dead. unlike actual death, can be inflienced by meds

	if(!isnull(modifier_set))
		temp = modifier_set

	temp = max(0, temp + modifier_shift)	// No negative pulses.

	if(Pump)
		///Prevents duplicating a reagent if it's in our gut and blood
		var/list/current_medications = list()
		//Stuff in our stomach, such as coffee, nicotine, 13loko, etc.
		for(var/datum/reagent/R in src.ingested.reagent_list)
			if((R.id in GLOB.tachycardics) && !(R.id in current_medications))
				if(temp < PULSE_THREADY && temp != PULSE_NONE) //If we really push it, we can get our pulse to thready.
					temp++
					current_medications += R.id
			if((R.id in GLOB.bradycardics) && !(R.id in current_medications))
				if(temp >= PULSE_NORM)
					temp--
					current_medications += R.id
		//Stuff in our bloodstream. (Heart-stopping drugs induce a cardiac_arrhythmia instead; see toxins.dm.)
		for(var/datum/reagent/R in src.reagents.reagent_list)
			if((R.id in GLOB.tachycardics) && !(R.id in current_medications))
				if(temp < PULSE_THREADY && temp != PULSE_NONE) //We can reach a thready pulse, but only if we actually have a pulse.
					temp++
					current_medications += R.id
			if((R.id in GLOB.bradycardics) && !(R.id in current_medications))
				if(temp >= PULSE_NORM) //Can get to PULSE_SLOW but never PULSE_NONE
					temp--
					current_medications += R.id
	return max(0, round(temp * brain_modifier))

/// MED-6: the heartbeat is a sound for a player with a racing pulse, in shock or in space.
/mob/living/carbon/human/proc/life_heartbeat_due()
	if(!src.client || src.pulse == PULSE_NONE)
		return FALSE
	return src.pulse >= PULSE_2FAST || src.shock_stage >= 10 || istype(get_turf(src), /turf/space)

/mob/living/carbon/human/proc/life_heartbeat_rewake()
	return 4 SECONDS

/// Heartbeat sound for fast pulses, shock or space.
/mob/living/carbon/human/proc/life_heartbeat(datum/seq_frame/life/F)
	if(src.pulse == PULSE_NONE)
		return

	var/obj/item/organ/internal/heart/H = src.organ_in(O_HEART)

	if(!H || (H.is_robotic()))
		return

	if(src.pulse >= PULSE_2FAST || src.shock_stage >= 10 || (istype(get_turf(src), /turf/space) && src.read_preference(/datum/preference/toggle/play_ambience)))
		//PULSE_THREADY - maximum value for pulse, currently it 5.
		//High pulse value corresponds to a fast rate of heartbeat.
		//Divided by 2, otherwise it is too slow.
		var/rate = (PULSE_THREADY - src.pulse)/2

		if(src.heartbeat >= rate)
			src.heartbeat = 0
			src << sound('sound/effects/singlebeat.ogg',0,0,0,50)
		else
			src.heartbeat++

/*
	Called by life(), instead of having the individual hud items update icons each tick and check for status changes
	we only set those statuses and icons upon changes.  Then those HUD items will simply add those pre-made images.
	This proc below is only called when those HUD elements need to change as determined by the mobs hud_updateflag.
*/
/mob/living/carbon/human/proc/life_hud_list()
	// P2-F1: one proc per HUD image; each redraws only when its bit is set.
	var/flags = src.hud_updateflag
	if (BITTEST(flags, HEALTH_HUD))
		life_hud_health()
	if (BITTEST(flags, LIFE_HUD))
		life_hud_life()
	if (BITTEST(flags, STATUS_HUD))
		life_hud_status()
	if (BITTEST(flags, ID_HUD))
		life_hud_id()
	if (BITTEST(flags, WANTED_HUD))
		life_hud_wanted_record()
	if (BITTEST(flags, IMPLOYAL_HUD) || BITTEST(flags, IMPCHEM_HUD) || BITTEST(flags, IMPTRACK_HUD))
		life_hud_implants()
	if (BITTEST(flags, SPECIALROLE_HUD))
		life_hud_special_role()
	if (BITTEST(flags, BACKUP_HUD))
		life_hud_backup()
	if (BITTEST(flags, VANTAG_HUD))
		life_hud_vantag()
	src.hud_updateflag = 0

/// Health bar: vitality band, or dead.
/mob/living/carbon/human/proc/life_hud_health()
	var/image/holder = src.grab_hud(HEALTH_HUD)
	var/image/health_us = src.grab_hud(HEALTH_VR_HUD)
	if(src.stat == DEAD || (src.status_flags & FAKEDEATH))
		holder.icon_state = "-100" 	// X_X
	else
		holder.icon_state = vitality_hud_state(src)
	if(src.block_hud)
		holder.icon_state = "hudblank"
	health_us.icon_state = holder.icon_state
	src.apply_hud(HEALTH_HUD, holder)
	src.apply_hud(HEALTH_VR_HUD, health_us)

/// Life indicator: synthetic, dead or healthy.
/mob/living/carbon/human/proc/life_hud_life()
	var/image/holder = src.grab_hud(LIFE_HUD)
	if(HAS_SYNTHETIC_BIOLOGY(src))
		holder.icon_state = "hudrobo"
	else if(src.stat == DEAD || (src.status_flags & FAKEDEATH))
		holder.icon_state = "huddead"
	else
		holder.icon_state = "hudhealthy"
	if(src.block_hud)
		holder.icon_state = "hudblank"
	src.apply_hud(LIFE_HUD, holder)

/// Medical status: synthetic, dead, ill (a known contagion) or healthy.
/mob/living/carbon/human/proc/life_hud_status()
	var/image/holder = src.grab_hud(STATUS_HUD)
	var/image/holder2 = src.grab_hud(STATUS_HUD_OOC)
	var/image/status_r = src.grab_hud(STATUS_R_HUD)
	if (HAS_SYNTHETIC_BIOLOGY(src))
		holder.icon_state = "hudrobo"
	else if(src.stat == DEAD || (src.status_flags & FAKEDEATH))
		holder.icon_state = "huddead"
		holder2.icon_state = "huddead"
	else if(src.has_known_contagion())
		holder.icon_state = "hudill"
	else
		holder.icon_state = "hudhealthy"
		if(src.has_known_contagion())
			holder2.icon_state = "hudill"
		else
			holder2.icon_state = "hudhealthy"
	if(src.block_hud)
		holder.icon_state = "hudblank"
		holder2.icon_state = "hudblank"

	status_r.icon_state = holder.icon_state
	src.apply_hud(STATUS_HUD, holder)
	src.apply_hud(STATUS_R_HUD, status_r)
	src.apply_hud(STATUS_HUD_OOC, holder2)

/// Job icon from the worn ID.
/mob/living/carbon/human/proc/life_hud_id()
	var/image/holder = src.grab_hud(ID_HUD)
	if(src.get_equipped_item(SLOT_ID_ID))
		var/obj/item/card/id/I = src.get_equipped_item(SLOT_ID_ID).GetID()
		if(I)
			holder.icon_state = "hud[ckey(GetJobName(I))]"
		else
			holder.icon_state = "hudunknown"
	else
		holder.icon_state = "hudunknown"

	if(src.block_hud)
		holder.icon_state = "hudblank"
	src.apply_hud(ID_HUD, holder)

/// Security record status for the worn ID's name.
/mob/living/carbon/human/proc/life_hud_wanted_record()
	var/image/holder = src.grab_hud(WANTED_HUD)
	holder.icon_state = "hudblank"
	var/perpname = src.name
	if(src.get_equipped_item(SLOT_ID_ID))
		var/obj/item/card/id/I = src.get_equipped_item(SLOT_ID_ID).GetID()
		if(I)
			perpname = I.registered_name

	for(var/datum/data/record/E in GLOB.data_core.general)
		if(E.fields["name"] == perpname)
			for (var/datum/data/record/R in GLOB.data_core.security)
				if((R.fields["id"] == E.fields["id"]) && (R.fields["criminal"] == "*Arrest*"))
					holder.icon_state = "hudwanted"
					break
				else if((R.fields["id"] == E.fields["id"]) && (R.fields["criminal"] == "Incarcerated"))
					holder.icon_state = "hudprisoner"
					break
				else if((R.fields["id"] == E.fields["id"]) && (R.fields["criminal"] == "Parolled"))
					holder.icon_state = "hudparolled"
					break
				else if((R.fields["id"] == E.fields["id"]) && (R.fields["criminal"] == "Released"))
					holder.icon_state = "hudreleased"
					break
	if(src.block_hud)
		holder.icon_state = "hudblank"
	src.apply_hud(WANTED_HUD, holder)

/// Loyalty, tracking and chemical implants.
/mob/living/carbon/human/proc/life_hud_implants()

	var/image/holder1 = src.grab_hud(IMPTRACK_HUD)
	var/image/holder2 = src.grab_hud(IMPLOYAL_HUD)
	var/image/holder3 = src.grab_hud(IMPCHEM_HUD)

	holder1.icon_state = "hudblank"
	holder2.icon_state = "hudblank"
	holder3.icon_state = "hudblank"

	for(var/obj/item/implant/I in contents_of(src, /obj/item/implant))
		if(I.implanted)
			if(!I.malfunction)
				if(istype(I,/obj/item/implant/tracking))
					holder1.icon_state = "hud_imp_tracking"
				if(istype(I,/obj/item/implant/loyalty))
					holder2.icon_state = "hud_imp_loyal"
				if(istype(I,/obj/item/implant/chem))
					holder3.icon_state = "hud_imp_chem"

	src.apply_hud(IMPTRACK_HUD, holder1)
	src.apply_hud(IMPLOYAL_HUD, holder2)
	src.apply_hud(IMPCHEM_HUD, holder3)

/// Antagonist role icon.
/mob/living/carbon/human/proc/life_hud_special_role()
	var/image/holder = src.grab_hud(SPECIALROLE_HUD)
	holder.icon_state = "hudblank"
	if(src.mind && src.mind.special_role)
		if(GLOB.hud_icon_reference[src.mind.special_role])
			holder.icon_state = GLOB.hud_icon_reference[src.mind.special_role]
		else
			holder.icon_state = "hudsyndicate"
	src.apply_hud(SPECIALROLE_HUD, holder)

/// Backup implant: mind and body scan on record.
/mob/living/carbon/human/proc/life_hud_backup()
	var/image/holder = src.grab_hud(BACKUP_HUD)

	holder.icon_state = "hudblank"

	for(var/obj/item/organ/external/E in src.organs)
		for(var/obj/item/implant/I in E.implants)
			if(I.implanted && istype(I,/obj/item/implant/backup))
				var/obj/item/implant/backup/B = I
				if(!src.mind)
					holder.icon_state = "hud_backup_nomind"
				else if(!(src.mind.name in B.our_db().body_scans))
					holder.icon_state = "hud_backup_nobody"
				else
					holder.icon_state = "hud_backup_norm"
	if(src.block_hud)
		holder.icon_state = "hudblank"
	src.apply_hud(BACKUP_HUD, holder)

/// Vore antag preference.
/mob/living/carbon/human/proc/life_hud_vantag()
	var/image/vantag = src.grab_hud(VANTAG_HUD)
	if(src.vantag_pref)
		vantag.icon_state = src.vantag_pref
	else
		vantag.icon_state = "hudblank"
	if(src.block_hud)
		vantag.icon_state = "hudblank"
	src.apply_hud(VANTAG_HUD, vantag)

/mob/living/carbon/human/on_fire_stack(seconds_per_tick, datum/status_effect/fire_handler/fire_stacks/fire_handler)
	var/no_protection = FALSE
	if(has_trait(src, TRAIT_IGNORE_FIRE_PROTECTION))
		no_protection = TRUE
	fire_handler.harm_human(seconds_per_tick, no_protection)

/mob/living/carbon/human/rejuvenate()
	restore_blood()
	set_shock(0, "rejuvenate")
	traumatic_shock = 0
	..()

// The defibrillation window needs no Life stage: the brain charges it on the body clock when
// read (/obj/item/organ/internal/brain/proc/sync_defib_window(), audit D10).



#undef HEAT_DAMAGE_LEVEL_1
#undef HEAT_DAMAGE_LEVEL_2
#undef HEAT_DAMAGE_LEVEL_3

#undef COLD_DAMAGE_LEVEL_1
#undef COLD_DAMAGE_LEVEL_2
#undef COLD_DAMAGE_LEVEL_3

#undef HUMAN_COMBUSTION_TEMP


// === merged from life_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/// MED-6: neither gaining (well fed, gain on, under the cap) nor losing (starving, loss on).
/mob/living/carbon/human/proc/life_weight_due()
	var/gaining = src.weight_gain && src.nutrition > MIN_NUTRITION_TO_GAIN && src.weight < MAX_MOB_WEIGHT
	var/losing = src.weight_loss && src.nutrition <= MAX_NUTRITION_TO_LOSE && src.weight > MIN_MOB_WEIGHT
	return gaining || losing

/mob/living/carbon/human/proc/life_weight_rewake()
	return 10 SECONDS

/// Weight gain and loss from nutrition.
/mob/living/carbon/human/proc/life_weight(datum/seq_frame/life/F)
	if (src.nutrition >= 0 && src.stat != 2)
		if (src.nutrition > MIN_NUTRITION_TO_GAIN && src.weight < MAX_MOB_WEIGHT && src.weight_gain)
			src.weight += src.species.metabolism*(0.01*src.weight_gain)

		else if (src.nutrition <= MAX_NUTRITION_TO_LOSE && src.stat != 2 && src.weight > MIN_MOB_WEIGHT && src.weight_loss)
			src.weight -= src.species.metabolism*(0.01*src.weight_loss) // starvation weight loss

//Our call for the NIF to do whatever
/// MED-6: no NIF, nothing to run.
/mob/living/carbon/human/proc/life_nif_due()
	return src.nif

/mob/living/carbon/human/proc/life_nif_rewake()
	return 30 SECONDS

/// Our call for the NIF to do whatever.
/mob/living/carbon/human/proc/life_nif(datum/seq_frame/life/F)
	if(!src.nif) return

	//Process regular life stuff
	src.nif.life()

//Overriding carbon move proc that forces default hunger factor
/mob/living/carbon/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	// Technically this does mean being dragged takes nutrition
	if(stat != DEAD)
		adjust_nutrition(hunger_rate/-10)
		if(m_intent == I_RUN)
			adjust_nutrition(hunger_rate/-10)

	// Moving around increases germ_level faster
	if(germ_level < GERM_LEVEL_MOVE_CAP && prob(8))
		germ_level++


/mob/living/carbon
	var/synth_cosmetic_pain = FALSE
