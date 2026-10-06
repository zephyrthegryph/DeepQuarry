/mob/living/carbon/Initialize(mapload)
	. = ..()
	//setup reagent holders
	// The bloodstream is the carbon's owned `reagents`; `bloodstr` is a relation alias of it.
	rel_set(src, nameof(reagents), new/datum/reagents/metabolism/bloodstream(500, src)) // ALLOW(decl): holder takes constructor args
	rel_set(src, nameof(bloodstr), reagents)
	rel_set(src, nameof(ingested), new/datum/reagents/metabolism/ingested(500, src)) // ALLOW(decl): holder takes constructor args
	rel_set(src, nameof(touching), new/datum/reagents/metabolism/touch(500, src)) // ALLOW(decl): holder takes constructor args
	if (!default_language && species_language)
		default_language = GLOB.all_languages[species_language]

	enable_footsteps(custom_footstep, 1, -6)

	rel_set(src, nameof(cozyloop), new /datum/looping_sound/mob/cozyloop(list(src), FALSE)) // ALLOW(decl): looping_sound takes constructor args

/// Skin germs creep up to the ambient level, on a rewake. Runs even while transforming or in
/// nullspace (it followed ..() in the old carbon Life()).
/mob/living/carbon
	fire_heats_body = TRUE
	/// Biological time (clock_now(CLOCK_BIO), ds) of the germs stage's last roll, or null
	/// before the first. Not 0: a biology clock can legitimately read 0 (stopped from the start).
	var/germs_rolled_at

/mob/living/carbon/proc/life_germs(datum/seq_frame/life/F)
	// A 30% chance per Life cycle, charged for the biological time since the last roll (the
	// stage idles and comes back on its rewake), so stasis stops the creep too.
	var/now = clock_now(src, CLOCK_BIO)
	// Charged for elapsed biological time only: a roll with no bio time behind it (a rewake or
	// frame while the clock is stopped by stasis) charges nothing, so re-runs cannot add creep.
	var/cycles = !isnull(src.germs_rolled_at) ? clamp((now - src.germs_rolled_at) / LIFE_CYCLE, 0, GERM_CATCHUP_CYCLES) : 1
	src.germs_rolled_at = now
	if(src.germ_level >= GERM_LEVEL_AMBIENT)	//if you're just standing there, you shouldn't get more germs beyond an ambient level
		return
	var/expected = cycles * 0.3
	var/gain = round(expected) + (prob((expected - round(expected)) * 100) ? 1 : 0)
	if(gain)
		src.germ_level = min(GERM_LEVEL_AMBIENT, src.germ_level + gain)

/// Lazy: germs creep up on the rewake; washing lowers them, and the next roll resumes the creep.

/mob/living/carbon/proc/life_germs_rewake()
	return src.germ_level < GERM_LEVEL_AMBIENT ? GERM_RESAMPLE : 0


/mob/living/carbon/rejuvenate()
	bloodstr.clear_reagents()
	ingested.clear_reagents()
	touching.clear_reagents()
	..()
/* Duplicated in our code
/mob/living/carbon/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(src.nutrition && src.stat != 2)
		adjust_nutrition(-DEFAULT_HUNGER_FACTOR / 10)
		if(src.m_intent == I_RUN)
			adjust_nutrition(-DEFAULT_HUNGER_FACTOR / 10)

	if((src.has_mutation(FAT)) && src.m_intent == I_RUN && src.body_temperature() <= 360)
		src.adjust_bodytemperature(2)

	// Moving around increases germ_level faster
	if(germ_level < GERM_LEVEL_MOVE_CAP && prob(8))
		germ_level++
*/
/mob/living/carbon/gib()
	for(var/mob/M in contents_of(src))
		M.forceMove(src.loc)
		for(var/mob/N in viewers(src, null))
			if(N.client)
				N.show_message(span_bolddanger("[M] bursts out of [src]!"), 2)
	..()

