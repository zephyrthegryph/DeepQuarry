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
	var/hud_full_refresh_at = 0

// Human Life (doc/mob_life_architecture.md §4.5). The living core runs first; the human-only
// steps that followed ..() in the old Life() are TAIL systems below, in their old order:
//	hud refresh, voice, stasis sleep, fall, gate: human vitals,
//	[alive, not in stasis] changeling, organs, thermoregulation, weight, shock, pain, medical,
//	                       heartbeat, NIF, phobias, NPC
//	[dead, not in stasis]  defib timer
//	species components, visible name, pulse

/// The code before ..() in the old human Life().
/datum/life_system/type_pre/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/type_pre/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if (self.transforming)
		return LIFE_HALT

	//Apparently, the person who wrote this code designed it so that
	//blinded get reset each cycle and then get activated later in the
	//code. Very ugly. I dont care. Moving this stuff here so its easy
	//to find it.
	self.blinded = 0

	//TODO: seperate this out
	// update the current life tick, can be used to e.g. only do something every 4 ticks
	self.life_tick++
	return ..()

/// Periodic safety refresh of every HUD.
/datum/life_system/hud_refresh
	name = "hud refresh"
	bit = LIFE_SYS_HUD
	phase = LIFE_PHASE_TAIL
	order = 100
	mob_type = /mob/living/carbon/human
	woken_by = "its own timer"

/datum/life_system/hud_refresh/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	// The periodic safety refresh is intentionally rare (once a minute); state-changing
	// code continues to set its exact HUD dirty bits.
	if(world.time >= self.hud_full_refresh_at)
		self.hud_full_refresh_at = world.time + 1 MINUTES
		self.hud_updateflag = (1 << TOTAL_HUDS) - 1

/// Lazy: sleeps until the next refresh is due.
/datum/life_system/hud_refresh/idle(mob/living/carbon/human/self)
	return TRUE

/datum/life_system/hud_refresh/rewake_delay(mob/living/carbon/human/self)
	return max(1 SECONDS, self.hud_full_refresh_at - world.time)

/// The voice others hear.
/datum/life_system/voice
	name = "voice"
	bit = LIFE_SYS_IDENTITY
	phase = LIFE_PHASE_TAIL
	order = 110
	mob_type = /mob/living/carbon/human
	woken_by = "equipment (LIFE_WAKE_EQUIPMENT); body invalidate; set_stat; Moved; its own timer"

/datum/life_system/voice/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	self.voice = self.GetVoice()

/// Event-driven: equipment (masks, voice changers, rigs), the body, stat and moving (belly
/// absorb) wake it. Voice changers, changeling mimicry and disguises toggle from scattered
/// sites, so a slow timer backs the events up.
/datum/life_system/voice/idle(mob/living/carbon/human/self)
	return TRUE

/datum/life_system/voice/rewake_delay(mob/living/carbon/human/self)
	return 10 SECONDS

/// Deep stasis (BF_STASIS above STASIS_SLEEP_THRESHOLD) puts the body to sleep.
/datum/life_system/stasis_sleep
	name = "stasis sleep"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_TAIL
	order = 120
	mob_type = /mob/living/carbon/human

/datum/life_system/stasis_sleep/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(self.factor(BF_STASIS) > STASIS_SLEEP_THRESHOLD)
		self.Sleeping(20)

/// Falling (prevents people from floating).
/datum/life_system/fall
	name = "fall"
	bit = LIFE_SYS_MOVEMENT
	phase = LIFE_PHASE_TAIL
	order = 130
	mob_type = /mob/living/carbon/human

/datum/life_system/fall/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	self.fall()

/// `if(!stasis) if(stat != DEAD) ... else if(stat == DEAD) ...` in the old human Life().
/// No need to update all of the living-only systems if the guy is dead.
/datum/life_system/gate/human_vitals
	name = "gate: human vitals"
	phase = LIFE_PHASE_TAIL
	order = 135
	mob_type = /mob/living/carbon/human

/datum/life_system/gate/human_vitals/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(ctx.in_stasis(self))
		ctx.blocked |= LIFE_SEG_HUMAN_LIVE | LIFE_SEG_HUMAN_DEAD
	else if(self.stat != DEAD)
		ctx.blocked |= LIFE_SEG_HUMAN_DEAD
	else
		ctx.blocked |= LIFE_SEG_HUMAN_LIVE

/// Allergens, medication side effects, ischemia and the dirty medical domains.
/datum/life_system/medical
	name = "medical"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_TAIL
	order = 200
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/datum/life_system/medical/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	SEND_SIGNAL(self,COMSIG_HANDLE_ALLERGENS, self.factor(BF_ALLERGY))

	side_effects(self)
	self.dq_check_ischemic_damage()
	self.dq_process_dirty_medical_conditions()

/// Species NPC behaviour for client-less humans.
/datum/life_system/npc
	name = "npc"
	bit = LIFE_SYS_BEHAVIOUR
	phase = LIFE_PHASE_TAIL
	order = 270
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/datum/life_system/npc/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(!self.client)
		self.species.npc_behaviour(self)

/// The name others see: obscured or disfigured faces hide it.
/datum/life_system/visible_name
	name = "visible name"
	bit = LIFE_SYS_IDENTITY
	phase = LIFE_PHASE_TAIL
	order = 300
	mob_type = /mob/living/carbon/human
	woken_by = "equipment (LIFE_WAKE_EQUIPMENT); body invalidate (disfigurement); set_stat; its own timer"

/datum/life_system/visible_name/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	//Update our name based on whether our face is obscured/disfigured
	self.name = self.get_visible_name()

/// Event-driven like the voice system, with the same slow timer behind it.
/datum/life_system/visible_name/idle(mob/living/carbon/human/self)
	return TRUE

/datum/life_system/visible_name/rewake_delay(mob/living/carbon/human/self)
	return 10 SECONDS

/datum/life_system/breathing/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/breathing/carbon/human/breathe(mob/living/carbon/human/self)
	if(!self.inStasisNow())
		..()

// Calculate how vulnerable the human is to the current pressure.
// Returns 0 (equals 0 %) if sealed in an undamaged suit that's rated for the pressure, 1 if unprotected (equals 100%).
// Suitdamage can modifiy this in 10% steps.
// Protection scales down from 100% at the boundary to 0% at 10% in excess of the boundary
/mob/living/carbon/human/proc/get_pressure_weakness(pressure)
	if(pressure == null)
		return 1 // No protection if someone forgot to give a pressure

	var/pressure_adjustment_coefficient = 1 // Assume no protection at first.

	// Check suit
	if(wear_suit && wear_suit.max_pressure_protection != null && wear_suit.min_pressure_protection != null)
		pressure_adjustment_coefficient = 0
		// Pressure is too high
		if(wear_suit.max_pressure_protection < pressure)
			// Protection scales down from 100% at the boundary to 0% at 10% in excess of the boundary
			pressure_adjustment_coefficient += round((pressure - wear_suit.max_pressure_protection) / (wear_suit.max_pressure_protection/10))

		// Pressure is too low
		if(wear_suit.min_pressure_protection > pressure)
			pressure_adjustment_coefficient += round((wear_suit.min_pressure_protection - pressure) / (wear_suit.min_pressure_protection/10))

		// Handles breaches in your space suit. 10 suit damage equals a 100% loss of pressure protection.
		if(istype(wear_suit,/obj/item/clothing/suit/space))
			var/obj/item/clothing/suit/space/S = wear_suit
			if(S.can_breach && S.damage)
				pressure_adjustment_coefficient += S.damage * 0.1

	else
		// Missing key protection
		pressure_adjustment_coefficient = 1

	// Check hat
	if(head && head.max_pressure_protection != null && head.min_pressure_protection != null)
		// Pressure is too high
		if(head.max_pressure_protection < pressure)
			// Protection scales down from 100% at the boundary to 0% at 20% in excess of the boundary
			pressure_adjustment_coefficient += round((pressure - head.max_pressure_protection) / (head.max_pressure_protection/20))

		// Pressure is too low
		if(head.min_pressure_protection > pressure)
			pressure_adjustment_coefficient += round((head.min_pressure_protection - pressure) / (head.min_pressure_protection/20))

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

/datum/life_system/disabilities/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/disabilities/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	..()

	if(self.stat != CONSCIOUS) //Let's not worry about tourettes if you're not conscious.
		return

	if(isbelly(self.loc)) //Let's not have you seizing, coughing, or falling apart if you're in a belly.
		return

	var/rn = rand(0, 200)
	var/brain_damage = self.injury_load(INJURY_CATEGORY_NEURAL)
	if(brain_damage >= 5)
		if(0 <= rn && rn <= 3)
			self.custom_pain("Your head feels numb and painful.", 10)
	if(brain_damage >= 15)
		if(4 <= rn && rn <= 6) if(self.eye_blurry <= 0)
			to_chat(self, span_warning("It becomes hard to see for some reason."))
			self.eye_blurry = 10
	if(brain_damage >= 35)
		if(7 <= rn && rn <= 9) if(self.get_active_hand())
			to_chat(self, span_danger("Your hand won't respond properly, you drop what you're holding!"))
			self.drop_item()
	if(brain_damage >= 45)
		if(10 <= rn && rn <= 12)
			if(prob(50))
				to_chat(self, span_danger("You suddenly black out!"))
				self.Paralyse(10)
				self.Sleeping(10)
			else if(!self.lying)
				to_chat(self, span_danger("Your legs won't respond properly, you fall down!"))
				self.Weaken(10)

/datum/life_system/mutations/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/mutations/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	. = ..()
	if(.)
		return
	if(self.inStasisNow())
		return

	// Slow natural healing of wounds; cold-resistant bodies shrug off burns.
	if(self.injury_load(INJURY_CATEGORY_THERMAL))
		if((COLD_RESISTANCE in self.mutations) || (prob(1)))
			self.mend(TREAT_BURN_CARE, 1)
	if(self.injury_load(INJURY_CATEGORY_PHYSICAL))
		if(prob(1))
			self.mend(TREAT_TISSUE_REPAIR, 1)

	if((mRegen in self.mutations))
		var/heal = rand(0.2,1.3)
		if(prob(50))
			for(var/obj/item/organ/external/O as anything in self.organs)
				self.mend(TREAT_RESTORATION, heal, O)
		else
			self.mend(TREAT_TISSUE_REPAIR, heal)
			self.mend(TREAT_BURN_CARE, heal)


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
/mob/living/carbon/human/proc/radiation_burn(amount)
	var/list/candidates = list()
	for(var/obj/item/organ/external/E as anything in organs)
		if(E.robotic < ORGAN_ROBOT && !E.is_stump())
			candidates += E
	if(!length(candidates))
		return 0
	var/obj/item/organ/external/E = pick(candidates)
	return injure(INJURY_BURN, amount, E.organ_tag, null, 0, /datum/affliction/radiation_burns)