/mob/living/carbon/unarmed_touch(mob/living/M, stance = I_HELP)
	if(touch_reaction_flags & SPECIES_TRAIT_THORNS)
		if(src != M)
			if(istype(M,/mob/living))
				var/mob/living/L = M
				L.injure(INJURY_PIERCE, 3, L.hand ? BP_L_HAND : BP_R_HAND, src)
				act_message(L, src, MSG_SELF(span_warning("%T% is covered in sharp bits and it hurt when you touched them!")), \
					MSG_OTHERS(span_warning("%U% is hurt by sharp body parts when touching %T%!")))

	if(!istype(M, /mob/living/carbon)) return

	if (ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]
		if (H.hand)
			temp = H.organs_by_name[BP_L_HAND]
		if(temp && !temp.is_usable())
			to_chat(H, span_warning("You can't use your [temp.name]"))
			return

	return

//EMP vulnerability for non-synth carbons. could be useful for diona, vox, or others
//the species' emp_sensitivity var needs to be greater than 0 for this to proc, and it defaults to 0 - shouldn't stack with prosthetics/fbps in most cases
//higher sensitivity values incur additional effects, starting with confusion/blinding/knockdown and ending with increasing amounts of damage
//the degree of damage and duration of effects can be tweaked up or down based on the species emp_dmg_mod and emp_stun_mod vars (default 1) on top of tuning the random ranges
/mob/living/carbon/proc/species_emp_effects(datum/act/A)
	if(!species)
		return
	var/datum/notice/hit/emp/N = A
	var/severity = N.packet.severity
	//pregen our stunning stuff, had to do this seperately or else byond complained. remember that severity falls off with distance based on the source, so we don't need to do any extra distance calcs here.
	var/agony_str = ((rand(4,6)*15)-(15*severity))*species.emp_stun_mod //big ouchies at high severity, causes 0-75 halloss/agony; shotgun beanbags and revolver rubbers do 60
	var/deafen_dur = (rand(9,16)-severity)*species.emp_stun_mod //5-15 deafen, on par with a flashbang
	var/confuse_dur = (rand(4,11)-severity)*species.emp_stun_mod //0-10 wobbliness, on par with a flashbang
	var/weaken_dur = (rand(2,4)-severity)*species.emp_stun_mod //0-3 knockdown, on par with.. you get the idea
	var/blind_dur = (rand(3,6)-severity)*species.emp_stun_mod //0-5 blind
	if(species.emp_sensitivity) //receive warning message and basic effects
		to_chat(src, span_bolddanger("*BZZZT*"))
		switch(severity)
			if(EMP_HEAVY)
				to_chat(src, span_danger("DANGER: Extreme EM flux detected!"))
			if(EMP_MEDIUM)
				to_chat(src, span_danger("Danger: High EM flux detected!"))
			if(EMP_LIGHT)
				to_chat(src, span_danger("Warning: Moderate EM flux detected!"))
			if(EMP_HARMLESS)
				to_chat(src, span_danger("Warning: Minor EM flux detected!"))
		if(prob(90-(10*severity))) //50-80% chance to fire an emote. most are harmless, but vomit might reduce your nutrition level which could suck (so the whole thing is padded out with extras)
			src.emote(pick("twitch", "twitch_v", "choke", "pale", "blink", "blink_r", "shiver", "sneeze", "vomit", "gasp", "cough", "drool"))
		//stun effects block, effects vary wildly
		if(species.emp_sensitivity & EMP_PAIN)
			to_chat(src, span_danger("A wave of intense pain washes over you."))
			injure(INJURY_PAIN, agony_str)
		if(species.emp_sensitivity & EMP_BLIND)
			if(blind_dur >= 1) //don't flash them unless they actually roll a positive blind duration
				src.flash_eyes(3)	//3 allows it to bypass any tier of eye protection, necessary or else sec sunglasses/etc. protect you from this
			status_at_least(STAT_BLINDED, max(0,blind_dur))
		if(species.emp_sensitivity & EMP_DEAFEN)
			src.set_ear_damage(src.ear_damage + (rand(0,deafen_dur))) //this will heal pretty quickly, but spamming them at someone could cause serious damage
			src.status_at_least(STAT_DEAFENED, deafen_dur)
			src.deaf_loop.start() // Ear Ringing/Deafness
		if(species.emp_sensitivity & EMP_CONFUSE)
			if(confuse_dur >= 1)
				to_chat(src, span_danger("Oh god, everything's spinning!"))
			status_at_least(STAT_CONFUSED, max(0,confuse_dur))
		if(species.emp_sensitivity & EMP_WEAKEN)
			if(weaken_dur >= 1)
				to_chat(src, span_danger("Your limbs go slack!"))
			status_at_least(STAT_WEAKENED, max(0,weaken_dur))
		//physical damage block, deals (minor-4) 5-15, 10-20, 15-25, 20-30 (extreme-1) of *each* type
		if(species.emp_sensitivity & EMP_BRUTE_DMG)
			injure(INJURY_BLUNT, rand(25-(severity*5),35-(severity*5)) * species.emp_dmg_mod)
		if(species.emp_sensitivity & EMP_BURN_DMG)
			injure(INJURY_ELECTRIC, rand(25-(severity*5),35-(severity*5)) * species.emp_dmg_mod)
		if(species.emp_sensitivity & EMP_TOX_DMG)
			injure(INJURY_TOXIN, rand(25-(severity*5),35-(severity*5)) * species.emp_dmg_mod)
		if(species.emp_sensitivity & EMP_OXY_DMG)
			add_oxygen_debt(rand(25-(severity*5),35-(severity*5)) * species.emp_dmg_mod, "EMP")

/mob/living/carbon/electrocute_act(shock_damage, obj/source, siemens_coeff = 1.0, def_zone = null, stun = 1)
	if(in_godmode(src))
		return 0
	if(def_zone == BP_L_HAND || def_zone == BP_R_HAND) //Diona (And any other potential plant people) hands don't get shocked.
		if(species.flags & IS_PLANT)
			return 0
	shock_damage *= siemens_coeff
	if (shock_damage<1)
		return 0

	receive_shock(0.2 * shock_damage, source, def_zone) //shock the target organ
	receive_shock(0.4 * shock_damage, source, BP_TORSO) //shock the torso more
	receive_shock(0.2 * shock_damage, source) //shock a random part!
	receive_shock(0.2 * shock_damage, source) //shock a random part!

	play_sfx(src, SFX_SPARKS, extrarange = -1)
	if (shock_damage > 15)
		act_message(src, null, MSG_SELF(span_danger("You feel a powerful shock course through your body!")), \
			MSG_OTHERS(span_warning("%U% was electrocuted[source ? " by the [source]" : ""]!")), \
			MSG_BLIND(span_warning("You hear a heavy electrical crack.")))
	else
		act_message(src, null, MSG_SELF(span_warning("You feel a shock course through your body.")), \
			MSG_OTHERS(span_warning("%U% was shocked[source ? " by the [source]" : ""].")), \
			MSG_BLIND(span_warning("You hear a zapping sound.")))

	if(stun)
		switch(shock_damage)
			if(16 to 20)
				status_at_least(STAT_STUNNED, 2)
			if(21 to 25)
				status_at_least(STAT_WEAKENED, 2)
			if(26 to 30)
				status_at_least(STAT_WEAKENED, 5)
			if(31 to INFINITY)
				status_at_least(STAT_WEAKENED, 10) //This should work for now, more is really silly and makes you lay there forever

	fx_sparks(loc, 5)

	return shock_damage