/datum/life_system/radiation/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/radiation/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	. = ..()
	if(.)
		return
	if(self.inStasisNow())
		return

	self.radiation = CLAMP(self.radiation,0,RADIATION_CAP) //Max of 100Gy. If you reach that...You're going to wish you were dead. You probably will be dead.
	self.accumulated_rads = CLAMP(self.accumulated_rads,0,RADIATION_CAP) //Max of 100Gy as well. You should never get higher than this. You will be dead before you can reach this.
	var/obj/item/organ/internal/I = null //Used for further down below when an organ is picked.
	if(!self.radiation)
		self.clear_alert("irradiated")
		if(self.accumulated_rads)
			self.accumulated_rads -= RADIATION_SPEED_COEFFICIENT //Accumulated rads slowly dissipate very slowly. Get to medical to get it treated!
	else if(((self.life_tick % 5 == 0) && self.radiation) || (self.radiation > 600)) //Radiation is a slow, insidious killer. Unless you get a massive dose, then the onset is sudden!

		if(HAS_TRAIT(self, TRAIT_HALT_RADIATION_EFFECTS)) //If we have a trait that halts radiation effects, then we just stop here. No need to do any of the checks below.
			return

		var/damage = 0
		var/rad_mod = self.species.radiation_mod

		if(!rad_mod) //If we are rad immune, stop here and remove rads if we have any.
			self.radiation -= 10 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			return

		if (self.radiation < GLOB.radiation_levels[self.species.rad_levels]["safe"]) //Less than 1.0 Gy. No side effects.
			self.radiation -= 10 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			self.accumulated_rads += 10 * RADIATION_SPEED_COEFFICIENT //No escape from accumulated rads.

		else if (self.radiation >= GLOB.radiation_levels[self.species.rad_levels]["safe"] && self.radiation < GLOB.radiation_levels[self.species.rad_levels]["danger_1"]) //Equivalent of 1.0-2.0 Gy. Minimum stage you start seeing effects.
			damage = 1
			self.radiation -= 10 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			self.accumulated_rads += 10 * RADIATION_SPEED_COEFFICIENT
			if(!self.isSynthetic())
				if(prob(5) && prob(100 * RADIATION_SPEED_COEFFICIENT) && !self.weakened)
					to_chat(self, span_warning("You feel exhausted."))
					self.AdjustWeakened(3)
				if(prob(5) && prob(100 * RADIATION_SPEED_COEFFICIENT) && self.species.get_bodytype() == SPECIES_HUMAN) //apes go bald
					if((self.h_style != "Bald" || self.f_style != "Shaved" ))
						to_chat(self, span_warning("Your hair falls out."))
						self.h_style = "Bald"
						self.f_style = "Shaved"
						self.update_hair()
				if(prob(1) && prob(100 * RADIATION_SPEED_COEFFICIENT)) //Rare chance of vomiting.
					spawn self.vomit()

		else if (self.radiation >= GLOB.radiation_levels[self.species.rad_levels]["danger_1"] && self.radiation < GLOB.radiation_levels[self.species.rad_levels]["danger_2"]) //Equivalent of 2.0 to 6.0 Gy. Nobody should ever be above this without extreme negligence.
			damage = 3
			self.radiation -= 30 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			self.accumulated_rads += 30 * RADIATION_SPEED_COEFFICIENT
			if(!self.isSynthetic())
				if(prob(5))
					self.radiation_burn(5 * RADIATION_SPEED_COEFFICIENT)
				if(prob(1))
					self.injure(INJURY_CELLULAR, 5 * RADIATION_SPEED_COEFFICIENT)
					self.emote("gasp")
				if(prob(5) && prob(100 * RADIATION_SPEED_COEFFICIENT))
					spawn self.vomit()
				if(prob(10) && !self.weakened)
					to_chat(self, span_warning("You feel sick."))
					self.AdjustWeakened(3)

		else if (self.radiation >= GLOB.radiation_levels[self.species.rad_levels]["danger_2"] && self.radiation < GLOB.radiation_levels[self.species.rad_levels]["danger_3"]) //Equivalent of 6.0 to 8.0 Gy.
			damage = 5
			self.radiation -= 50 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			self.accumulated_rads += 50 * RADIATION_SPEED_COEFFICIENT
			if(!self.isSynthetic())
				if(prob(15))
					self.radiation_burn(10 * RADIATION_SPEED_COEFFICIENT)
				if(prob(2))
					self.injure(INJURY_CELLULAR, 5 * RADIATION_SPEED_COEFFICIENT)
					self.emote("gasp")
				if(prob(10) && prob(100 * RADIATION_SPEED_COEFFICIENT))
					spawn self.vomit()
				if(prob(15) && !self.weakened)
					to_chat(self, span_warning("You feel horribly ill."))
					self.AdjustWeakened(3)
				if(prob(5) && self.internal_organs.len)
					// begin - organ mutations
					if(prob(2))
						// random organ time!
						self.random_malignant_organ(TRUE,FALSE,prob(40))
					// end
					else
						I = pick(self.internal_organs) //Internal organ damage...Not good. Not good at all.
						if(istype(I)) I.add_autopsy_data("Radiation Induced Cancerous Growth", damage)
						self.injure(INJURY_RADIATION, damage * rad_mod * RADIATION_SPEED_COEFFICIENT, I, flags = INJURE_IGNORE_RESISTANCE)


		else if (self.radiation >= GLOB.radiation_levels[self.species.rad_levels]["danger_3"] && self.radiation < GLOB.radiation_levels[self.species.rad_levels]["danger_4"]) //Equivalent of 8.0 to 30 Gy.
			self.throw_alert("irradiated", /atom/movable/screen/alert/irradiated)
			damage = 10
			self.radiation -= 100 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			self.accumulated_rads += 100 * RADIATION_SPEED_COEFFICIENT
			if(!self.isSynthetic())
				if(prob(25))
					self.radiation_burn(15 * RADIATION_SPEED_COEFFICIENT)
					if(prob(5))
						I = self.internal_organs_by_name[O_EYES]
						if(I)
							if(istype(I)) I.add_autopsy_data("Radiation Burns", damage)
							self.injure(INJURY_RADIATION, damage * rad_mod * RADIATION_SPEED_COEFFICIENT, I, flags = INJURE_IGNORE_RESISTANCE)
							to_chat(self, span_warning("Your eyes burn!"))
							self.eye_blurry += 10
				if(prob(4))
					self.injure(INJURY_CELLULAR, 5 * RADIATION_SPEED_COEFFICIENT)
					self.emote("gasp")
				if(prob(25) && prob(100 * RADIATION_SPEED_COEFFICIENT))
					spawn self.vomit()
				if(prob(20) && !self.weakened)
					to_chat(self, span_critical("You feel like your insides are burning!"))
					self.AdjustWeakened(5)
				if(prob(5))
					to_chat(self, span_critical("Your entire body feels like it's on fire!"))
					self.injure(INJURY_PAIN, 5)
				if(prob(10) && self.internal_organs.len)
					// begin - organ mutations
					if(prob(2))
						self.random_malignant_organ(TRUE,FALSE,prob(60))
					// end
					else
						I = pick(self.internal_organs) //Internal organ damage...Not good. Not good at all.
						if(istype(I)) I.add_autopsy_data("Radiation Induced Cancerous Growth", damage)
						self.injure(INJURY_RADIATION, damage * rad_mod * RADIATION_SPEED_COEFFICIENT, I, flags = INJURE_IGNORE_RESISTANCE)

		else if (self.radiation >= GLOB.radiation_levels[self.species.rad_levels]["danger_4"]) //Above 30Gy. You had to get absolutely blasted with rads for this.
			damage = 30
			self.radiation -= 300 * RADIATION_SPEED_COEFFICIENT * self.species.rad_removal_mod
			self.accumulated_rads += 300 * RADIATION_SPEED_COEFFICIENT

			if(!self.isSynthetic())
				self.radiation_burn(damage * RADIATION_SPEED_COEFFICIENT) //3 burn damage a tick as your body melts.
				self.injure(INJURY_CELLULAR, 15 * RADIATION_SPEED_COEFFICIENT) //1.5 cellular damage a tick as your cells mutate and break down.

				I = self.internal_organs_by_name[O_EYES]
				if(I)
					I.add_autopsy_data("Radiation Burns", damage * rad_mod * RADIATION_SPEED_COEFFICIENT)
					self.injure(INJURY_RADIATION, damage * rad_mod * RADIATION_SPEED_COEFFICIENT, I, flags = INJURE_IGNORE_RESISTANCE) //3 eye damage a tick as your eyes melt down.
					self.eye_blurry += 10

				if(prob(50) && prob(100 * RADIATION_SPEED_COEFFICIENT))
					spawn self.vomit()
				if(!self.paralysis && prob(30) && prob(100 * RADIATION_SPEED_COEFFICIENT)) //CNS is shutting down.
					to_chat(self, span_critical("You have a seizure!"))
					self.Paralyse(10)
					self.Sleeping(10)
					self.make_jittery(1000)
					if(!self.lying)
						self.emote("collapse")
				if(self.get_active_hand() && prob(15)) //CNS is shutting down.
					to_chat(self, span_danger("Your hand won't respond properly, you drop what you're holding!"))
					self.drop_item()
				if(self.internal_organs.len)  //TODO: Add malignant organs. - The person that wrote radcode.
					I = pick(self.internal_organs) //Internal organ damage...Not good. Not good at all.
					if(istype(I)) I.add_autopsy_data("Radiation Induced Cancerous Growth", damage * rad_mod * RADIATION_SPEED_COEFFICIENT)
					self.injure(INJURY_RADIATION, damage * rad_mod * RADIATION_SPEED_COEFFICIENT, I, flags = INJURE_IGNORE_RESISTANCE)

/* 		//Not-so-sparkledog code. TODO: Make a pref for 'special game interactions' that allows interactions that align with prefs to occur.
		if(radiation >= 250) //Special effect stuff that occurs at certain rad levels.
			if(prob(1) && prob(radiation/2 * RADIATION_SPEED_COEFFICIENT) && allow_spontaneous_tf) //If you've got spontaneous TF...well...
				scramble(1, self, 3) //I tried to base this on how many rads you took and it was...Hilarious. Sparkledogs everywhere.
				//For the most part, 3 strength will simply change colors. If you get really unlucky, it can do more TF's.
				//Math: 250 rads = 1/800 chance
				//500 rads = 1/400 chance chance. Etc.
*/

		if(damage)
			damage *= rad_mod
			self.injure(INJURY_TOXIN, damage * RADIATION_SPEED_COEFFICIENT, null, null, 0, /datum/affliction/radiation_poisoning)
			if(!self.isSynthetic() && self.organs.len)
				var/obj/item/organ/external/O = pick(self.organs)
				if(istype(O)) O.add_autopsy_data("Radiation Poisoning", damage)

	// Begin long-term radiation effects
	// Loss of taste occurs at 100 (2Gy) and is handled in taste.dm
	// These are all done one after another, so duplication is not required. Someone at 400rads will have the 100&400 effects.
	if(!self.radiation && self.accumulated_rads >= 100  && !self.reagents.has_reagent(REAGENT_ID_PRUSSIANBLUE)) //Let's not hit them with long term effects when they're actively being hit with rads.
		if(!self.isSynthetic())
			I = self.internal_organs_by_name[O_EYES]
			if(I) //Eye stuff
				if(prob(5) && prob(self.accumulated_rads * RADIATION_SPEED_COEFFICIENT))
					to_chat(self, span_warning("Your eyes water."))
					self.eye_blurry += 5
				if(self.accumulated_rads > 300) // (6Gy)
					if(prob(2) && prob(self.accumulated_rads * RADIATION_SPEED_COEFFICIENT))
						to_chat(self, span_warning("Your eyes burn."))
						I.add_autopsy_data("Radiation Burns", 1 * self.species.radiation_mod * RADIATION_SPEED_COEFFICIENT)
						self.injure(INJURY_RADIATION, 1 * self.species.radiation_mod * RADIATION_SPEED_COEFFICIENT, I, flags = INJURE_IGNORE_RESISTANCE) //0.1 damage. Not a lot, but enough to tell you to get to medical.
						self.eye_blurry += 10

			if(self.accumulated_rads > 200) // (4Gy)
				if(prob(5) && prob(self.accumulated_rads * RADIATION_SPEED_COEFFICIENT))
					to_chat(self, span_warning("Your feel nauseated."))
					spawn self.vomit()
				if(!self.weakened && prob(2) && prob(self.accumulated_rads * RADIATION_SPEED_COEFFICIENT))
					to_chat(self, span_warning("Your feel exhausted."))
					self.AdjustWeakened(3)
			if(self.accumulated_rads > 300) // (6Gy)
				if(self.get_active_hand() && prob(15) && prob(100 * RADIATION_SPEED_COEFFICIENT)) //CNS is shutting down.
					to_chat(self, span_danger("Your hand won't respond properly, you drop what you're holding!"))
					self.drop_item()
			if(self.accumulated_rads > 700) // (12Gy)
				if(!self.paralysis && prob(1) && prob(100 * RADIATION_SPEED_COEFFICIENT)) //1 in 1000 chance per tick.
					to_chat(self, span_critical("You have a seizure!"))
					self.Paralyse(10)
					self.Sleeping(10)
					self.make_jittery(1000)
					if(!self.lying)
						self.emote("collapse")

		else //The synthetic effects!
			return //Nothing for now.



	/** breathing **/

/datum/life_system/breathing/carbon/human/inhale_smoke(mob/living/carbon/human/self, datum/gas_mixture/environment)
	if(self.wear_mask && (self.wear_mask.item_flags & BLOCK_GAS_SMOKE_EFFECT))
		return
	if(self.glasses && (self.glasses.item_flags & BLOCK_GAS_SMOKE_EFFECT))
		return
	if(self.head && (self.head.item_flags & BLOCK_GAS_SMOKE_EFFECT))
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

		if ((!suit_supply && !contents.Find(internal)) || !((wear_mask && (wear_mask.item_flags & AIRTIGHT)) || (head && (head.item_flags & AIRTIGHT))))
			internal = null

		if(internal)
			return internal.remove_air_volume(volume_needed)
		else if(internals)
			internals.icon_state = "internal0"
	return null


/datum/life_system/breathing/carbon/human/exchange(mob/living/carbon/human/self, datum/gas_mixture/breath)
	if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
		return 0	// Cancelled by a component

	if(mNobreath in self.mutations)
		return

	if(self.suiciding)
		// Holding the breath: nothing is drawn in.
		self.failed_last_breath = 1
		self.body?.set_breath_quality(0)
		self.suiciding--
		return 0

	if(self.wear_mask && (self.wear_mask.item_flags & INFINITE_AIR))
		self.failed_last_breath = 0
		self.body?.set_breath_quality(1)
		return

	if(self.does_not_breathe)
		self.failed_last_breath = 0
		return

	// XGM .total_moles var → LINDA proc. Cache to avoid 12 proc calls.
	var/breath_moles = breath ? breath.total_moles() : 0
	if(!breath || (breath_moles == 0))
		// Nothing to breathe: a closed airway, apnea, or vacuum.
		self.failed_last_breath = 1
		self.body?.set_breath_quality(0)
		self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_atmos)
		return 0
	else
		self.clear_alert("oxy")

	// Minimum safe partial pressure of breathable gas in kPa. Lung damage is
	// the physiology's business (gas exchange), not the air's.
	var/safe_pressure_min = self.species.minimum_breath_pressure
	/// How good this breath is, 0..1, reported to the physiology.
	var/quality = 1

	var/safe_exhaled_max = 10
	var/safe_toxins_min = 0.05
	var/safe_toxins_max = 0.2
	var/SA_para_min = 1
	var/SA_sleep_min = 5
	var/inhaled_gas_used = 0

	var/breath_pressure = (breath_moles*R_IDEAL_GAS_EQUATION*breath.return_temperature())/BREATH_VOLUME

	var/inhaling
	var/poison_toxin
	var/poison_methane
	var/exhaling

	var/breath_type
	var/poison_type
	var/exhale_type

	var/failed_inhale = 0
	var/failed_exhale = 0

	if(self.species.breath_type)
		breath_type = self.species.breath_type
	else
		breath_type = GAS_O2
	inhaling = LINDA_GAS_AMT(breath, breath_type)

	if(self.species.poison_type)
		poison_type = self.species.poison_type
	else
		poison_type = GAS_PHORON
	poison_toxin = LINDA_GAS_AMT(breath, poison_type)

	if(self.species.breath_type != GAS_CH4)
		poison_methane = LINDA_GAS_AMT(breath, GAS_CH4)

	if(self.species.exhale_type)
		exhale_type = self.species.exhale_type
		exhaling = LINDA_GAS_AMT(breath, exhale_type)
	else
		exhaling = 0

	var/inhale_pp = (inhaling/breath_moles)*breath_pressure
	var/toxins_pp = (poison_toxin/breath_moles)*breath_pressure
	var/methane_pp = (poison_methane/breath_moles)*breath_pressure
	// To be clear, this isn't how much they're exhaling -- it's the amount of the species exhale_gas that they just
	var/exhaled_pp = (exhaling/breath_moles)*breath_pressure

	// Not enough to breathe
	if(inhale_pp < safe_pressure_min)
		if(prob(20))
			self.emote("gasp")
		if(is_below_sound_pressure(get_turf(self)))	//No more popped lungs from choking/drowning. You also have ~20 seconds to get internals on before your lungs pop.
			self.rupture_lung(TRUE)

		// Too little of the breath gas: the breath is only as good as its share.
		quality = safe_pressure_min > 0 ? clamp(inhale_pp / safe_pressure_min, 0, 1) : 0
		failed_inhale = 1

		switch(breath_type)
			if(GAS_O2)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_oxy)
			if(GAS_PHORON)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_tox)
			if(GAS_N2)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_nitro)
			if(GAS_CO2)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_co2)
			if(GAS_CH4)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_methane)
			if(GAS_VOLATILE_FUEL)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_fuel)
			if(GAS_N2O)
				self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_n2o)

	else
		// We're in safe limits
		self.clear_alert("oxy")

	inhaled_gas_used = inhaling/6

	breath.adjust_gas(breath_type, -inhaled_gas_used, update = 0) //update afterwards

	if(exhale_type)
		breath.adjust_gas_temp(exhale_type, inhaled_gas_used, self.bodytemperature, update = 0) //update afterwards

		// Too much exhaled gas in the air
		if(exhaled_pp > safe_exhaled_max)
			if (prob(15))
				var/word = pick("extremely dizzy","short of breath","faint","confused")
				to_chat(self, span_danger("You feel [word]."))

			// Hypercapnia: the exhaled gas crowds out the breath.
			quality *= 0.4
			failed_exhale = 1

		else if(exhaled_pp > safe_exhaled_max * 0.7)
			if (!prob(1))
				var/word = pick("dizzy","short of breath","faint","momentarily confused")
				to_chat(self, span_warning("You feel [word]."))

			//scale linearly from 0 to 1 between safe_exhaled_max and safe_exhaled_max*0.7
			var/ratio = 1.0 - (safe_exhaled_max - exhaled_pp)/(safe_exhaled_max*0.3)

			// Mild hypercapnia: the breath worsens as the exhaled gas nears its limit.
			quality *= 1 - 0.5 * ratio
			failed_exhale = 1

		else if(exhaled_pp > safe_exhaled_max * 0.6)
			if(prob(0.3))
				var/word = pick("a little dizzy","short of breath")
				to_chat(self, span_warning("You feel [word]."))

	// Too much phoron in the air.
	if(toxins_pp > safe_toxins_min)
		var/SA_pp = (LINDA_GAS_AMT(breath, GAS_PHORON) / breath_moles) * breath_pressure
		if(SA_pp > 0.05)
			if(prob(3))
				to_chat(self,span_warning("Something burns as you breathe."))
	if(toxins_pp > safe_toxins_max)
		var/ratio = (poison_toxin/safe_toxins_max) * 10
		if(self.reagents)
			self.reagents.add_reagent(REAGENT_ID_TOXIN, CLAMP(ratio, MIN_TOXIN_DAMAGE, MAX_TOXIN_DAMAGE))
			breath.adjust_gas(poison_type, -poison_toxin/6, update = 0) //update after
		self.throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)
	else
		self.clear_alert("tox_in_air")

	// Too much methane in the air
	if(methane_pp > safe_toxins_min)
		var/SA_pp = (LINDA_GAS_AMT(breath, GAS_CH4) / breath_moles) * breath_pressure
		if(SA_pp > 0.05)
			if(prob(5))
				to_chat(self,span_warning("You smell rotten eggs."))
	if(methane_pp > safe_toxins_max)
		// Methane displaces the breath: slow suffocation.
		quality *= 1 - clamp(methane_pp / (safe_toxins_max * 20), 0.1, 0.8)
		if(prob(20))
			self.emote("gasp")
		breath.adjust_gas(GAS_CH4, -poison_methane/6, update = 0) // update after // removed duplicate line; poison_methane already equals LINDA_GAS_AMT(breath, GAS_CH4) from line 608
		self.throw_alert("methane_in_air", /atom/movable/screen/alert/methane_in_air)
	else
		self.clear_alert("methane_in_air")

	// If there's some other shit in the air lets deal with it here.
	if(LINDA_GAS_AMT(breath, GAS_N2O))
		var/SA_pp = (LINDA_GAS_AMT(breath, GAS_N2O) / breath_moles) * breath_pressure

		// Enough to make us paralysed for a bit
		if(SA_pp > SA_para_min)

			// 3 gives them one second to wake up and run away a bit!
			self.Paralyse(3)
			self.Sleeping(1)

			// Enough to make us sleep as well
			if(SA_pp > SA_sleep_min)
				self.Sleeping(5)

		// There is sleeping gas in their lungs, but only a little, so give them a bit of a warning
		else if(SA_pp > 0.15)
			if(prob(20))
				self.emote(pick("giggle", "laugh"))
		breath.adjust_gas(GAS_N2O, -LINDA_GAS_AMT(breath, GAS_N2O)/6, update = 0) //update after

	if(self.get_hallucination_component()?.get_hud_state() == HUD_HALLUCINATION_OXY)
		self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_atmos)
	else if(self.get_hallucination_component()?.get_hud_state() == HUD_HALLUCINATION_TOXIN)
		self.throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)

	// Were we able to breathe?
	self.failed_last_breath = (failed_inhale || failed_exhale) ? 1 : 0
	self.body?.set_breath_quality(quality)

	if(!self.does_not_breathe && self.client) // If we breathe, and have an active client, check if we have synthetic lungs.
		var/obj/item/organ/internal/lungs/L = self.internal_organs_by_name[O_LUNGS]
		var/turf = get_turf(self)
		var/mob/living/carbon/human/M = self
		if(L && L.robotic < ORGAN_ROBOT && is_below_sound_pressure(turf) && M.internal) // Only non-synthetic lungs, please, and only play these while the pressure is below that which we can hear sounds normally AND we're on internals.
			if(!failed_inhale && (world.time >= (self.last_breath_sound + 7 SECONDS))) // Were we able to inhale successfully? Play inhale.
				var/exhale = failed_exhale // Pass through if we passed exhale or not
				self.play_inhale(M, exhale)
				self.last_breath_sound = world.time


	// Hot air hurts :(
	if(!isbelly(self.loc)) //None of this happens anyway whilst inside of a belly, belly temperatures are all handled as body temperature
		var/breath_temperature = breath.return_temperature()
		if((breath_temperature <= self.species.cold_discomfort_level || breath_temperature >= self.species.heat_discomfort_level) && !(COLD_RESISTANCE in self.mutations))

			if(breath_temperature <= self.species.breath_cold_level_1)
				if(prob(20))
					to_chat(self, span_danger("You feel your face freezing and icicles forming in your lungs!"))
			else if(breath_temperature >= self.species.breath_heat_level_1)
				if(prob(20))
					to_chat(self, span_danger("You feel your face burning and a searing heat in your lungs!"))

			if(breath_temperature >= self.species.heat_discomfort_level)

				if(breath_temperature >= self.species.breath_heat_level_3)
					self.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_3, BP_HEAD)
					self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
				else if(breath_temperature >= self.species.breath_heat_level_2)
					self.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_2, BP_HEAD)
					self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MODERATE)
				else if(breath_temperature >= self.species.breath_heat_level_1)
					self.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_1, BP_HEAD)
					self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_LOW)
				else if(self.species.get_environment_discomfort(self, ENVIRONMENT_COMFORT_MARKER_HOT))
					self.throw_alert("temp", /atom/movable/screen/alert/warm, HOT_ALERT_SEVERITY_LOW)
				else
					self.clear_alert("temp")

			else if(breath_temperature <= self.species.cold_discomfort_level)

				if(breath_temperature <= self.species.breath_cold_level_3)
					self.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_3, BP_HEAD)
					self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
				else if(breath_temperature <= self.species.breath_cold_level_2)
					self.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_2, BP_HEAD)
					self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MODERATE)
				else if(breath_temperature <= self.species.breath_cold_level_1)
					self.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_1, BP_HEAD)
					self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_LOW)
				else if(self.species.get_environment_discomfort(self, ENVIRONMENT_COMFORT_MARKER_COLD))
					self.throw_alert("temp", /atom/movable/screen/alert/chilly, COLD_ALERT_SEVERITY_LOW)
				else
					self.clear_alert("temp")

			//breathing in hot/cold air also heats/cools you a bit
			var/temp_adj = breath_temperature - self.bodytemperature
			if (temp_adj < 0)
				temp_adj /= (BODYTEMP_COLD_DIVISOR * 5)	//don't raise temperature as much as if we were directly exposed
			else
				temp_adj /= (BODYTEMP_HEAT_DIVISOR * 5)	//don't raise temperature as much as if we were directly exposed

			var/relative_density = breath_moles / (MOLES_CELLSTANDARD * BREATH_PERCENTAGE)
			temp_adj *= relative_density

			if(temp_adj > BODYTEMP_HEATING_MAX)
				temp_adj = BODYTEMP_HEATING_MAX
			if(temp_adj < BODYTEMP_COOLING_MAX)
				temp_adj = BODYTEMP_COOLING_MAX

			self.bodytemperature += temp_adj

		else
			self.clear_alert("temp")

	// breath.update_values() removed; no-op under LINDA.
	return 1

/mob/living/carbon/human/proc/play_inhale(mob/living/M, exhale)
	var/suit_inhale_sound
	if(species.suit_inhale_sound)
		suit_inhale_sound = species.suit_inhale_sound
	else // Failsafe
		suit_inhale_sound = 'sound/effects/mob_effects/suit_breathe_in.ogg'

	playsound_local(get_turf(src), suit_inhale_sound, 100, pressure_affected = FALSE, volume_channel = VOLUME_CHANNEL_AMBIENCE)
	if(!exhale) // Did we fail exhale? If no, play it after inhale finishes.
		addtimer(CALLBACK(src, PROC_REF(play_exhale), M), 5 SECONDS)

/mob/living/carbon/human/proc/play_exhale(mob/living/M)
	var/suit_exhale_sound
	if(species.suit_exhale_sound)
		suit_exhale_sound = species.suit_exhale_sound
	else // Failsafe
		suit_exhale_sound = 'sound/effects/mob_effects/suit_breathe_out.ogg'

	playsound_local(get_turf(src), suit_exhale_sound, 100, pressure_affected = FALSE, volume_channel = VOLUME_CHANNEL_AMBIENCE)