/mob/living/carbon/proc/help_shake_act(mob/living/carbon/M)
	if (!is_critical() || on_fire)
		if(src == M && ishuman(src))
			var/mob/living/carbon/human/H = src
			act_message(src, null, MSG_SELF(span_notice("You check yourself for injuries.")), \
				MSG_OTHERS(span_notice("%U% examines %THEMSELVES%.")))

			for(var/obj/item/organ/external/org in H.organs)
				var/list/status = list()
				var/brutedamage = org.get_trauma()
				var/burndamage = org.get_burn()
				//For reference, these will show up in game as:
				//"My X is: [DESCRIPTOR]"
				switch(brutedamage)
					if(1 to 20)
						status += "bruised"
					if(20 to 40)
						status += "wounded"
					if(40 to INFINITY)
						status += "mangled"

				switch(burndamage)
					if(1 to 10)
						status += "numb"
					if(10 to 40)
						status += "blistered"
					if(40 to INFINITY)
						status += "peeling away"

				if(org.is_stump())
					status += "MISSING"
				if(org.status & ORGAN_MUTATED)
					status += "weirdly shapen"
				if(org.dislocated == 1)
					status += "dislocated"
				if(org.is_fractured())
					status += "[can_feel_pain(org) ? "hurting and " : ""]abnormally bent"
				//infection stuff
				if(org.status & ORGAN_DEAD)
					status += "necrotic"
				else if(org.germ_level > INFECTION_LEVEL_TWO)
					status += "burning and feels like it's on fire"
				else if(org.germ_level > INFECTION_LEVEL_TWO-INFECTION_LEVEL_ONE) //Early warning
					status += "warm to the touch"
				for(var/datum/affliction/wound/W as anything in org.get_wounds())
					if(W.internal)
						status += "[can_feel_pain(org) ? "hurting and " : ""]showing a slowly growing bruise"
				if(!org.is_usable() || org.is_dislocated())
					status += "dangling uselessly"
				if(status.len)
					src.show_message("My [org.name] is " + span_warning("[english_list(status)]."),1)
				else
					src.show_message("My [org.name] is " + span_notice("OK."),1)

			if((H.has_mutation(SKELETON)) && (!H.get_equipped_item(SLOT_ID_UNIFORM)) && (!H.get_equipped_item(SLOT_ID_SUIT)))
				H.play_xylophone()
		else if (on_fire)
			play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
			if (M.on_fire)
				act_message(M, src, MSG_SELF(span_warning("You try to pat out %T%'s flames, but to no avail! Put yourself out first!")), \
					MSG_OTHERS(span_warning("%U% tries to pat out %T%'s flames, but to no avail!")))
			else
				act_message(M, src, MSG_SELF(span_warning("You try to pat out %T%'s flames! Hot!")), \
					MSG_OTHERS(span_warning("%U% tries to pat out %T%'s flames!")))
				task_timed(M, 1.5 SECONDS, target = src, receiver = src, on_done = PROC_REF(help_shake_act_carbon_done), done_args = list(M))
		else
			if (ishuman(src))
				var/mob/living/carbon/human/H = src
				if(H.get_equipped_item(SLOT_ID_UNIFORM))
					H.get_equipped_item(SLOT_ID_UNIFORM).add_fingerprint(M)

			var/show_ssd
			var/mob/living/carbon/human/H = src
			if(istype(H)) show_ssd = H.species.show_ssd
			if(show_ssd && !client && !teleop)
				act_message(M, src, MSG_SELF(span_notice("You shake %T%, but [p_they()] [p_do()] not respond... Maybe [H.p_theyre()] S.S.D?")), \
					MSG_OTHERS(span_notice("%U% shakes %T% trying to wake [H.p_them()] up!")))
			else if(lying || src.has_status(STAT_SLEEPING))
				status_adjust(STAT_SLEEPING, -5)
				if(!src.has_status(STAT_SLEEPING))
					set_resting(0)
				act_message(M, src, MSG_SELF(span_notice("You shake %T% trying to wake [H.p_them()] up!")), \
					MSG_OTHERS(span_notice("%U% shakes %T% trying to wake [H.p_them()] up!")))
			else
				var/mob/living/carbon/human/hugger = M
				if(M.resting == 1) //Are they resting on the ground?
					act_message(M, src, MSG_SELF(span_notice("You grip onto %T% and pull yourself up off the ground!")), \
						MSG_OTHERS(span_notice("%U% grabs onto %T% and pulls %THEMSELVES% up")))
					if(M.fire_stacks >= (src.fire_stacks + 3)) //Fire checks.
						src.adjust_fire_stacks(1)
						M.adjust_fire_stacks(-1)
					if(M.on_fire)
						src.ignite_mob()
					M.set_resting(0) //Hoist yourself up up off the ground. No para/stunned/weakened removal.
					update_canmove()
				else if(istype(hugger))
					hugger.species.hug(hugger,src)
				else
					act_message(M, src, MSG_SELF(span_notice("You hug %T% to make [H.p_them()] feel better!")), \
						MSG_OTHERS(span_notice("%U% hugs %T% to make [H.p_them()] feel better!")))
				if(M.fire_stacks >= (src.fire_stacks + 3))
					src.adjust_fire_stacks(1)
					M.adjust_fire_stacks(-1)
				if(M.on_fire)
					src.ignite_mob()
			status_adjust(STAT_PARALYZED, -3)
			status_adjust(STAT_STUNNED, -3)
			status_adjust(STAT_WEAKENED, -3)

			play_sfx(src, SFX_WEAPONS_THUDSWOOSH)

/mob/living/carbon/proc/help_shake_act_carbon_done(mob/living/carbon/M)
	src.adjust_fire_stacks(-0.5)
	if (prob(10) && (M.fire_stacks <= 0))
		M.adjust_fire_stacks(1)
	M.ignite_mob()
	if (M.on_fire)
		act_message(M, src, MSG_SELF(span_danger("The fire spreads to you as well!")), \
			MSG_OTHERS(span_danger("The fire spreads from %T% to %U%!")))
	else
		src.adjust_fire_stacks(-0.5) //Less effective than stop, drop, and roll - also accounting for the fact that it takes half as long.
		if (src.fire_stacks <= 0)
			act_message(M, src, MSG_SELF(span_warning("You successfully pat out %T%'s flames.")), \
				MSG_OTHERS(span_warning("%U% successfully pats out %T%'s flames.")))
			src.extinguish_mob()

/mob/living/carbon/proc/eyecheck()
	return 0

/mob/living/carbon/flash_eyes(intensity = FLASH_PROTECTION_MODERATE, override_blindness_check = FALSE, affect_silicon = FALSE, visual = FALSE, type = /atom/movable/screen/fullscreen/flash)
	if(eyecheck() < intensity || override_blindness_check)
		return ..()

// ++++ROCKDTBEN++++ MOB PROCS -- Ask me before touching.
// Stop! ... Hammertime! ~Carn

/mob/living/carbon/proc/getDNA()
	return dna

/mob/living/carbon/proc/setDNA(datum/dna/newDNA)
	rel_set(src, nameof(dna), newDNA)

// ++++ROCKDTBEN++++ MOB PROCS //END

/mob/living/carbon/can_use_hands()
	if(get_equipped_item(SLOT_ID_HANDCUFFED))
		return 0
	if(src?.buckled_to() && istype(src?.buckled_to(), /obj/structure/bed/nest)) // buckling does not restrict hands
		return 0
	return 1

/mob/living/carbon/restrained()
	if (get_equipped_item(SLOT_ID_HANDCUFFED))
		return 1
	return

/mob/living/carbon/equipped_to_slot(obj/item/W, slot)
	..()
	if(slot == SLOT_ID_HANDCUFFED)
		update_handcuffed()

/mob/living/carbon/slot_vacated(slot_id, obj/item/I)
	..()
	if(slot_id == SLOT_ID_HANDCUFFED)
		update_handcuffed()
		var/obj/buckled = src?.buckled_to()
		if(buckled && buckled.buckle_require_restraints)
			buckled.unbuckle_mob()

//generates realistic-ish pulse output based on preset levels
/mob/living/carbon/proc/get_pulse(method)	//method 0 is for hands, 1 is for machines, more accurate
	var/temp = 0								//see setup.dm:694
	switch(src.pulse)
		if(PULSE_NONE)
			return "0"
		if(PULSE_SLOW)
			temp = rand(40, 60)
			return num2text(method ? temp : temp + rand(-10, 10))
		if(PULSE_NORM)
			temp = rand(60, 90)
			return num2text(method ? temp : temp + rand(-10, 10))
		if(PULSE_FAST)
			temp = rand(90, 120)
			return num2text(method ? temp : temp + rand(-10, 10))
		if(PULSE_2FAST)
			temp = rand(120, 160)
			return num2text(method ? temp : temp + rand(-10, 10))
		if(PULSE_THREADY)
			return method ? ">250" : "extremely weak and fast, patient's artery feels like a thread"
//			output for machines^	^^^^^^^output for people^^^^^^^^^