/datum/life_system/species_components
	name = "species components"
	bit = LIFE_SYS_TRAITS
	phase = LIFE_PHASE_TAIL
	order = 290
	mob_type = /mob/living/carbon/human

/// Species components (xenochimera, shadekin). Not stat checked: those check in their own code.
/datum/life_system/species_components/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	//Xenochimera Species Component
	var/datum/component/xenochimera/xc = self.get_xenochimera_component()
	if(xc)
		if(!self.stat || !(xc.revive_ready == REVIVING_NOW || xc.revive_ready == REVIVING_DONE))
			SEND_SIGNAL(self, COMSIG_XENOCHIMERA_COMPONENT)

	//Shadekin Species Component.
	//For when shadekin actually have their component control everything.
	var/datum/component/shadekin/sk = self.get_shadekin_component()
	if(sk)
		if(!self.stat)
			SEND_SIGNAL(self, COMSIG_SHADEKIN_COMPONENT)

/datum/life_system/environment/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/environment/carbon/human/exchange(mob/living/carbon/human/self, datum/gas_mixture/environment)
	if(!environment)
		return

	if(self.is_incorporeal()) //Not in this plane of existance right now, tbh.
		return

	//Stuff like the xenomorph's plasma regen happens here.
	self.species.environment_effects(self)

	//Moved pressure calculations here for use in skip-processing check.
	var/pressure = environment.return_pressure()
	var/adjusted_pressure = self.calculate_affecting_pressure(pressure)

	// phoron contamination is offline under LINDA (no contamination
	// flags/limits on GLOB.gas_data, the env.gas dict shape changed, and
	// pl_effects is a no-op). Loop disabled until LINDA contamination is wired.

	if(istype(self.loc, /turf/space)) //No FBPs overheating on space turfs inside mechs or people.
		//Don't bother if the temperature drop is less than 0.1 anyways. Hopefully BYOND is smart enough to turn this constant expression into a constant
		if(self.bodytemperature > (0.1 * HUMAN_HEAT_CAPACITY/(HUMAN_EXPOSED_SURFACE_AREA*STEFAN_BOLTZMANN_CONSTANT))**(1/4) + COSMIC_RADIATION_TEMPERATURE)
			//Thermal radiation into space
			var/heat_loss = HUMAN_EXPOSED_SURFACE_AREA * STEFAN_BOLTZMANN_CONSTANT * ((self.bodytemperature - COSMIC_RADIATION_TEMPERATURE)**4)
			var/temperature_loss = heat_loss/HUMAN_HEAT_CAPACITY
			self.bodytemperature -= temperature_loss
	else
		var/loc_temp = T0C
		if(istype(self.loc, /obj/mecha))
			var/obj/mecha/M = self.loc
			loc_temp =  M.get_interior_temperature()
		else if(istype(self.loc, /obj/machinery/atmospherics/unary/cryo_cell))
			var/obj/machinery/atmospherics/unary/cryo_cell/cc = self.loc
			loc_temp = cc.air_contents.return_temperature()
		else if(isbelly(self.loc))
			var/obj/belly/b = self.loc
			if(self.allowtemp)
				loc_temp = b.bellytemperature
			else
				loc_temp = self.species.body_temperature //Should be safe for just about anyone
		else
			loc_temp = environment.return_temperature()

		if(adjusted_pressure < self.species.warning_high_pressure && adjusted_pressure > self.species.warning_low_pressure && abs(loc_temp - self.bodytemperature) < 20 && self.bodytemperature < self.species.heat_level_1 && self.bodytemperature > self.species.cold_level_1 && (!isbelly(self.loc) || !self.allowtemp))
			self.clear_alert("pressure")
			return // Temperatures are within normal ranges, fuck all this processing. ~Ccomp

		//Body temperature adjusts depending on surrounding atmosphere based on your thermal protection (convection)
		var/temp_adj = 0
		if(loc_temp < self.bodytemperature)			//Place is colder than we are
			var/thermal_protection = self.get_cold_protection(loc_temp) //This returns a 0 - 1 value, which corresponds to the percentage of protection based on what you're wearing and what you're exposed to.
			if(thermal_protection < 0.99)	//For some reason, < 1 returns false if the value is 1.
				temp_adj = (1-thermal_protection) * ((loc_temp - self.bodytemperature) / BODYTEMP_COLD_DIVISOR)	//this will be negative
		else if (loc_temp > self.bodytemperature)			//Place is hotter than we are
			var/thermal_protection = self.get_heat_protection(loc_temp) //This returns a 0 - 1 value, which corresponds to the percentage of protection based on what you're wearing and what you're exposed to.
			if(thermal_protection < 0.99)	//For some reason, < 1 returns false if the value is 1.
				temp_adj = (1-thermal_protection) * ((loc_temp - self.bodytemperature) / BODYTEMP_HEAT_DIVISOR)

		//Use heat transfer as proportional to the gas density. However, we only care about the relative density vs standard 101 kPa/20 C air. Therefore we can use mole ratios
		var/relative_density = environment.total_moles() / MOLES_CELLSTANDARD // XGM var → LINDA proc
		self.bodytemperature += between(BODYTEMP_COOLING_MAX, temp_adj*relative_density, BODYTEMP_HEATING_MAX)

	if(isbelly(self.loc) && self.allowtemp)
		var/obj/belly/b = self.loc
		if(b.bellytemperature >= self.species.heat_discomfort_level) //A bit more easily triggered than normal, intentionally
			var/heat_dam = 0
			if(b.bellytemperature >= self.species.heat_level_1)
				if(b.bellytemperature >= self.species.heat_level_2)
					if(b.bellytemperature >= self.species.heat_level_3)
						heat_dam = HEAT_DAMAGE_LEVEL_3
						self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
					else
						heat_dam = HEAT_DAMAGE_LEVEL_2
						self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MODERATE)
				else
					heat_dam = HEAT_DAMAGE_LEVEL_1
					self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_LOW)
			else
				self.throw_alert("temp", /atom/movable/screen/alert/warm, HOT_ALERT_SEVERITY_LOW)
			if(self.digestable && b.temperature_damage)
				self.injure(INJURY_BURN, heat_dam) // High body temperature
		else if(b.bellytemperature <= self.species.cold_discomfort_level)
			var/cold_dam = 0
			if(b.bellytemperature <= self.species.cold_level_1)
				if(b.bellytemperature <= self.species.cold_level_2)
					if(b.bellytemperature <= self.species.cold_level_3)
						cold_dam = COLD_DAMAGE_LEVEL_3
						self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
					else
						cold_dam = COLD_DAMAGE_LEVEL_2
						self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MODERATE)
				else
					cold_dam = COLD_DAMAGE_LEVEL_1
					self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_LOW)
			else
				self.throw_alert("temp", /atom/movable/screen/alert/chilly, COLD_ALERT_SEVERITY_LOW)
			if(self.digestable && b.temperature_damage)
				self.injure(INJURY_FROSTBITE, cold_dam) // Low body temperature
		else self.clear_alert("temp")

	// +/- 50 degrees from 310.15K is the 'safe' zone, where no damage is dealt.
	else if(self.bodytemperature >= self.species.heat_discomfort_level)
		//Body temperature is too hot.
		if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
			return 1	// Cancelled by a component

		var/heat_dam = 0

		// switch() can't access numbers inside variables, so we need to use some ugly if() spam ladder.
		if(self.bodytemperature >= self.species.heat_level_1)
			if(self.bodytemperature >= self.species.heat_level_2)
				if(self.bodytemperature >= self.species.heat_level_3)
					heat_dam = HEAT_DAMAGE_LEVEL_3
					self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
				else
					heat_dam = HEAT_DAMAGE_LEVEL_2
					self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MODERATE)
			else
				heat_dam = HEAT_DAMAGE_LEVEL_1
				self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_LOW)

		self.injure(INJURY_BURN, heat_dam) // High body temperature

	else if(self.bodytemperature <= self.species.cold_discomfort_level)
		//Body temperature is too cold.

		if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
			return 1	// Cancelled by a component


		if(!istype(self.loc, /obj/machinery/atmospherics/unary/cryo_cell))
			var/cold_dam = 0
			if(self.bodytemperature <= self.species.cold_level_1)
				if(self.bodytemperature <= self.species.cold_level_2)
					if(self.bodytemperature <= self.species.cold_level_3)
						cold_dam = COLD_DAMAGE_LEVEL_3
					else
						cold_dam = COLD_DAMAGE_LEVEL_2
				else
					cold_dam = COLD_DAMAGE_LEVEL_1

			self.injure(INJURY_FROSTBITE, cold_dam) // Low body temperature

	else self.clear_alert("temp")

	// Account for massive pressure differences.  Done by Polymorph
	// Made it possible to actually have something that can protect against high pressure... Done by Errorage. Polymorph now has an axe sticking from his head for his previous hardcoded nonsense!
	if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
		return 1	// Cancelled by a component

	if(adjusted_pressure >= self.species.hazard_high_pressure)
		var/pressure_damage = min( ( (adjusted_pressure / self.species.hazard_high_pressure) -1 )*PRESSURE_DAMAGE_COEFFICIENT , MAX_HIGH_PRESSURE_DAMAGE)
		if(self.stat == DEAD)
			pressure_damage = pressure_damage/2
		if(!istype(self.loc, /obj/structure/closet/body_bag/cryobag))
			self.injure(INJURY_BLUNT, pressure_damage) // Crushing pressure
		self.throw_alert("pressure", /atom/movable/screen/alert/highpressure, 2)
	else if(adjusted_pressure >= self.species.warning_high_pressure)
		self.throw_alert("pressure", /atom/movable/screen/alert/highpressure, 1)
	else if(adjusted_pressure >= self.species.warning_low_pressure)
		self.clear_alert("pressure")
	else if(adjusted_pressure >= self.species.hazard_low_pressure)
		self.throw_alert("pressure", /atom/movable/screen/alert/lowpressure, 1)
	else
		if(!(COLD_RESISTANCE in self.mutations) && !istype(self.loc, /obj/structure/closet/body_bag/cryobag))
			if(!self.isSynthetic() || !self.nif || !self.nif.flag_check(NIF_O_PRESSURESEAL,NIF_FLAGS_OTHER))
				var/pressure_damage = LOW_PRESSURE_DAMAGE
				if(self.stat==DEAD)
					pressure_damage = pressure_damage/2
				self.injure(INJURY_BLUNT, pressure_damage) // Decompression: ruptured capillaries and tissue
				// Ebullition in the lungs: gas exchange fails even on internals,
				// less the better the suit holds pressure.
				var/exposure = (ONE_ATMOSPHERE - adjusted_pressure) / ONE_ATMOSPHERE
				if(self.wear_suit && self.wear_suit.min_pressure_protection && self.head && self.head.min_pressure_protection)
					exposure *= max(self.wear_suit.min_pressure_protection, self.head.min_pressure_protection) / ONE_ATMOSPHERE
				self.body?.add_restriction(self, BF_GAS_EXCHANGE, clamp(1 - exposure, 0.1, 1), 4 SECONDS)
			self.throw_alert("pressure", /atom/movable/screen/alert/lowpressure, 2)
		else
			self.clear_alert("pressure")

	return

/datum/life_system/thermoregulation
	name = "thermoregulation"
	bit = LIFE_SYS_THERMAL
	phase = LIFE_PHASE_TAIL
	order = 160
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Body temperature adjusts itself (self-regulation).
/datum/life_system/thermoregulation/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	// We produce heat naturally.
	if (self.species.passive_temp_gain)
		self.bodytemperature += self.species.passive_temp_gain
	if (self.species.body_temperature == null)
		return //this species doesn't have metabolic thermoregulation

	// FBPs will overheat when alive, prosthetic limbs are fine.
	if(self.stat != DEAD && self.robobody_count)
		if(!self.nif || !self.nif.flag_check(NIF_O_HEATSINKS,NIF_FLAGS_OTHER))
			self.bodytemperature += round(self.robobody_count*1.15)
		var/obj/item/organ/internal/robotic/heatsink/HS = self.internal_organs_by_name[O_HEATSINK]
		if(!HS || HS.is_broken()) // However, NIF Heatsinks will not compensate for a core FBP component (your heatsink) being lost.
			self.bodytemperature += round(self.robobody_count*0.5)

	var/body_temperature_difference = self.species.body_temperature - self.bodytemperature

	if (abs(body_temperature_difference) < 0.5)
		return //fuck this precision

	if (self.on_fire)
		return //too busy for pesky metabolic regulation

	if(self.bodytemperature < self.species.cold_level_1) //260.15 is 310.15 - 50, the temperature where you start to feel effects.
		if(self.nutrition >= 2) //If we are very, very cold we'll use up quite a bit of nutriment to heat us up.
			self.adjust_nutrition(-2)
		var/recovery_amt = max((body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR), BODYTEMP_AUTORECOVERY_MINIMUM)
		//to_world("Cold. Difference = [body_temperature_difference]. Recovering [recovery_amt]")
		self.bodytemperature += recovery_amt
	else if(self.species.cold_level_1 <= self.bodytemperature && self.bodytemperature <= self.species.heat_level_1)
		var/recovery_amt = body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR
		//to_world("Norm. Difference = [body_temperature_difference]. Recovering [recovery_amt]")
		self.bodytemperature += recovery_amt
	else if(self.bodytemperature > self.species.heat_level_1) //360.15 is 310.15 + 50, the temperature where you start to feel effects.
		//We totally need a sweat system cause it totally makes sense...~
		var/recovery_amt = min((body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR), -BODYTEMP_AUTORECOVERY_MINIMUM)	//We're dealing with negative numbers
		//to_world("Hot. Difference = [body_temperature_difference]. Recovering [recovery_amt]")
		self.bodytemperature += recovery_amt

	//This proc returns a number made up of the flags for body parts which you are protected on. (such as HEAD, UPPER_TORSO, LOWER_TORSO, etc. See setup.dm for the full list)