/mob/living/carbon/Bump(atom/A)
	if(now_pushing)
		return
	..()
	if(istype(A, /mob/living/carbon) && prob(10))
		var/mob/living/carbon/human/H = A
		for(var/datum/affliction/contagion/D as anything in get_spreadable_contagions())
			if(D.spread_flags & DISEASE_SPREAD_CONTACT)
				H.expose_contagion(D)

/mob/living/carbon/cannot_use_vents()
	return

/mob/living/carbon/slip(slipped_on,stun_duration=8)
	PUBLISH_LEGACY(src, /datum/notice/carbon_slip, slipped_on, stun_duration)
	if(src?.buckled_to())
		return FALSE
	stop_pulling()
	to_chat(src, span_warning("You slipped on [slipped_on]!"))
	play_sfx(src, SFX_MISC_SLIP, 2, extrarange = -3)
	if(has_trait(src, SLIP_REFLEX_TRAIT) && !lying)
		if(COOLDOWN_FINISHED(src, next_emote))
			src.emote("sflip")
			return TRUE
	status_at_least(STAT_WEAKENED, FLOOR(stun_duration/2, 1))
	return TRUE

/mob/living/carbon/get_default_language()
	if(default_language)
		if(can_speak(default_language))
			return default_language
		else
			return GLOB.all_languages[LANGUAGE_GIBBERISH]

	if(!species)
		return GLOB.all_languages[LANGUAGE_GIBBERISH]

	return species.default_language ? GLOB.all_languages[species.default_language] : GLOB.all_languages[LANGUAGE_GIBBERISH]

/mob/living/carbon/proc/should_have_organ(organ_check)
	return 0

/mob/living/carbon/can_feel_pain(check_organ)
	if(!species)
		return 0
	if(HAS_SYNTHETIC_BIOLOGY(src))
		return 0
	return !(species.flags & NO_PAIN)

/mob/living/carbon/proc/update_handcuffed()
	if(get_equipped_item(SLOT_ID_HANDCUFFED))
		drop_l_hand()
		drop_r_hand()
		stop_pulling()
		throw_alert("handcuffed", /atom/movable/screen/alert/restrained/handcuffed, new_master = get_equipped_item(SLOT_ID_HANDCUFFED))
	else
		clear_alert("handcuffed")
	update_mob_action_buttons() //some of our action buttons might be unusable when we're handcuffed.
	update_inv_handcuffed()

// Clears blood overlays
/mob/living/carbon/wash(clean_types)
	. = ..()
	if(get_equipped_item(SLOT_ID_HAND_R))
		get_equipped_item(SLOT_ID_HAND_R).wash(clean_types)
	if(get_equipped_item(SLOT_ID_HAND_L))
		get_equipped_item(SLOT_ID_HAND_L).wash(clean_types)
	if(get_equipped_item(SLOT_ID_BACK))
		if(get_equipped_item(SLOT_ID_BACK).wash(clean_types))
			src.update_inv_back(0)

	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		var/washgloves = 1
		var/washshoes = 1
		var/washmask = 1
		var/washears = 1
		var/washglasses = 1

		if(H.get_equipped_item(SLOT_ID_SUIT))
			washgloves = !(H.get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDEGLOVES)
			washshoes = !(H.get_equipped_item(SLOT_ID_SUIT).flags_inv & HIDESHOES)

		if(H.get_equipped_item(SLOT_ID_HEAD))
			washmask = !(H.get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEMASK)
			washglasses = !(H.get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEEYES)
			washears = !(H.get_equipped_item(SLOT_ID_HEAD).flags_inv & HIDEEARS)

		if(H.get_equipped_item(SLOT_ID_MASK))
			if (washears)
				washears = !(H.get_equipped_item(SLOT_ID_MASK).flags_inv & HIDEEARS)
			if (washglasses)
				washglasses = !(H.get_equipped_item(SLOT_ID_MASK).flags_inv & HIDEEYES)

		if(H.get_equipped_item(SLOT_ID_HEAD))
			if(H.get_equipped_item(SLOT_ID_HEAD).wash(clean_types))
				H.update_inv_head()

		if(H.get_equipped_item(SLOT_ID_SUIT))
			if(H.get_equipped_item(SLOT_ID_SUIT).wash(clean_types))
				H.update_inv_wear_suit()

		else if(H.get_equipped_item(SLOT_ID_UNIFORM))
			if(H.get_equipped_item(SLOT_ID_UNIFORM).wash(clean_types))
				H.update_inv_w_uniform()

		if(H.get_equipped_item(SLOT_ID_GLOVES) && washgloves)
			if(H.get_equipped_item(SLOT_ID_GLOVES).wash(clean_types))
				H.update_inv_gloves(0)

		if(H.get_equipped_item(SLOT_ID_SHOES) && washshoes)
			if(H.get_equipped_item(SLOT_ID_SHOES).wash(clean_types))
				H.update_inv_shoes(0)

		if(H.get_equipped_item(SLOT_ID_MASK) && washmask)
			if(H.get_equipped_item(SLOT_ID_MASK).wash(clean_types))
				H.update_inv_wear_mask(0)

		if(H.get_equipped_item(SLOT_ID_EYES) && washglasses)
			if(H.get_equipped_item(SLOT_ID_EYES).wash(clean_types))
				H.update_inv_glasses(0)

		if(H.get_equipped_item(SLOT_ID_EAR_L) && washears)
			if(H.get_equipped_item(SLOT_ID_EAR_L).wash(clean_types))
				H.update_inv_ears(0)

		if(H.get_equipped_item(SLOT_ID_EAR_R) && washears)
			if(H.get_equipped_item(SLOT_ID_EAR_R).wash(clean_types))
				H.update_inv_ears(0)

		if(H.get_equipped_item(SLOT_ID_BELT))
			if(H.get_equipped_item(SLOT_ID_BELT).wash(clean_types))
				H.update_inv_belt(0)

	else
		if(get_equipped_item(SLOT_ID_MASK))						//if the mob is not human, it cleans the mask without asking for bitflags
			if(get_equipped_item(SLOT_ID_MASK).wash(clean_types))
				src.update_inv_wear_mask(0)

/mob/living/carbon/proc/food_preference(allergen_type) //RS edit
	if(!species) // carbon/brains have no species
		return FALSE

	if(allergen_type in species.food_preference)
		return species.food_preference_bonus
	return FALSE

/mob/living/carbon/vv_get_dropdown()
	. = ..()
	/*
	VV_DROPDOWN_OPTION("", "---------")
	VV_DROPDOWN_OPTION(VV_HK_MODIFY_BODYPART, "Modify bodypart")
	VV_DROPDOWN_OPTION(VV_HK_MODIFY_ORGANS, "Modify organs")
	VV_DROPDOWN_OPTION(VV_HK_MARTIAL_ART, "Give Martial Arts")
	VV_DROPDOWN_OPTION(VV_HK_GIVE_TRAUMA, "Give Brain Trauma")
	VV_DROPDOWN_OPTION(VV_HK_CURE_TRAUMA, "Cure Brain Traumas")
	*/

/**
 * This proc is used to determine whether or not the mob can handle touching a burning object.
 */
/mob/living/carbon/proc/can_touch_burning(atom/burning_atom, acid_power, acid_volume)
	// So people can take their own clothes off
	if((burning_atom == src) || (burning_atom.loc == src))
		return TRUE
	if(has_trait(src, TRAIT_RESISTHEAT) || has_trait(src, TRAIT_RESISTHEATHANDS))
		return TRUE
	if(get_equipped_item(SLOT_ID_GLOVES)?.max_heat_protection_temperature >= BURNING_ITEM_MINIMUM_TEMPERATURE)
		return TRUE
	for(var/obj/item/clothing/clothing in get_worn_clothing())
		if(clothing.max_heat_protection_temperature >= BURNING_ITEM_MINIMUM_TEMPERATURE && (clothing.heat_protection & HANDS) && (clothing.body_parts_covered & HANDS))
			return TRUE
	return FALSE

/mob/living/carbon
	var/datum/looping_sound/mob/cozyloop/cozyloop
	var/synth_reag_processing = TRUE