/mob/living/carbon/human/proc/get_heat_protection_flags(temperature) //Temperature is the temperature you're being exposed to.
	. = 0
	//Handle normal clothing
	for(var/obj/item/clothing/C in list(head,wear_suit,w_uniform,shoes,gloves,wear_mask))
		if(C)
			if(C.handle_high_temperature(temperature))
				. |= C.get_heat_protection_flags()

//See proc/get_heat_protection_flags(temperature) for the description of this proc.
/mob/living/carbon/human/proc/get_cold_protection_flags(temperature)
	. = 0
	//Handle normal clothing
	for(var/obj/item/clothing/C in list(head,wear_suit,w_uniform,shoes,gloves,wear_mask))
		if(C)
			if(C.handle_low_temperature(temperature))
				. |= C.get_cold_protection_flags()

/mob/living/carbon/human/get_heat_protection(temperature) //Temperature is the temperature you're being exposed to.
	var/thermal_protection_flags = get_heat_protection_flags(temperature)

	. = get_thermal_protection(thermal_protection_flags)
	. = 1 - . // Invert from 1 = immunity to 0 = immunity.

	// Body factors stack multiplicatively, so two sources that each let half the heat through combine to a quarter.
	. *= factor(BF_HEAT_EXPOSURE)

	// Code that calls this expects 1 = immunity so we need to invert again.
	. = 1 - .
	. = min(., 1.0)

/mob/living/carbon/human/get_cold_protection(temperature)
	if(COLD_RESISTANCE in mutations)
		return 1 //Fully protected from the cold.

	temperature = max(temperature, 2.7) //There is an occasional bug where the temperature is miscalculated in ares with a small amount of gas on them, so this is necessary to ensure that that bug does not affect this calculation. Space's temperature is 2.7K and most suits that are intended to protect against any cold, protect down to 2.0K.
	var/thermal_protection_flags = get_cold_protection_flags(temperature)

	. = get_thermal_protection(thermal_protection_flags)
	. = 1 - . // Invert from 1 = immunity to 0 = immunity.

	// Body factors stack multiplicatively, so two sources that each let half the cold through combine to a quarter.
	. *= factor(BF_COLD_EXPOSURE)

	// Code that calls this expects 1 = immunity so we need to invert again.
	. = 1 - .
	. = min(., 1.0)

/mob/living/carbon/human/proc/get_thermal_protection(flags)
	.=0
	if(flags)
		if(flags & HEAD)
			. += THERMAL_PROTECTION_HEAD
		if(flags & UPPER_TORSO)
			. += THERMAL_PROTECTION_UPPER_TORSO
		if(flags & LOWER_TORSO)
			. += THERMAL_PROTECTION_LOWER_TORSO
		if(flags & LEG_LEFT)
			. += THERMAL_PROTECTION_LEG_LEFT
		if(flags & LEG_RIGHT)
			. += THERMAL_PROTECTION_LEG_RIGHT
		if(flags & FOOT_LEFT)
			. += THERMAL_PROTECTION_FOOT_LEFT
		if(flags & FOOT_RIGHT)
			. += THERMAL_PROTECTION_FOOT_RIGHT
		if(flags & ARM_LEFT)
			. += THERMAL_PROTECTION_ARM_LEFT
		if(flags & ARM_RIGHT)
			. += THERMAL_PROTECTION_ARM_RIGHT
		if(flags & HAND_LEFT)
			. += THERMAL_PROTECTION_HAND_LEFT
		if(flags & HAND_RIGHT)
			. += THERMAL_PROTECTION_HAND_RIGHT
	return min(1,.)

/datum/life_system/chemicals/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/chemicals/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)

	if(self.inStasisNow())
		return

	if(self.reagents)
		if(self.touching)
			self.touching.metabolize()
		if(self.ingested)
			self.ingested.metabolize()
		if(self.bloodstr)
			self.bloodstr.metabolize()

		// ZAS-era phoron-contamination damage path removed. It read
		// `I.contaminated` (which has no setter under LINDA) and
		// `GLOB.vsc.plc.CONTAMINATION_LOSS` (config holder that's also gone).
		// Whole branch was inert; restore properly if/when contamination
		// machinery is rebuilt on the LINDA gas model.

	if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
		return 0	// Cancelled by a component

	// nutrition decrease
	// Species controls hunger rate for humans, otherwise use defaults
	if(self.nutrition > 0 && self.stat != DEAD)
		var/nutrition_reduction = DEFAULT_HUNGER_FACTOR
		nutrition_reduction = self.species.hunger_factor
		// Metabolism above or below the species' own (hunger_factor already
		// covers the species) raises or lowers nutrition cost.
		var/species_metabolism = self.species.baseline_factor(BF_METABOLISM)
		if(species_metabolism > 0)
			nutrition_reduction *= self.factor(BF_METABOLISM) / species_metabolism
		var/datum/component/nutrition_size_change/comp = self.GetComponent(/datum/component/nutrition_size_change)
		if(comp)
			nutrition_reduction *= comp.get_nutrition_multiplier()
		self.adjust_nutrition(-nutrition_reduction)

	if(self.noisy == TRUE && self.nutrition < 250 && prob(10))
		var/sound/growlsound = sound(get_sfx("hunger_sounds"))
		var/growlmultiplier = 100 - (self.nutrition / 250 * 100)
		playsound(self, growlsound, vol = growlmultiplier, vary = 1, falloff = 0.1, ignore_walls = TRUE, preference = /datum/preference/toggle/digestion_noises)
	if(self.nutrition > 500 && self.noisy_full == TRUE)
		var/belch_prob = 5 //Maximum belch prob.
		if(self.nutrition < 4075)
			belch_prob = ((self.nutrition-500)/3575)*5 //Scale belch prob with fullness if not already at max. If editing make sure the multiplier matches the max prob above.
		if(prob(belch_prob))
			self.emote("belch")
	if(self.factor(BF_DARKSIGHT) && self.chemical_darksight == 0)
		self.recalculate_vis()
		self.chemical_darksight = 1
	if(!self.factor(BF_DARKSIGHT) && self.chemical_darksight == 1)
		self.recalculate_vis()
		self.chemical_darksight = 0

	// TODO: stomach and bloodstream organ.
	if(!self.isSynthetic())
		self.handle_trace_chems()

	return

//DO NOT run the statuses system from this proc: it runs after this one as long as this returns a true value.
/datum/life_system/status/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/status/carbon/human/update_status(mob/living/carbon/human/self)

	if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
		return 0	// Cancelled by a component

	//SSD check, if a logged player is awake put them back to sleep!
	if(self.species.get_ssd(self) && !self.client && !self.teleop)
		self.Sleeping(2)
	if(self.stat == DEAD)	//DEAD. BROWN BREAD. SWIMMING WITH THE SPESS CARP
		self.blinded = 1
		self.silent = 0
		self.deaf_loop.stop() // CHOMPEnable: Ear Ringing/Deafness - Not sure if we need this, but, safety.
	else				//ALIVE. LIGHTS ARE ON
		// The body ticks afflictions, recomputes vitals once, and applies
		// death (organ death) and unconsciousness (consciousness model).
		self.body.life_tick()

		if(self.stat == DEAD)
			self.blinded = 1
			self.silent = 0
			self.deaf_loop.stop() // CHOMPEnable: Ear Ringing/Deafness - Not sure if we need this, but, safety.
			return 1

		//UNCONSCIOUS. NO-ONE IS HOME
		var/in_crit = FALSE
		if(self.body.is_unconscious())
			self.Paralyse(3)
			self.Sleeping(3)
			self.set_stat(UNCONSCIOUS)
			self.blinded = TRUE
			in_crit = TRUE
			if(!HAS_TRAIT(self, TRAIT_CRITICAL_CONDITION))
				ADD_TRAIT(self, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)

		if(self.hallucination)
			if(self.hallucination >= HALLUCINATION_THRESHOLD && !(self.species.flags & (NO_POISON|IS_PLANT|NO_HALLUCINATION)) && !HAS_TRAIT(self, TRAIT_MADNESS_IMMUNE))
				self.handle_hallucinations()
				/* Stop spinning the view, it breaks too much.
				if(client && prob(5))
					client.dir = pick(2,4,8)
					spawn(rand(20,50))
						client.dir = 1
				*/
			self.hallucination = max(0, self.hallucination - 2)



		if(self.tiredness) //tiredness for vore drain
			self.tiredness = (self.tiredness - 1)
			if(self.tiredness >= 100)
				self.Sleeping(5)

		if(self.fear)
			self.fear = (self.fear - 1)
			if(self.fear >= 80 && self.client?.prefs?.read_preference(/datum/preference/toggle/play_ambience))
				if(self.last_fear_sound + 51 SECONDS <= world.time)
					self << sound('sound/effects/Heart Beat.ogg',0,0,0,25)
					self.last_fear_sound = world.time
			if(self.fear >= 80 && !self.isSynthetic())
				if(prob(1) && self.get_active_hand())
					var/stuff_to_drop = self.get_active_hand()
					self.drop_item()
					self.visible_message(span_notice("\The [self] suddenly drops their [stuff_to_drop]."),span_warning("You drop your [stuff_to_drop]!"))
				if(prob(5))
					var/fear_self = pick(self.fear_message_self)
					var/fear_other = pick(self.fear_message_other)
					self.visible_message(span_notice("\The [self][fear_other]"),span_warning("[fear_self]"))
			else if(self.fear >= 30 && !self.isSynthetic())
				if(prob(2))
					var/fear_self = pick(self.fear_message_self)
					var/fear_other = pick(self.fear_message_other)
					self.visible_message(span_notice("\The [self][fear_other]"),span_warning("[fear_self]"))

		if(self.sleeping)
			self.blinded = TRUE
			self.set_stat(UNCONSCIOUS)
			self.animate_tail_reset()
			self.mend(TREAT_ANALGESIC, 3) // Sleep eases pain on top of its natural fading.

			if(self.sleeping)
				if(prob(2))
					if(prob(50))
						self.mend(TREAT_TISSUE_REPAIR, 1)
					else
						self.mend(TREAT_BURN_CARE, 1)

				self.handle_dreams()
				if(self.mind)
					//Are they SSD? If so we'll keep them asleep but work off some of that sleep var in case of stoxin or similar.
					if(self.client || self.sleeping > 3)
						life_statuses().sleeping(self)
				if(prob(2) && !self.is_critical() && !self.get_hallucination_component()?.get_fakecrit() && self.client)
					self.emote("snore")
		//CONSCIOUS
		else if(!in_crit)
			self.set_stat(CONSCIOUS)
			self.clear_alert("asleep")
			if(HAS_TRAIT(self, TRAIT_CRITICAL_CONDITION))
				REMOVE_TRAIT(self, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)

		//Periodically double-check embedded_flag
		if(self.embedded_flag && !(self.life_tick % 10))
			var/list/E
			E = self.get_visible_implants(0)
			if(!E.len)
				self.embedded_flag = 0

		//Eyes
		//Check rig first because it's two-check and other checks will override it.
		if(istype(self.back,/obj/item/rig))
			var/obj/item/rig/O = self.back
			if(O.helmet && O.helmet == self.head && (O.helmet.body_parts_covered & EYES))
				if((O.offline && O.offline_vision_restriction == 2) || (!O.offline && O.vision_restriction == 2))
					self.blinded = 1

		// Check everything else.

		//Periodically double-check embedded_flag
		if(self.embedded_flag && !(self.life_tick % 10))
			if(!self.embedded_needs_process())
				self.embedded_flag = 0
		//Vision
		var/obj/item/organ/vision
		if(self.species.vision_organ)
			vision = self.internal_organs_by_name[self.species.vision_organ]

		if(!self.species.vision_organ) // Presumably if a species has no vision organs, they see via some other means.
			self.SetBlinded(0)
			self.blinded =    0
			self.eye_blurry = 0
			self.clear_alert("blind")
		else if(!vision || vision.is_broken())   // Vision organs cut out or broken? Permablind.
			self.SetBlinded(1)
			self.blinded =    1
			self.eye_blurry = 1
			self.throw_alert("blind", /atom/movable/screen/alert/blind)
		else //You have the requisite organs
			if(self.sdisabilities & BLIND) 	// Disabled-blind, doesn't get better on its own
				self.blinded =    1
				self.throw_alert("blind", /atom/movable/screen/alert/blind)
			else if(self.eye_blind)		  	// Blindness, heals slowly over time
				self.AdjustBlinded(-1)
				self.blinded =    1
				self.throw_alert("blind", /atom/movable/screen/alert/blind)
			else if(istype(self.glasses, /obj/item/clothing/glasses/sunglasses/blindfold))	//resting your eyes with a blindfold heals blurry eyes faster
				self.eye_blurry = max(self.eye_blurry-3, 0)
				self.blinded =    1
				self.throw_alert("blind", /atom/movable/screen/alert/blind)

			//blurry sight
			if(vision.is_bruised())   // Vision organs impaired? Permablurry.
				self.eye_blurry = 1
			if(self.eye_blurry)	           // Blurry eyes heal slowly
				self.eye_blurry = max(self.eye_blurry-1, 0)

		//Ears
		if(self.sdisabilities & DEAF)	//disabled-deaf, doesn't get better on its own
			self.ear_deaf = max(self.ear_deaf, 1)
			self.deaf_loop.start(skip_start_sound = TRUE) // CHOMPEnable: Ear Ringing/Deafness
		else if(self.ear_deaf)			//deafness, heals slowly over time
			self.ear_deaf = max(self.ear_deaf-1, 0)
		else if(self.get_ear_protection() >= 2)	//resting your ears with earmuffs heals ear damage faster
			self.ear_damage = max(self.ear_damage-0.15, 0)
			self.ear_deaf = max(self.ear_deaf, 1)
		else if(self.ear_damage < 25)	//ear damage heals slowly under this threshold. otherwise you'll need earmuffs
			self.ear_damage = max(self.ear_damage-0.05, 0)

		// CHOMPEnable Start: Handle Ear ringing, standalone safety check.
		if(self.ear_deaf <= 0)
			self.deaf_loop.stop()
		// CHOMPEnable End

		//Resting eases pain faster than it fades on its own.
		if(self.resting)
			self.mend(TREAT_ANALGESIC, 2)

		if (self.drowsyness)
			self.drowsyness = max(0, self.drowsyness - 1)
			self.eye_blurry = max(2, self.eye_blurry)
			if (prob(5))
				self.Sleeping(1)
				self.Paralyse(5)

		// If you're dirty, your gloves will become dirty, too.
		if(self.gloves && self.germ_level > self.gloves.germ_level && prob(10))
			self.gloves.germ_level += 1

	return 1

/mob/living/carbon/human/set_stat(new_stat)
	. = ..()
	if(. && stat)
		update_skin(1)

/datum/life_system/hud/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/hud/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(self.hud_updateflag) // update our mob's hud overlays, AKA what others see flaoting above our head
		hud_list(self)

	// now handle what we see on our screen
	. = ..()
	if(!.)
		return

	self.client.screen.Remove(GLOB.global_hud.blurry, GLOB.global_hud.druggy, GLOB.global_hud.vimpaired, GLOB.global_hud.darkMask, GLOB.global_hud.nvg, GLOB.global_hud.thermal, GLOB.global_hud.meson, GLOB.global_hud.science, GLOB.global_hud.material, GLOB.global_hud.whitense, GLOB.global_hud.heavy_whitense)

	if(istype(self.client.eye,/obj/machinery/camera))
		var/obj/machinery/camera/cam = self.client.eye
		if(LAZYLEN(cam.client_huds))
			self.client.screen |= cam.client_huds

	if(self.stat == DEAD) //Dead
		if(!self.druggy)		self.see_invisible = SEE_INVISIBLE_LEVEL_TWO

	else if(self.is_critical()) //Crit
		//Critical damage passage overlay, deeper as vitality drains (0 at the crit line, -100 at the end).
		var/severity = 0
		switch(100 * (2 * self.vitality() - 1))
			if(-20 to -10)			severity = 1
			if(-30 to -20)			severity = 2
			if(-40 to -30)			severity = 3
			if(-50 to -40)			severity = 4
			if(-60 to -50)			severity = 5
			if(-70 to -60)			severity = 6
			if(-80 to -70)			severity = 7
			if(-90 to -80)			severity = 8
			if(-95 to -90)			severity = 9
			if(-INFINITY to -95)	severity = 10
		self.overlay_fullscreen("crit", /atom/movable/screen/fullscreen/crit, severity)
	else //Alive
		self.clear_fullscreen("crit")
		//Oxygen debt overlay
		var/debt = self.oxygen_debt()
		if(debt)
			var/severity = 0
			switch(debt)
				if(10 to 20)		severity = 1
				if(20 to 25)		severity = 2
				if(25 to 30)		severity = 3
				if(30 to 35)		severity = 4
				if(35 to 40)		severity = 5
				if(40 to 45)		severity = 6
				if(45 to INFINITY)	severity = 7
			self.overlay_fullscreen("oxy", /atom/movable/screen/fullscreen/oxy, severity)
		else
			self.clear_fullscreen("oxy")

		//Fire and Brute damage overlay (BSSR)
		var/hurtdamage = self.injury_load(INJURY_CATEGORY_PHYSICAL) + self.injury_load(INJURY_CATEGORY_THERMAL) + self.damageoverlaytemp
		self.damageoverlaytemp = 0 // We do this so we can detect if someone hits us or not.
		if(hurtdamage)
			var/severity = 0
			switch(hurtdamage)
				if(10 to 25)		severity = 1
				if(25 to 40)		severity = 2
				if(40 to 55)		severity = 3
				if(55 to 70)		severity = 4
				if(70 to 85)		severity = 5
				if(85 to INFINITY)	severity = 6
			self.overlay_fullscreen("brute", /atom/movable/screen/fullscreen/brute, severity)
		else
			self.clear_fullscreen("brute")

		//tiredness for drain vore
		if(self.tiredness)
			var/severity = 0
			switch(self.tiredness)
				if(10 to 20)		severity = 1
				if(20 to 30)		severity = 2
				if(30 to 45)		severity = 3
				if(45 to 60)		severity = 4
				if(60 to 75)		severity = 5
				if(75 to 90)		severity = 6
				if(90 to INFINITY)	severity = 7
			self.overlay_fullscreen("tired", /atom/movable/screen/fullscreen/oxy, severity)
		else
			self.clear_fullscreen("tired")

		if(self.fear)
			var/severity = 0
			switch(self.fear)
				if(10 to 20)		severity = 1
				if(20 to 30)		severity = 2
				if(30 to 50)		severity = 3
				if(50 to 70)		severity = 4
				if(70 to 90)		severity = 5
				if(90 to INFINITY)	severity = 6
			self.overlay_fullscreen("fear", /atom/movable/screen/fullscreen/fear, severity)
		else
			self.clear_fullscreen("fear")


		var/fat_alert = /atom/movable/screen/alert/fat
		var/hungry_alert = /atom/movable/screen/alert/hungry
		var/starving_alert = /atom/movable/screen/alert/starving

		if(self.isSynthetic())
			fat_alert = /atom/movable/screen/alert/fat/synth
			hungry_alert = /atom/movable/screen/alert/hungry/synth
			starving_alert = /atom/movable/screen/alert/starving/synth
		else if(self.get_species() in list(SPECIES_CUSTOM, SPECIES_HANNER))
			var/datum/species/custom/C = self.species
			if(/datum/trait/neutral/bloodsucker in C.traits)
				fat_alert = /atom/movable/screen/alert/fat/vampire
				hungry_alert = /atom/movable/screen/alert/hungry/vampire
				starving_alert = /atom/movable/screen/alert/starving/vampire

		switch(self.nutrition)
			if(450 to INFINITY)
				self.throw_alert("nutrition", fat_alert)
			// if(350 to 450)
			// if(250 to 350) // Alternative more-detailed tiers, not used.
			if(250 to 450)
				self.clear_alert("nutrition")
			if(150 to 250)
				self.throw_alert("nutrition", hungry_alert)
			else
				self.throw_alert("nutrition", starving_alert)

		if(self.blinded)
			self.overlay_fullscreen("blind", /atom/movable/screen/fullscreen/blind)
			self.throw_alert("blind", /atom/movable/screen/alert/blind)
		else
			self.clear_fullscreen("blind")
			self.clear_alert("blind")

		var/apply_nearsighted_overlay = FALSE
		if(self.disabilities & NEARSIGHTED)
			apply_nearsighted_overlay = TRUE

			if(self.glasses)
				var/obj/item/clothing/glasses/G = self.glasses
				if(G.prescription)
					apply_nearsighted_overlay = FALSE

			if(self.nif && self.nif.flag_check(NIF_V_CORRECTIVE, NIF_FLAGS_VISION))
				apply_nearsighted_overlay = FALSE

		self.set_fullscreen(apply_nearsighted_overlay, "nearsighted", /atom/movable/screen/fullscreen/impaired, 1)

		self.set_fullscreen(self.eye_blurry, "blurry", /atom/movable/screen/fullscreen/blurry)
		self.set_fullscreen(self.druggy, "high", /atom/movable/screen/fullscreen/high)
		if(self.druggy)
			self.throw_alert("high", /atom/movable/screen/alert/high)
		else
			self.clear_alert("high")

		if(!self.surrounding_belly() && !self.previewing_belly) // Belly fullscreens safety
			self.clear_fullscreen("belly")
			self.belly_overlay_tgui?.hide() // hide TGUI belly overlay

		if(CONFIG_GET(flag/welder_vision))
			var/found_welder
			if(self.species.short_sighted)
				found_welder = 1
			else
				if(istype(self.glasses, /obj/item/clothing/glasses/welding))
					var/obj/item/clothing/glasses/welding/O = self.glasses
					if(!O.up)
						found_welder = 1
				if(!found_welder && self.nif && self.nif.flag_check(NIF_V_UVFILTER,NIF_FLAGS_VISION))	found_welder = 1
				if(istype(self.glasses, /obj/item/clothing/glasses/sunglasses/thinblindfold))
					found_welder = 1
				if(!found_welder && istype(self.head, /obj/item/clothing/head/welding))
					var/obj/item/clothing/head/welding/O = self.head
					if(!O.up)
						found_welder = 1
				if(!found_welder && istype(self.back, /obj/item/rig))
					var/obj/item/rig/O = self.back
					if(O.helmet && O.helmet == self.head && (O.helmet.body_parts_covered & EYES))
						if((O.offline && O.offline_vision_restriction == 1) || (!O.offline && O.vision_restriction == 1))
							found_welder = 1
				if(self.absorbed) found_welder = 1
			if(found_welder)
				self.client.screen |= GLOB.global_hud.darkMask

/// Pain as a fraction of the pain that knocks this body out (1 = passing
/// out from pain). Drives the HUD's softcrit / hardcrit indicators.
/mob/living/carbon/human/proc/pain_knockout_fraction()
	var/datum/body/humanoid/HB = body
	if(!istype(HB))
		return 0
	return current_pain() / max(1, HB.pain_tolerance() + 100)

/datum/life_system/hud/carbon/human/health_icons(mob/living/carbon/human/self)
	. = ..()
	if(!. || !self.healths)
		return

	if(self.stat == DEAD || (self.status_effects & FAKEDEATH)) //Dead
		self.healths.icon_state = "health7"	//DEAD healthmeter
		return

	if(self.is_critical()) //Crit
		return

	if(self.factor(BF_ANALGESIA) > 100)
		self.healths.icon_state = "health_numb"
		return

	// Generate a by-limb health display.
	var/mutable_appearance/healths_ma = new(self.healths)
	healths_ma.icon_state = "blank"
	healths_ma.overlays = null
	healths_ma.plane = PLANE_PLAYER_HUD

	var/no_damage = 1
	var/trauma_val = 0 // Used in calculating softcrit/hardcrit indicators.
	if(!(self.species.flags & NO_PAIN))
		trauma_val = self.pain_knockout_fraction()
	var/limb_trauma_val = trauma_val*0.3
	// Collect and apply the images all at once to avoid appearance churn.
	var/list/health_images = list()
	for(var/obj/item/organ/external/E in self.organs)
		if(no_damage && (E.get_trauma() || E.get_burn()))
			no_damage = 0
		health_images += E.get_damage_hud_image(limb_trauma_val)

	// Apply a fire overlay if we're burning.
	if(self.on_fire || self.get_hallucination_component()?.get_hud_state() == HUD_HALLUCINATION_ONFIRE)
		health_images += image('icons/mob/OnFire.dmi',"[self.get_fire_icon_state()]")

	// Show a general pain/crit indicator if needed.
	if(self.get_hallucination_component()?.get_hud_state() == HUD_HALLUCINATION_CRIT)
		trauma_val = 2
	if(trauma_val)
		if(!(self.species.flags & NO_PAIN))
			if(trauma_val > 0.7)
				health_images += image('icons/mob/screen1_health.dmi',"softcrit")
			if(trauma_val >= 1)
				health_images += image('icons/mob/screen1_health.dmi',"hardcrit")
	else if(no_damage)
		health_images += image('icons/mob/screen1_health.dmi',"fullhealth")

	healths_ma.add_overlay(health_images)
	self.healths.appearance = healths_ma

/datum/life_system/vision/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/vision/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(self.stat == DEAD)
		self.sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS|SEE_SELF
		self.see_in_dark = 8
	else //We aren't dead
		self.sight &= ~(SEE_TURFS|SEE_MOBS|SEE_OBJS)

		if(self.see_invisible_default > SEE_INVISIBLE_LEVEL_ONE)
			self.see_invisible = self.see_invisible_default
		else
			self.see_invisible = self.see_in_dark>2 ? SEE_INVISIBLE_LEVEL_ONE : self.see_invisible_default

		// Do this early so certain stuff gets turned off before vision is assigned.
		var/area/A = get_area(self)
		if(A?.flag_check(AREA_NO_SPOILERS))
			self.disable_spoiler_vision()

		if(XRAY in self.mutations)
			self.sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS
			self.see_in_dark = 8
			if(!self.druggy)		self.see_invisible = SEE_INVISIBLE_LEVEL_TWO

		if(self.seer==1)
			var/obj/effect/rune/R = locate() in self.loc
			if(R && R.word1 == GLOB.cultwords["see"] && R.word2 == GLOB.cultwords["hell"] && R.word3 == GLOB.cultwords["join"])
				self.see_invisible = SEE_INVISIBLE_CULT
			else
				self.see_invisible = self.see_invisible_default
				self.seer = 0

		if(!self.seedarkness)
			self.sight = self.species.get_vision_flags(self)
			self.see_in_dark = 8
			self.see_invisible = SEE_INVISIBLE_NOLIGHTING

		else
			self.sight = self.species.get_vision_flags(self)
			self.see_in_dark = self.species.darksight
			if(self.see_invisible_default > SEE_INVISIBLE_LEVEL_ONE)
				self.see_invisible = self.see_invisible_default
			else
				self.see_invisible = self.see_in_dark>2 ? SEE_INVISIBLE_LEVEL_ONE : self.see_invisible_default

		var/glasses_processed = 0
		var/obj/item/rig/rig = self.get_rig()
		if(istype(rig) && rig.visor && !self.is_remote_viewing())
			if(!rig.helmet || (self.head && rig.helmet == self.head))
				if(rig.visor && rig.visor.vision && rig.visor.active && rig.visor.vision.glasses)
					glasses_processed = self.process_glasses(rig.visor.vision.glasses)

		if(self.glasses && !glasses_processed && !self.is_remote_viewing())
			glasses_processed = self.process_glasses(self.glasses)
		if(XRAY in self.mutations)
			self.sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS
			self.see_in_dark = 8
			if(!self.druggy)
				self.see_invisible = SEE_INVISIBLE_LEVEL_TWO

		self.sight |= self.factor(BF_SIGHT_FLAGS)

		if(!glasses_processed && self.nif)
			var/datum/nifsoft/vision_soft
			for(var/datum/nifsoft/NS in self.nif.nifsofts)
				if(NS.vision_exclusive && NS.active)
					vision_soft = NS
					break
			if(vision_soft)
				glasses_processed = self.process_nifsoft_vision(vision_soft)		//not really glasses but equitable

		if(!glasses_processed && (self.species.get_vision_flags(self) > 0))
			self.sight |= self.species.get_vision_flags(self)
		if(!self.seer && !glasses_processed && self.seedarkness)
			self.see_invisible = self.see_invisible_default

		if(self.eyeobj && self.eyeobj.owner != self)
			self.reset_perspective()

	// Call parent to handle signals
	..()

/mob/living/carbon/human/proc/process_glasses(obj/item/clothing/glasses/G)
	. = FALSE
	if(G && G.active)
		if(G.darkness_view)
			see_in_dark += G.darkness_view
			. = TRUE
		if(G.overlay && client)
			client.screen |= G.overlay
		if(G.vision_flags)
			sight |= G.vision_flags
			. = TRUE
		if(istype(G,/obj/item/clothing/glasses/night) && !seer)
			see_invisible = SEE_INVISIBLE_MINIMUM

		if(G.see_invisible >= 0)
			see_invisible = G.see_invisible
			. = TRUE
		else if(!druggy && !seer)
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

/datum/life_system/random_events/carbon/human
	mob_type = /mob/living/carbon/human

/datum/life_system/random_events/carbon/human/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(self.inStasisNow())
		return

	// Puke if toxloss is too high
	if(!self.stat && !isbelly(self.loc))
		var/toxic_load = self.injury_load(INJURY_CATEGORY_TOXIC)
		if (toxic_load >= 30 && self.isSynthetic())
			if(!self.confused)
				if(prob(5))
					to_chat(self, span_danger("You lose directional control!"))
					self.Confuse(10)
		if (toxic_load >= 45 && !self.isSynthetic())
			spawn self.vomit()


	//0.1% chance of playing a scary sound to someone who's in complete darkness
	if(isturf(self.loc) && rand(1,1000) == 1)
		var/turf/T = self.loc
		if(T.get_lumcount() <= LIGHTING_SOFT_THRESHOLD)
			/* 
			if(text2num(time2text(world.timeofday, "MM")) == 4)
				if(text2num(time2text(world.timeofday, "DD")) == 1)
					playsound_local(self,pick(GLOB.scawwysownds),50, 0)
					return
			*/
			self.playsound_local(self,pick(GLOB.scarySounds),50, 1, -1)

/datum/life_system/changeling
	name = "changeling"
	bit = LIFE_SYS_TRAITS
	phase = LIFE_PHASE_TAIL
	order = 140
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Updates the number of stored chemicals for powers.
/datum/life_system/changeling/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	var/datum/component/antag/changeling/comp = is_changeling(self)
	if(!comp)
		if(self.mind && self.hud_used)
			self.ling_chem_display.invisibility = INVISIBILITY_ABSTRACT
		return
	else
		comp.regenerate()
		if(self.hud_used)
			self.ling_chem_display.invisibility = INVISIBILITY_NONE
//			ling_chem_display.maptext = "<div align='center' valign='middle' style='position:relative; top:0px; left:6px'><font color='#dd66dd'>[round(mind.changeling.chem_charges)]</font></div>"
			switch(comp.chem_storage)
				if(1 to 50)
					switch(comp.chem_charges)
						if(0 to 9)
							self.ling_chem_display.icon_state = "ling_chems0"
						if(10 to 19)
							self.ling_chem_display.icon_state = "ling_chems10"
						if(20 to 29)
							self.ling_chem_display.icon_state = "ling_chems20"
						if(30 to 39)
							self.ling_chem_display.icon_state = "ling_chems30"
						if(40 to 49)
							self.ling_chem_display.icon_state = "ling_chems40"
						if(50)
							self.ling_chem_display.icon_state = "ling_chems50"
				if(51 to 80) //This is a crappy way of checking for engorged sacs...
					switch(comp.chem_charges)
						if(0 to 9)
							self.ling_chem_display.icon_state = "ling_chems0e"
						if(10 to 19)
							self.ling_chem_display.icon_state = "ling_chems10e"
						if(20 to 29)
							self.ling_chem_display.icon_state = "ling_chems20e"
						if(30 to 39)
							self.ling_chem_display.icon_state = "ling_chems30e"
						if(40 to 49)
							self.ling_chem_display.icon_state = "ling_chems40e"
						if(50 to 59)
							self.ling_chem_display.icon_state = "ling_chems50e"
						if(60 to 69)
							self.ling_chem_display.icon_state = "ling_chems60e"
						if(70 to 79)
							self.ling_chem_display.icon_state = "ling_chems70e"
						if(80)
							self.ling_chem_display.icon_state = "ling_chems80e"

/datum/life_system/shock
	name = "shock"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_TAIL
	order = 180
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Traumatic shock stages from pain.
/datum/life_system/shock/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	self.updateshock()
	if(SEND_SIGNAL(self, COMSIG_CHECK_FOR_GODMODE) & COMSIG_GODMODE_CANCEL)
		return 0	// Cancelled by a component
	if(self.traumatic_shock >= 80 && self.can_feel_pain())
		self.shock_stage += 1
	else
		self.shock_stage = min(self.shock_stage, 160)
		self.shock_stage = max(self.shock_stage-1, 0)
	if(!self.can_feel_pain()) return

	if(self.stat)
		return 0

	if(self.shock_stage == 10)
		if(self.traumatic_shock >= 80)
			self.custom_pain("[pick("It hurts so much", "You really need some painkillers", "Dear god, the pain")]!", 40)

	if(self.shock_stage >= 30)
		if(self.shock_stage == 30 && !isbelly(self.loc))
			self.automatic_custom_emote(VISIBLE_MESSAGE, "is having trouble keeping their eyes open.", check_stat = TRUE)
		self.eye_blurry = max(2, self.eye_blurry)
		if(self.traumatic_shock >= 80)
			self.stuttering = max(self.stuttering, 5)


	if(self.shock_stage == 40)
		if(self.traumatic_shock >= 80)
			to_chat(self, span_danger("[pick("The pain is excruciating", "Please&#44; just end the pain", "Your whole body is going numb")]!"))

	if (self.shock_stage >= 60)
		if(self.shock_stage == 60 && !isbelly(self.loc))
			self.automatic_custom_emote(VISIBLE_MESSAGE, "'s body becomes limp.", check_stat = TRUE)
		if (prob(2))
			if(self.traumatic_shock >= 80)
				to_chat(self, span_danger("[pick("The pain is excruciating", "Please&#44; just end the pain", "Your whole body is going numb")]!"))
			self.Weaken(20)

	if(self.shock_stage >= 80)
		if (prob(5))
			if(self.traumatic_shock >= 80)
				to_chat(self, span_danger("[pick("The pain is excruciating", "Please&#44; just end the pain", "Your whole body is going numb")]!"))
				if(prob(20) && !isbelly(self.loc))
					self.emote("pain")
			self.Weaken(20)

	if(self.shock_stage >= 120)
		if (prob(2))
			if(self.traumatic_shock >= 80)
				to_chat(self, span_danger("[pick("You black out", "You feel like you could die any moment now", "You are about to lose consciousness")]!"))
				if(prob(40) && !isbelly(self.loc))
					self.emote("pain")
			self.Paralyse(5)
			self.Sleeping(5)

	if(self.shock_stage == 150)
		if(!isbelly(self.loc))
			self.automatic_custom_emote(VISIBLE_MESSAGE, "can no longer stand, collapsing!", check_stat = TRUE)
			if(prob(60))
				self.emote("pain")
		self.Weaken(20)

	if(self.shock_stage >= 150)
		self.Weaken(20)

/datum/life_system/pulse
	name = "pulse"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_TAIL
	order = 310
	mob_type = /mob/living/carbon/human

/datum/life_system/pulse/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	self.pulse = compute(self)

/// The pulse this body should show now (updates every 5 life ticks).
/datum/life_system/pulse/proc/compute(mob/living/carbon/human/self)
	if(self.life_tick % 5) return self.pulse	//update pulse every 5 life ticks (~1 tick/sec, depending on server load)

	var/temp = PULSE_NORM

	var/brain_modifier = 1

	var/modifier_shift = round(self.factor(BF_PULSE_SHIFT))
	// BF_PULSE_SET's baseline is -1: nothing forces the pulse.
	var/modifier_set = self.factor(BF_PULSE_SET)
	modifier_set = modifier_set < 0 ? null : round(modifier_set)

	if(!self.internal_organs_by_name[O_HEART])
		temp = PULSE_NONE
		if(!isnull(modifier_set))
			temp = modifier_set
		return temp //No blood, no pulse.

	if(self.stat == DEAD)
		temp = PULSE_NONE
		if(!isnull(modifier_set))
			temp = modifier_set
		return temp	//that's it, you're dead, nothing can influence your pulse, aside from outside means.

	var/obj/item/organ/internal/heart/Pump = self.internal_organs_by_name[O_HEART]

	// VF / asystole: the heart isn't moving blood (cardiac_arrhythmia).
	if(!self.has_cardiac_output())
		return isnull(modifier_set) ? PULSE_NONE : modifier_set

	var/obj/item/organ/internal/brain/Control = self.internal_organs_by_name[O_BRAIN]

	if(Control)
		brain_modifier = Control.get_control_efficiency()

		if(brain_modifier <= 0.7 && brain_modifier >= 0.4) // 70%-40% control, things start going weird as the brain is failing.
			brain_modifier = rand(5, 15) / 10

	if(Pump)
		temp += Pump.standard_pulse_level - PULSE_NORM

	if(round(self.vessel.get_reagent_amount(REAGENT_ID_BLOOD)) <= self.species.blood_volume*self.species.blood_level_danger)	//how much blood do we have
		temp = temp + 3	//not enough :(

	if(self.status_flags & FAKEDEATH)
		temp = PULSE_NONE		//pretend that we're dead. unlike actual death, can be inflienced by meds

	if(!isnull(modifier_set))
		temp = modifier_set

	temp = max(0, temp + modifier_shift)	// No negative pulses.

	if(Pump)
		///Prevents duplicating a reagent if it's in our gut and blood
		var/list/current_medications = list()
		//Stuff in our stomach, such as coffee, nicotine, 13loko, etc.
		for(var/datum/reagent/R in self.ingested.reagent_list)
			if((R.id in GLOB.tachycardics) && !(R.id in current_medications))
				if(temp < PULSE_THREADY && temp != PULSE_NONE) //If we really push it, we can get our pulse to thready.
					temp++
					current_medications += R.id
			if((R.id in GLOB.bradycardics) && !(R.id in current_medications))
				if(temp >= PULSE_NORM)
					temp--
					current_medications += R.id
		//Stuff in our bloodstream. (Heart-stopping drugs induce a cardiac_arrhythmia instead; see toxins.dm.)
		for(var/datum/reagent/R in self.reagents.reagent_list)
			if((R.id in GLOB.tachycardics) && !(R.id in current_medications))
				if(temp < PULSE_THREADY && temp != PULSE_NONE) //We can reach a thready pulse, but only if we actually have a pulse.
					temp++
					current_medications += R.id
			if((R.id in GLOB.bradycardics) && !(R.id in current_medications))
				if(temp >= PULSE_NORM) //Can get to PULSE_SLOW but never PULSE_NONE
					temp--
					current_medications += R.id
	return max(0, round(temp * brain_modifier))

/datum/life_system/heartbeat
	name = "heartbeat"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_TAIL
	order = 240
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Heartbeat sound for fast pulses, shock or space.
/datum/life_system/heartbeat/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(self.pulse == PULSE_NONE)
		return

	var/obj/item/organ/internal/heart/H = self.internal_organs_by_name[O_HEART]

	if(!H || (H.robotic >= ORGAN_ROBOT))
		return

	if(self.pulse >= PULSE_2FAST || self.shock_stage >= 10 || (istype(get_turf(self), /turf/space) && self.read_preference(/datum/preference/toggle/play_ambience)))
		//PULSE_THREADY - maximum value for pulse, currently it 5.
		//High pulse value corresponds to a fast rate of heartbeat.
		//Divided by 2, otherwise it is too slow.
		var/rate = (PULSE_THREADY - self.pulse)/2

		if(self.heartbeat >= rate)
			self.heartbeat = 0
			self << sound('sound/effects/singlebeat.ogg',0,0,0,50)
		else
			self.heartbeat++

/*
	Called by life(), instead of having the individual hud items update icons each tick and check for status changes
	we only set those statuses and icons upon changes.  Then those HUD items will simply add those pre-made images.
	This proc below is only called when those HUD elements need to change as determined by the mobs hud_updateflag.
*/
/datum/life_system/hud/carbon/human/proc/hud_list(mob/living/carbon/human/self)
	if (BITTEST(self.hud_updateflag, HEALTH_HUD))
		var/image/holder = self.grab_hud(HEALTH_HUD)
		var/image/health_us = self.grab_hud(HEALTH_VR_HUD)
		if(self.stat == DEAD || (self.status_flags & FAKEDEATH))
			holder.icon_state = "-100" 	// X_X
		else
			holder.icon_state = vitality_hud_state(self)
		if(self.block_hud)
			holder.icon_state = "hudblank"
		health_us.icon_state = holder.icon_state
		self.apply_hud(HEALTH_HUD, holder)
		self.apply_hud(HEALTH_VR_HUD, health_us)

	if (BITTEST(self.hud_updateflag, LIFE_HUD))
		var/image/holder = self.grab_hud(LIFE_HUD)
		if(self.isSynthetic())
			holder.icon_state = "hudrobo"
		else if(self.stat == DEAD || (self.status_flags & FAKEDEATH))
			holder.icon_state = "huddead"
		else
			holder.icon_state = "hudhealthy"
		if(self.block_hud)
			holder.icon_state = "hudblank"
		self.apply_hud(LIFE_HUD, holder)

	if (BITTEST(self.hud_updateflag, STATUS_HUD))

		var/image/holder = self.grab_hud(STATUS_HUD)
		var/image/holder2 = self.grab_hud(STATUS_HUD_OOC)
		var/image/status_r = self.grab_hud(STATUS_R_HUD)
		if (self.isSynthetic())
			holder.icon_state = "hudrobo"
		else if(self.stat == DEAD || (self.status_flags & FAKEDEATH))
			holder.icon_state = "huddead"
			holder2.icon_state = "huddead"
		else if(self.has_virus())
			holder.icon_state = "hudill"
		else
			holder.icon_state = "hudhealthy"
			if(self.has_virus())
				holder2.icon_state = "hudill"
			else
				holder2.icon_state = "hudhealthy"
		if(self.block_hud)
			holder.icon_state = "hudblank"
			holder2.icon_state = "hudblank"

		status_r.icon_state = holder.icon_state
		self.apply_hud(STATUS_HUD, holder)
		self.apply_hud(STATUS_R_HUD, status_r)
		self.apply_hud(STATUS_HUD_OOC, holder2)

	if (BITTEST(self.hud_updateflag, ID_HUD))
		var/image/holder = self.grab_hud(ID_HUD)
		if(self.wear_id)
			var/obj/item/card/id/I = self.wear_id.GetID()
			if(I)
				holder.icon_state = "hud[ckey(I.GetJobName())]"
			else
				holder.icon_state = "hudunknown"
		else
			holder.icon_state = "hudunknown"

		if(self.block_hud)
			holder.icon_state = "hudblank"
		self.apply_hud(ID_HUD, holder)

	if (BITTEST(self.hud_updateflag, WANTED_HUD))
		var/image/holder = self.grab_hud(WANTED_HUD)
		holder.icon_state = "hudblank"
		var/perpname = self.name
		if(self.wear_id)
			var/obj/item/card/id/I = self.wear_id.GetID()
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
		if(self.block_hud)
			holder.icon_state = "hudblank"
		self.apply_hud(WANTED_HUD, holder)

	if (  BITTEST(self.hud_updateflag, IMPLOYAL_HUD) \
	   || BITTEST(self.hud_updateflag,  IMPCHEM_HUD) \
	   || BITTEST(self.hud_updateflag, IMPTRACK_HUD))

		var/image/holder1 = self.grab_hud(IMPTRACK_HUD)
		var/image/holder2 = self.grab_hud(IMPLOYAL_HUD)
		var/image/holder3 = self.grab_hud(IMPCHEM_HUD)

		holder1.icon_state = "hudblank"
		holder2.icon_state = "hudblank"
		holder3.icon_state = "hudblank"

		for(var/obj/item/implant/I in self)
			if(I.implanted)
				if(!I.malfunction)
					if(istype(I,/obj/item/implant/tracking))
						holder1.icon_state = "hud_imp_tracking"
					if(istype(I,/obj/item/implant/loyalty))
						holder2.icon_state = "hud_imp_loyal"
					if(istype(I,/obj/item/implant/chem))
						holder3.icon_state = "hud_imp_chem"

		self.apply_hud(IMPTRACK_HUD, holder1)
		self.apply_hud(IMPLOYAL_HUD, holder2)
		self.apply_hud(IMPCHEM_HUD, holder3)

	if (BITTEST(self.hud_updateflag, SPECIALROLE_HUD))
		var/image/holder = self.grab_hud(SPECIALROLE_HUD)
		holder.icon_state = "hudblank"
		if(self.mind && self.mind.special_role)
			if(GLOB.hud_icon_reference[self.mind.special_role])
				holder.icon_state = GLOB.hud_icon_reference[self.mind.special_role]
			else
				holder.icon_state = "hudsyndicate"
		self.apply_hud(SPECIALROLE_HUD, holder)

	//Backup implant hud status
	if (BITTEST(self.hud_updateflag, BACKUP_HUD))
		var/image/holder = self.grab_hud(BACKUP_HUD)

		holder.icon_state = "hudblank"

		for(var/obj/item/organ/external/E in self.organs)
			for(var/obj/item/implant/I in E.implants)
				if(I.implanted && istype(I,/obj/item/implant/backup))
					var/obj/item/implant/backup/B = I
					if(!self.mind)
						holder.icon_state = "hud_backup_nomind"
					else if(!(self.mind.name in B.our_db.body_scans))
						holder.icon_state = "hud_backup_nobody"
					else
						holder.icon_state = "hud_backup_norm"
		if(self.block_hud)
			holder.icon_state = "hudblank"
		self.apply_hud(BACKUP_HUD, holder)

	//Vore Antag Hud
	if (BITTEST(self.hud_updateflag, VANTAG_HUD))
		var/image/vantag = self.grab_hud(VANTAG_HUD)
		if(self.vantag_pref)
			vantag.icon_state = self.vantag_pref
		else
			vantag.icon_state = "hudblank"
		if(self.block_hud)
			vantag.icon_state = "hudblank"
		self.apply_hud(VANTAG_HUD, vantag)

	self.hud_updateflag = 0

/mob/living/carbon/human/on_fire_stack(seconds_per_tick, datum/status_effect/fire_handler/fire_stacks/fire_handler)
	SEND_SIGNAL(src, COMSIG_HUMAN_BURNING)
	// burn_clothing(seconds_per_tick, fire_handler.stacks)
	var/no_protection = FALSE
	if(HAS_TRAIT(src, TRAIT_IGNORE_FIRE_PROTECTION))
		no_protection = TRUE
	fire_handler.harm_human(seconds_per_tick, no_protection)

/mob/living/carbon/human/rejuvenate()
	restore_blood()
	shock_stage = 0
	traumatic_shock = 0
	..()

/datum/life_system/defib_timer
	name = "defib timer"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_TAIL
	order = 280
	segment = LIFE_SEG_HUMAN_DEAD
	mob_type = /mob/living/carbon/human

/// Brain decay while dead, which closes the defibrillation window.
/datum/life_system/defib_timer/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(!self.should_have_organ(O_BRAIN))
		return // No brain.

	var/obj/item/organ/internal/brain/brain = self.internal_organs_by_name[O_BRAIN]
	if(!brain)
		return // Still no brain.

	brain.tick_defib_timer()

/mob/living/carbon/human/proc/has_virus()
	for(var/thing in viruses)
		var/datum/disease/D = thing
		if(!global_flag_check(D.virus_modifiers, DISCOVERED))
			continue
		if((!(D.visibility_flags & HIDDEN_SCANNER)) && (D.danger != DISEASE_NONTHREAT))
			return TRUE
	return FALSE


#undef HEAT_DAMAGE_LEVEL_1
#undef HEAT_DAMAGE_LEVEL_2
#undef HEAT_DAMAGE_LEVEL_3

#undef COLD_DAMAGE_LEVEL_1
#undef COLD_DAMAGE_LEVEL_2
#undef COLD_DAMAGE_LEVEL_3

#undef HUMAN_COMBUSTION_TEMP


// === merged from life_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/life_system/weight
	name = "weight"
	bit = LIFE_SYS_NUTRITION
	phase = LIFE_PHASE_TAIL
	order = 170
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Weight gain and loss from nutrition.
/datum/life_system/weight/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if (self.nutrition >= 0 && self.stat != 2)
		if (self.nutrition > MIN_NUTRITION_TO_GAIN && self.weight < MAX_MOB_WEIGHT && self.weight_gain)
			self.weight += self.species.metabolism*(0.01*self.weight_gain)

		else if (self.nutrition <= MAX_NUTRITION_TO_LOSE && self.stat != 2 && self.weight > MIN_MOB_WEIGHT && self.weight_loss)
			self.weight -= self.species.metabolism*(0.01*self.weight_loss) // starvation weight loss

//Our call for the NIF to do whatever
/datum/life_system/nif
	name = "nif"
	bit = LIFE_SYS_TRAITS
	phase = LIFE_PHASE_TAIL
	order = 250
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Our call for the NIF to do whatever.
/datum/life_system/nif/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(!self.nif) return

	//Process regular life stuff
	self.nif.life()

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
