


/mob/living/carbon/human/proc/hasnutriment()
	if (bloodstr.has_reagent(REAGENT_ID_NUTRIMENT, 30) || src.bloodstr.has_reagent(REAGENT_ID_PROTEIN, 15)) //protein needs half as much. For reference, a steak contains 9u protein.
		return TRUE
	else if (ingested.has_reagent(REAGENT_ID_NUTRIMENT, 60) || src.ingested.has_reagent(REAGENT_ID_PROTEIN, 30)) //try forcefeeding them, why not. Less effective.
		return TRUE
	else return FALSE

/mob/living/carbon/human/proc/quickcheckuninjured()
	if (is_injured() || current_pain()) //fails if they have any injury or pain
		return FALSE
	for (var/obj/item/organ/O in organs) //check their organs just in case they're being sneaky and somehow have organ damage but no health damage
		if (O.is_damaged() || O.status)
			return FALSE
	for (var/obj/item/organ/O in internal_organ_list()) //check their organs just in case they're being sneaky and somehow have organ damage but no health damage
		if (O.is_damaged() || O.status)
			return FALSE
	return TRUE

/mob/living/carbon/human/proc/getlightlevel() //easier than having the same code in like three places
	if(isturf(src.loc)) //else, there's considered to be no light
		var/turf/T = src.loc
		return T.get_lumcount() * 5
	else return 0

/mob/living/carbon/human/proc/bloodsuck()
	set name = "Partially Drain prey of blood"
	set desc = "Bites prey and drains them of a significant portion of blood, feeding you in the process. You may only do this once per minute."
	set category = VERB_CAT_ABILITIES_GENERAL


	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying || restrained() || src?.buckled_to())
		to_chat(src, "You cannot bite anyone in your current state!")
		return

	var/list/choices = list()
	for(var/mob/living/carbon/human/M in view(1,src))
		if(!istype(M,/mob/living/silicon) && Adjacent(M))
			choices += M


	open_request(src, /datum/prompt/choice, PROC_REF(bloodsuck_target_chosen), answerer = src, title = "Suck Blood", question = "Who do you wish to bite? Select yourself to bring up configuration for privacy and bleeding. Beware! Configuration resets on new round!", choices = choices, ask_flags = ASK_CONSCIOUS, timeout = 0)

/// A pop-up bloodsuck question (Yes/No); carries the target and the privacy answer.
/datum/prompt/choice/bloodsuck
	timeout = 0
	choices = list("Yes", "No")
	buttons = TRUE
	ask_flags = ASK_CONSCIOUS
	var/mob/living/carbon/human/target
	var/subtle

CAPABILITIES(/datum/prompt/choice/bloodsuck)
	ref_one(nameof(target), /mob/living/carbon/human)

/datum/prompt/choice/bloodsuck/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured = target
	rel_clear(src, nameof(target))
	rel_set(src, nameof(target), captured)

/datum/prompt/choice/bloodsuck/begin()
	if(QDELETED(target))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/bloodsuck/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(target) ? "target gone" : null

/mob/living/carbon/human/proc/bloodsuck_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/B = A.answer.value
	if(B == src) //We are using this to minimize the amount of pop-ups or buttons.
		open_request(src, /datum/prompt/choice, PROC_REF(bloodsuck_mode_chosen), answerer = src, title = "Configure Bloodsuck", question = "Choose your preferred control of blood sucking. You can only cause bleeding wounds with pop up and stance modes. Choosing stance prints controls to chat.", choices = list("always loud", "pop-up", "stance", "always subtle"), default = "always loud", timeout = 0)
		return
	if(!bloodsuck_can(B))
		return

	var/noise = TRUE
	var/bleed = FALSE
	switch(species.bloodsucker_controlmode)
		if("always subtle")
			noise = FALSE
		if("pop-up")
			open_request(src, /datum/prompt/choice/bloodsuck, PROC_REF(bloodsuck_popup_subtle), answerer = src, question = "Do you want to be subtle?", title = "Privacy", target = B)
			return
		if("stance")
			/*
			Logic is, out of combat mode, we are taking our time but it's pretty obvious..
			With Disarm, we rush the act, letting it keep bleeding
			Combat mode is self-evidently loud and bleedy
			Grab is subtle because we keep our prey tight and close.
			*/
			// The biter's own posture (state) picks the mode.
			if(attack_variant == ATTACK_VARIANT_DISARM)
				noise = FALSE
				bleed = TRUE
			else if(attack_variant == ATTACK_VARIANT_GRAB)
				noise = FALSE
			else if(combat_mode)
				bleed = TRUE
	bloodsuck_begin(B, noise, bleed)

/mob/living/carbon/human/proc/bloodsuck_mode_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mode = A.answer.value
	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.bloodsucker_controlmode = mode
	if(mode == "stance") //We are printing to chat for better readability
		to_chat(src, span_notice("You've chosen to use your stance for blood draining.\n Combat mode off - Loud, No Bleeding\n Disarm held - Subtle, Causes bleeding\n Grab held - Subtle, No Bleeding\n Combat mode on - Loud, Causes Bleeding"))

/mob/living/carbon/human/proc/bloodsuck_popup_subtle(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/bloodsuck/ask = A.request
	open_request(src, /datum/prompt/choice/bloodsuck, PROC_REF(bloodsuck_popup_answered), answerer = src, question = "Do you want your target to keep bleeding?", title = "Continue Bleeding", target = ask.target, subtle = A.answer.value)

/mob/living/carbon/human/proc/bloodsuck_popup_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/bloodsuck/ask = A.request
	var/mob/living/carbon/human/B = ask.target
	if(bloodsuck_can(B))
		bloodsuck_begin(B, ask.subtle != "Yes", A.answer.value == "Yes")

/// Whether we can bite B right now (next to us, not on cooldown, has blood); says why not.
/mob/living/carbon/human/proc/bloodsuck_can(mob/living/carbon/human/B)
	if(!COOLDOWN_FINISHED(src, last_special))
		to_chat(src, "You cannot suck blood so quickly in a row!")
		return FALSE
	if(!B || stat || !Adjacent(B))
		return FALSE
	if(has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying || restrained() || src?.buckled_to())
		to_chat(src, "You cannot bite in your current state.")
		return FALSE
	if(B.vessel.total_volume <= 0 || HAS_SYNTHETIC_BIOLOGY(B)) //Do they have any blood in the first place, and are they synthetic?
		to_chat(src, span_red("There appears to be no blood in this prey..."))
		return FALSE
	return TRUE

/mob/living/carbon/human/proc/bloodsuck_begin(mob/living/carbon/human/B, noise, bleed)
	COOLDOWN_START(src, last_special, 60 SECONDS)
	if(noise)
		act_message(src, B, others = span_infoplain(span_red(span_bold("%U% moves their head next to %T%'s neck, seemingly looking for something!"))))
	else
		act_message(src, B, others = span_infoplain(span_red(span_italics("%U% moves their head next to %T%'s neck, seemingly looking for something!"))), range = 1)

	if(bleed) //Due to possibility of missing/misclick and missing the bleeding cues, we are warning the scene members of BLEEDING being on
		to_chat(src, span_warning("This is going to cause [B] to keep bleeding!"))
		to_chat(B, span_danger("You are going to keep bleeding from this bite!"))

	task_start(/datum/task/timed/human_bloodsuck_human, src, B, noise = noise, bleed = bleed)

/datum/task/timed/human_bloodsuck_human
	duration = 30 SECONDS
	complete_proc = /mob/living/carbon/human/proc/bloodsuck_human_done
	var/noise
	var/bleed

/mob/living/carbon/human/proc/bloodsuck_human_done(datum/task/timed/human_bloodsuck_human/task)
	var/mob/living/carbon/human/B = task.target
	var/noise = task.noise
	var/bleed = task.bleed
	if(!Adjacent(B)) return
	if(noise)
		act_message(src, B, others = span_infoplain(span_red(span_bold("%U% suddenly extends their fangs and plunges them down into %T%'s neck!"))))
	else
		act_message(src, B, others = span_infoplain(span_red(span_italics("%U% suddenly extends their fangs and plunges them down into %T%'s neck!"))), range = 1)
	if(bleed)
		B.injure(INJURY_PIERCE, 10, BP_HEAD, src)
		var/obj/item/organ/external/E = B.get_organ(BP_HEAD)
		if(!(E.status & ORGAN_BLEEDING))
			E.set_status(E.status | ORGAN_BLEEDING) //If 10 points of piercing didn't make the organ bleed, we are making it bleed.


	else
		B.injure(INJURY_PIERCE, 5, BP_HEAD, src) //You're getting fangs pushed into your neck. What do you expect????


	if(!noise && !bleed) //If we're quiet and careful, there should be no blood to serve as evidence
		B.remove_blood(82) //Removing in one go since we dont want splatter
		adjust_nutrition(410) //We drink it all, not letting any go to waste!
	else //Otherwise, we're letting blood drop to the floor
		B.drip(80) //Remove enough blood to make them a bit woozy, but not take oxyloss.
		adjust_nutrition(400)
		after(B, 5 SECONDS, TYPE_PROC_REF(/mob/living/carbon/human, drip), with = list(1))
		after(B, 10 SECONDS, TYPE_PROC_REF(/mob/living/carbon/human, drip), with = list(1))

/// One stage of a drain through a grab (succubus_drain(), slime_feed()): five seconds holding
/// the target, then the next stage.
/datum/task/timed/grab_drain
	duration = 5 SECONDS
	complete_proc = /mob/living/carbon/human/proc/grab_drain_held
	cancel_proc = /mob/living/carbon/human/proc/grab_drain_interrupted
	var/obj/item/grab/grab
	var/stage
	/// A proc on the drainer: (target, stage) runs that stage and returns the next, or 0 when done.
	var/stage_proc
	/// The grab state the drain needs (0: any grab).
	var/needed_grab = 0
	/// "draining", "feeding": for the interruption message.
	var/what

/// Runs stage `stage` of a drain, and holds the grab for the next one.
/mob/living/carbon/human/proc/grab_drain_step(mob/living/carbon/human/T, obj/item/grab/G, stage, stage_proc, needed_grab, what)
	stage = call(src, stage_proc)(T, stage)
	if(!stage)
		return
	task_start(/datum/task/timed/grab_drain, src, T, grab = G, stage = stage, stage_proc = stage_proc, needed_grab = needed_grab, what = what)

/mob/living/carbon/human/proc/grab_drain_held(datum/task/timed/grab_drain/task)
	var/obj/item/grab/G = task.grab
	if(QDELETED(G) || (task.needed_grab ? G.state != task.needed_grab : !G.state))
		grab_drain_interrupted(task)
		return
	grab_drain_step(task.target, G, task.stage + 1, task.stage_proc, task.needed_grab, task.what)

/mob/living/carbon/human/proc/grab_drain_interrupted(datum/task/timed/grab_drain/task)
	to_chat(src, span_warning("Your [task.what] of [task.target] has been interrupted!"))
	absorbing_prey = FALSE

//Welcome to the adapted changeling absorb code.
/mob/living/carbon/human/proc/succubus_drain()
	set name = "Drain prey of nutrition"
	set desc = "Slowly drain prey of all the nutrition in their body, feeding you in the process. You may only do this to one person at a time."
	set category = VERB_CAT_ABILITIES_SUCCUBUS
	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.
	var/mob/living/carbon/human/C = src
	var/obj/item/grab/G = src.get_active_hand()
	if(!istype(G))
		to_chat(C, span_warning("You must be grabbing a creature in your active hand to absorb them."))
		return

	var/mob/living/carbon/human/T = G?.grab_target() // I must say, this is a quite ingenious way of doing it. Props to the original coders.
	if(!istype(T) || HAS_SYNTHETIC_BIOLOGY(T))
		to_chat(src, span_warning("\The [T] is not able to be drained."))
		return

	if(G.state != GRAB_NECK)
		to_chat(C, span_warning("You must have a tighter grip to drain this creature."))
		return

	if(C.absorbing_prey)
		to_chat(C, span_warning("You are already draining someone!"))
		return

	C.absorbing_prey = 1
	grab_drain_step(T, G, 1, PROC_REF(succubus_drain_stage), GRAB_NECK, "draining")

/// Runs stage `stage`; returns the stage to continue from, or 0 when done.
/mob/living/carbon/human/proc/succubus_drain_stage(mob/living/carbon/human/T, stage)
	var/mob/living/carbon/human/C = src
	switch(stage)
		if(1)
			to_chat(C, span_notice("You begin to drain [T]..."))
			to_chat(T, span_danger("An odd sensation flows through your body as [C] begins to drain you!"))
			C.set_nutrition((C.nutrition + (T.nutrition*0.05))) //Drain a small bit at first. 5% of the prey's nutrition.
			T.set_nutrition(T.nutrition*0.95)
		if(2)
			to_chat(C, span_notice("You feel stronger with every passing moment of draining [T]."))
			src.visible_message(span_danger("[C] seems to be doing something to [T], resulting in [T]'s body looking weaker with every passing moment!"))
			to_chat(T, span_danger("You feel weaker with every passing moment as [C] drains you!"))
			C.set_nutrition((C.nutrition + (T.nutrition*0.1)))
			T.set_nutrition(T.nutrition*0.9)
		if(3 to 99)
			C.set_nutrition((C.nutrition + (T.nutrition*0.1))) //Just keep draining them.
			T.set_nutrition(T.nutrition*0.9)
			T.status_adjust(STAT_BLURRY, 5) //Some eye blurry just to signify to the prey that they are still being drained. This'll stack up over time, leave the prey a bit more "weakened" after the deed is done.
			if(T.nutrition < 100 && stage < 99 && C.drain_finalized == 1)//Did they drop below 100 nutrition? If so, immediately jump to stage 99 so it can advance to 100.
				stage = 99
			if(C.drain_finalized != 1 && stage == 99) //Are they not finalizing and the stage hit 100? If so, go back to stage 3 until they finalize it.
				stage = 3
		if(100)
			C.set_nutrition((C.nutrition + T.nutrition))
			T.set_nutrition(0) //Completely drained of everything.
			var/damage_to_be_applied = T.get_endurance() //Enough pain to pass out.
			T.injure(INJURY_PAIN, damage_to_be_applied, null, src) //Knock em out.
			C.absorbing_prey = FALSE
			to_chat(C, span_notice("You have completely drained [T], causing them to pass out."))
			to_chat(T, span_danger("You feel weak, as if you have no control over your body whatsoever as [C] finishes draining you.!"))
			add_attack_logs(C,T,"Succubus drained")
			return 0
	return stage

/mob/living/carbon/human/proc/succubus_drain_lethal()
	set name = "Lethally drain prey" //Provide a warning that THIS WILL KILL YOUR PREY.
	set desc = "Slowly drain prey of all the nutrition in their body, feeding you in the process. Once prey run out of nutrition, you will begin to drain them lethally. You may only do this to one person at a time."
	set category = VERB_CAT_ABILITIES_SUCCUBUS
	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.

	var/obj/item/grab/G = src.get_active_hand()
	if(!istype(G))
		to_chat(src, span_warning("You must be grabbing a creature in your active hand to drain them."))
		return

	var/mob/living/carbon/human/T = G?.grab_target() // I must say, this is a quite ingenious way of doing it. Props to the original coders.
	if(!istype(T) || HAS_SYNTHETIC_BIOLOGY(T))
		to_chat(src, span_warning("\The [T] is not able to be drained."))
		return

	if(G.state != GRAB_NECK)
		to_chat(src, span_warning("You must have a tighter grip to drain this creature."))
		return

	if(absorbing_prey)
		to_chat(src, span_warning("You are already draining someone!"))
		return

	absorbing_prey = 1
	grab_drain_step(T, G, 1, PROC_REF(succubus_drain_lethal_stage), GRAB_NECK, "draining")

/// Runs stage `stage`; returns the stage to continue from, or 0 when done.
/mob/living/carbon/human/proc/succubus_drain_lethal_stage(mob/living/carbon/human/T, stage)
	switch(stage)
		if(1)
			if(T.stat == DEAD)
				to_chat(src, span_warning("[T] is dead and can not be drained.."))
				return 0
			to_chat(src, span_notice("You begin to drain [T]..."))
			to_chat(T, span_danger("An odd sensation flows through your body as [src] begins to drain you!"))
			set_nutrition((nutrition + (T.nutrition*0.05))) //Drain a small bit at first. 5% of the prey's nutrition.
			T.set_nutrition(T.nutrition*0.95)
		if(2)
			to_chat(src, span_notice("You feel stronger with every passing moment as you drain [T]."))
			act_message(src, T, others = span_danger("%U% seems to be doing something to %T%, resulting in %T%'s body looking weaker with every passing moment!"))
			to_chat(T, span_danger("You feel weaker with every passing moment as [src] drains you!"))
			set_nutrition((nutrition + (T.nutrition*0.1)))
			T.set_nutrition(T.nutrition*0.9)
		if(3 to 48) //Should be more than enough to get under 100.
			set_nutrition((nutrition + (T.nutrition*0.1))) //Just keep draining them.
			T.set_nutrition(T.nutrition*0.9)
			T.status_adjust(STAT_BLURRY, 5) //Some eye blurry just to signify to the prey that they are still being drained. This'll stack up over time, leave the prey a bit more "weakened" after the deed is done.
			if(T.nutrition < 100)//Did they drop below 100 nutrition? If so, do one last check then jump to stage 50 (Lethal!)
				stage = 49
		if(49)
			if(T.nutrition < 100)//Did they somehow not get drained below 100 nutrition yet? If not, go back to stage 3 and repeat until they get drained.
				stage = 3 //Otherwise, advance to stage 50 (Lethal draining.)
		if(50)
			if(!T.digestable)
				to_chat(src, span_danger("You feel invigorated as you completely drain [T] and begin to move onto draining them lethally before realizing they are too strong for you to do so!"))
				to_chat(T, span_danger("You feel completely drained as [src] finishes draining you and begins to move onto draining you lethally, but you are too strong for them to do so!"))
				set_nutrition((nutrition + T.nutrition))
				T.set_nutrition(0) //Completely drained of everything.
				var/damage_to_be_applied = T.get_endurance() //Enough pain to pass out.
				T.injure(INJURY_PAIN, damage_to_be_applied, null, src) //Knock em out.
				absorbing_prey = 0 //Clean this up before we return
				return 0
			to_chat(src, span_notice("You begin to drain [T] completely..."))
			to_chat(T, span_danger("An odd sensation flows through your body as you as [src] begins to drain you to dangerous levels!"))
		if(51 to 98)
			if(T.stat == DEAD)
				if(soulgem?.flag_check(SOULGEM_ACTIVE | SOULGEM_CATCHING_DRAIN, TRUE))
					soulgem.catch_mob(T)
				T.add_oxygen_debt(PHYSIOLOGY_DEBT_MAX, src) //Bit of fluff.
				absorbing_prey = 0
				to_chat(src, span_notice("You have completely drained [T], killing them."))
				to_chat(T, span_danger(span_giant("You feel... So... Weak...")))
				add_attack_logs(src,T,"Succubus drained (almost lethal)")
				return 0
			if(drain_finalized == 1 || T.injury_load(INJURY_CATEGORY_NEURAL) < 55) //Let's not kill them with this unless the drain is finalized. This will still stack up to 55, since 60 is lethal.
				T.injure(INJURY_NEURAL, 5, null, src) //Will kill them after a short bit!
			T.status_adjust(STAT_BLURRY, 20) //A lot of eye blurry just to signify to the prey that they are still being drained. This'll stack up over time, leave the prey a bit more "weakened" after the deed is done. More than non-lethal due to their lifeforce being sucked out
			set_nutrition((nutrition + 25)) //Assuming brain damage kills at 60, this gives 300 nutrition.
		if(99)
			if(drain_finalized != 1)
				stage = 51
		if(100) //They shouldn't  survive long enough to get here, but just in case.
			if(soulgem?.flag_check(SOULGEM_ACTIVE | SOULGEM_CATCHING_DRAIN, TRUE))
				soulgem.catch_mob(T)
			T.add_oxygen_debt(PHYSIOLOGY_DEBT_MAX, src) //Kill them.
			if(T.stat != DEAD)
				T.death()
			absorbing_prey = FALSE
			to_chat(src, span_notice("You have completely drained [T], killing them in the process."))
			to_chat(T, span_danger(span_massive("You... Feel... So... Weak...")))
			act_message(src, T, others = span_danger("%U% seems to finish whatever they were doing to %T%."))
			add_attack_logs(src,T,"Succubus drained (lethal)")
			return 0
	return stage

/mob/living/carbon/human/proc/slime_feed()
	set name = "Feed prey with self"
	set desc = "Slowly feed prey with your body, draining you in the process. You may only do this to one person at a time."
	set category = VERB_CAT_ABILITIES_VORE
	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.
	var/mob/living/carbon/human/C = src
	var/obj/item/grab/G = src.get_active_hand()
	if(!istype(G))
		to_chat(C, span_warning("You must be grabbing a creature in your active hand to feed them."))
		return

	var/mob/living/carbon/human/T = G?.grab_target() // I must say, this is a quite ingenious way of doing it. Props to the original coders.
	if(!istype(T))
		to_chat(src, span_warning("\The [T] is not able to be fed."))
		return

	if(!G.state) //This should never occur. But alright
		return

	if(C.absorbing_prey)
		to_chat(C, span_warning("You are already feeding someone!"))
		return

	C.absorbing_prey = 1
	grab_drain_step(T, G, 1, PROC_REF(slime_feed_stage), 0, "feeding")

/// Runs stage `stage`; returns the stage to continue from, or 0 when done.
/mob/living/carbon/human/proc/slime_feed_stage(mob/living/carbon/human/T, stage)
	var/mob/living/carbon/human/C = src
	switch(stage)
		if(1)
			to_chat(C, span_notice("You begin to feed [T]..."))
			to_chat(T, span_notice("An odd sensation flows through your body as [C] begins to feed you!"))
			T.set_nutrition((T.nutrition + (C.nutrition*0.05))) //Drain a small bit at first. 5% of the prey's nutrition.
			C.set_nutrition(C.nutrition*0.95)
		if(2)
			to_chat(C, span_notice("You feel weaker with every passing moment of feeding [T]."))
			src.visible_message(span_notice("[C] seems to be doing something to [T], resulting in [T]'s body looking stronger with every passing moment!"))
			to_chat(T, span_notice("You feel stronger with every passing moment as [C] feeds you!"))
			T.set_nutrition((T.nutrition + (C.nutrition*0.1)))
			C.set_nutrition(C.nutrition*0.90)
		if(3 to 99)
			T.set_nutrition((T.nutrition + (C.nutrition*0.1))) //Just keep draining them.
			C.set_nutrition(C.nutrition*0.9)
			T.status_adjust(STAT_BLURRY, 1) //Eating a slime's body is odd and will make your vision a bit blurry!
			if(C.nutrition < 100 && stage < 99 && C.drain_finalized == 1)//Did they drop below 100 nutrition? If so, immediately jump to stage 99 so it can advance to 100.
				stage = 99
			if(C.drain_finalized != 1 && stage == 99) //Are they not finalizing and the stage hit 100? If so, go back to stage 3 until they finalize it.
				stage = 3
		if(100)
			T.set_nutrition((T.nutrition + C.nutrition))
			C.set_nutrition(0) //Completely drained of everything.
			C.absorbing_prey = FALSE
			to_chat(C, span_danger("You have completely fed [T] every part of your body!"))
			to_chat(T, span_notice("You feel quite strong and well fed, as [C] finishes feeding \himself to you!"))
			add_attack_logs(C,T,"Slime fed")
			C.feed_grabbed_to_self_falling_nom(T,C) //Reused this proc instead of making a new one to cut down on code usage.
			return 0
	return stage

/mob/living/carbon/human/proc/succubus_drain_finalize()
	set name = "Drain/Feed Finalization"
	set desc = "Toggle to allow for draining to be prolonged. Turn this on to make it so prey will be knocked out/die while being drained, or you will feed yourself to the prey's selected stomach if you're feeding them. Can be toggled at any time."
	set category = VERB_CAT_ABILITIES_SUCCUBUS

	var/mob/living/carbon/human/C = src
	C.drain_finalized = !C.drain_finalized
	to_chat(C, span_notice("You will [C.drain_finalized?"now":"not"] finalize draining/feeding."))


//Test to see if we can shred a mob. Some child override needs to pass us a target. We'll return it if you can.
/mob/living/var/vore_shred_time = 45 SECONDS
/mob/living/proc/can_shred(mob/living/carbon/human/target)
	if(isnull(target) && shred_picks_target())
		shred_pick_target()
		return FALSE
	//Needs to have organs to be able to shred them.
	if(!istype(target))
		to_chat(src,span_warning("You can't shred that type of creature."))
		return FALSE
	//Needs to be capable (replace with incapacitated call?)
	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying || restrained() || src?.buckled_to())
		to_chat(src,span_warning("You cannot do that in your current state!"))
		return FALSE
	//Needs to be adjacent, at the very least.
	if(!Adjacent(target))
		to_chat(src,span_warning("You must be next to your target."))
		return FALSE
	//Cooldown on abilities
	if(!COOLDOWN_FINISHED(src, last_special))
		to_chat(src,span_warning("You can't perform an ability again so soon!"))
		return FALSE

	return target

//Human test for shreddability, returns the mob if they can be shredded.
/mob/living/carbon/human/vore_shred_time = 10 SECONDS
/mob/living/carbon/human/can_shred()
	//Humans need a grab
	var/obj/item/grab/G = get_active_hand()
	if(!istype(G))
		to_chat(src,span_warning("You have to have a very strong grip on someone first!"))
		return FALSE
	if(G.state != GRAB_NECK)
		to_chat(src,span_warning("You must have a tighter grip to severely damage this creature!"))
		return FALSE

	return ..(G?.grab_target())

//PAIs, borgs, and animals don't need a grab or anything: they pick someone next to them.
/mob/living/proc/shred_picks_target()
	return FALSE

/mob/living/silicon/pai/shred_picks_target()
	return TRUE

/mob/living/silicon/robot/shred_picks_target()
	return TRUE

/mob/living/simple_mob/shred_picks_target()
	return TRUE

/// Asks who to shred; the pick goes on in shred_target_picked().
/mob/living/proc/shred_pick_target()
	var/list/choices = list()
	for(var/mob/living/carbon/human/M in oviewers(1))
		choices += M
	if(!choices.len)
		to_chat(src,span_warning("There's nobody nearby to use this on."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(shred_target_picked), answerer = src, title = "Damage/Remove Prey's Organ", question = "Who do you wish to target?", choices = choices, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/proc/shred_target_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/T = A.answer.value
	if(can_shred(T) == T)
		shred_limb_begin(T)

/mob/living/proc/shred_limb()
	set name = "Damage/Remove Prey's Organ"
	set desc = "Severely damages prey's organ. If the limb is already severely damaged, it will be torn off."
	set category = VERB_CAT_ABILITIES_VORE

	//can_shred() will return a mob we can shred, if we can shred any.
	var/mob/living/carbon/human/T = can_shred()
	if(!istype(T))
		return //Silent, because can_shred does messages.

	shred_limb_begin(T)

/// Asks which organs to shred (and where to swallow them), then starts on T.
/mob/living/proc/shred_limb_begin(mob/living/carbon/human/T)
	var/datum/shred_limb_review/review = new
	rel_set(review, nameof(review.actor), src)
	rel_set(review, nameof(review.target), T)
	review.start()

/// Which external organ (confirmed when vital), which internal one if any (likewise), and a
/// belly to swallow it into if any. The actor stays conscious throughout.
/datum/shred_limb_review
	parent_type = /datum/prompt_workflow
	var/mob/living/actor
	var/mob/living/carbon/human/target
	var/obj/item/organ/external/T_ext
	var/obj/item/organ/internal/T_int
	var/obj/belly/B
	var/external_selected = FALSE
	var/internal_selected = FALSE

CAPABILITIES(/datum/shred_limb_review)
	ref_one(nameof(actor), /mob/living)
	ref_one(nameof(target), /mob/living/carbon/human)
	ref_one(nameof(T_ext), /obj/item/organ/external)
	ref_one(nameof(T_int), /obj/item/organ/internal)
	ref_one(nameof(B), /obj/belly)

/datum/prompt/choice/shred_limb
	timeout = 0

/datum/prompt/choice/shred_limb/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/datum/shred_limb_review/review = owner
	return review.why_not()

/datum/prompt/yes_no/shred_limb
	timeout = 0

/datum/prompt/yes_no/shred_limb/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/shred_limb_review/review = owner
	return review.why_not()

/datum/shred_limb_review/proc/why_not()
	if(QDELETED(actor) || QDELETED(target) || (external_selected && QDELETED(T_ext)) || (internal_selected && QDELETED(T_int)))
		return "gone"
	return actor.stat != CONSCIOUS ? "not conscious" : null

/datum/shred_limb_review/proc/start()
	if(why_not())
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(start_step))
	if(!result.ok)
		failed_step("start", result.error)

/datum/shred_limb_review/proc/start_step()
	open_request(src, /datum/prompt/choice/shred_limb, PROC_REF(external_chosen), answerer = actor, asker = actor, question = "What do you wish to severely damage?", choices = target.organs, title = "Organ Choice")

/datum/shred_limb_review/proc/failed_step(step, error)
	stack_trace("shred limb step [step]: [error]")
	retire()

/datum/shred_limb_review/proc/external_chosen(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(external_chosen_step), A)
	if(!result.ok)
		failed_step("external", result.error)

/datum/shred_limb_review/proc/external_chosen_step(datum/act/request/A)
	if(!A.answer)
		retire()
		return
	rel_set(src, nameof(T_ext), A.request.value)
	external_selected = TRUE
	if(QDELETED(T_ext))
		retire()
		return
	if(T_ext.vital)
		open_request(src, /datum/prompt/yes_no/shred_limb, PROC_REF(external_confirmed), answerer = actor, asker = actor, question = "Are you sure you wish to severely damage their [T_ext]? It will likely kill [target]...", title = "Shred Limb")
		return
	ask_internal()

/datum/shred_limb_review/proc/external_confirmed(datum/act/request/A)
	if(!A.answer || A.request.value != TRUE)
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(ask_internal))
	if(!result.ok)
		failed_step("external confirmation", result.error)

/datum/shred_limb_review/proc/ask_internal()
	var/list/T_organs = T_ext.held_organs()
	if(!length(T_organs))
		ask_belly()
		return
	open_request(src, /datum/prompt/choice/shred_limb, PROC_REF(internal_chosen), answerer = actor, asker = actor, question = "Do you wish to severely damage an internal organ, as well? If not, click 'cancel'", choices = T_organs, title = "Organ Choice")

/datum/shred_limb_review/proc/internal_chosen(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(internal_chosen_step), A)
	if(!result.ok)
		failed_step("internal", result.error)

/datum/shred_limb_review/proc/internal_chosen_step(datum/act/request/A)
	// Closing this optional question supplied an empty answer then rechecked the flow.
	if(why_not() || (!A.answer && !isnull(A.request.value)))
		retire()
		return
	rel_set(src, nameof(T_int), A.answer ? A.request.value : null)
	if(A.answer && QDELETED(T_int))
		retire()
		return
	internal_selected = !isnull(T_int)
	if(T_int?.vital)
		open_request(src, /datum/prompt/yes_no/shred_limb, PROC_REF(internal_confirmed), answerer = actor, asker = actor, question = "Are you sure you wish to severely damage their [T_int]? It will likely kill [target]...", title = "Shred Limb")
		return
	ask_belly()

/datum/shred_limb_review/proc/internal_confirmed(datum/act/request/A)
	if(!A.answer || A.request.value != TRUE)
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(ask_belly))
	if(!result.ok)
		failed_step("internal confirmation", result.error)

/datum/shred_limb_review/proc/ask_belly()
	open_request(src, /datum/prompt/choice/shred_limb, PROC_REF(belly_chosen), answerer = actor, asker = actor, question = "To where do you wish to swallow the organ if you tear if out? If not at all, click 'cancel'", choices = actor.vore_organs, title = "Organ Choice")

/datum/shred_limb_review/proc/belly_chosen(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(belly_chosen_step), A)
	if(!result.ok)
		failed_step("belly", result.error)

/datum/shred_limb_review/proc/belly_chosen_step(datum/act/request/A)
	if(why_not() || (!A.answer && !isnull(A.request.value)))
		retire()
		return
	rel_set(src, nameof(B), A.answer ? A.request.value : null)
	if(A.answer && QDELETED(B))
		retire()
		return
	actor.shred_limb_answered(target, T_ext, T_int, B)
	retire()

/mob/living/proc/shred_limb_answered(mob/living/carbon/human/T, obj/item/organ/external/T_ext, obj/item/organ/internal/T_int, obj/belly/B)
	if(can_shred(T) != T || T_ext.owner != T || (T_int && T_int.owner != T) || (B && B.owner != src))
		to_chat(src,span_warning("Looks like you lost your chance..."))
		return

	COOLDOWN_START(src, last_special, vore_shred_time)
	act_message(src, T, others = span_danger("%U% appears to be preparing to do something to %T%!")) //Let everyone know that bad times are ahead

	task_start(/datum/task/timed/living_shred_limb_living, src, T, duration = vore_shred_time, T_ext = T_ext, T_int = T_int, B = B)

/datum/task/timed/living_shred_limb_living
	complete_proc = /mob/living/proc/shred_limb_living_done
	var/obj/item/organ/external/T_ext
	var/obj/item/organ/internal/T_int
	var/obj/belly/B

/mob/living/proc/shred_limb_living_done(datum/task/timed/living_shred_limb_living/task)
	var/mob/living/carbon/human/T = task.target
	var/obj/item/organ/external/T_ext = task.T_ext
	var/obj/item/organ/internal/T_int = task.T_int
	var/obj/belly/B = task.B
	if(can_shred(T) != T)
		to_chat(src,span_warning("Looks like you lost your chance..."))
		return

// T.apply_body_effect(/datum/body_effect/gory_devourment, 10 SECONDS) // Don't need this because we don't do resleeving sickness.

	//Removing an internal organ
	if(T_int && T_int.damage >= 25) //Internal organ and it's been severely damaged
		T.injure(INJURY_CUT, 15, T_ext.organ_tag, src) //Damage the external organ they're going through.
		T_int.removed()
		if(B)
			T_int.forceMove(B) //Move to pred's gut
			act_message(src, T, others = span_danger("%U% severely damages [T_int.name] of %T%!"))
		else
			T_int.forceMove(T.loc)
			act_message(src, T, MSG_SELF(span_warning("You tear out %T%'s [T_int.name]!")), \
				MSG_OTHERS(span_danger("%U% severely damages [T_ext.name] of %T%, resulting in their [T_int.name] coming out!")))

	//Removing an external organ
	else if(!T_int && (T_ext.damage >= 25 || T_ext.get_trauma() >= 25))
		T_ext.droplimb(1,DROPLIMB_EDGE) //Clean cut so it doesn't kill the prey completely.

		//Is it groin/chest? You can't remove those.
		if(T_ext.cannot_amputate)
			T.injure(INJURY_CUT, 25, T_ext.organ_tag, src)
			act_message(src, T, others = span_danger("%U% severely damages %T%'s [T_ext.name]!"))
		else if(B)
			T_ext.forceMove(B)
			act_message(src, T, others = span_warning("%U% swallows %T%'s [T_ext.name] into their [lowertext(B.name)]!"))
		else
			T_ext.forceMove(T.loc)
			act_message(src, T, MSG_SELF(span_warning("You tear off %T%'s [T_ext.name]!")), MSG_OTHERS(span_warning("%U% tears off %T%'s [T_ext.name]!")))

	//Not targeting an internal organ w/ > 25 damage , and the limb doesn't have < 25 damage.
	else
		if(T_int)
			T.injure(INJURY_CUT, 25, T_int, src, affliction = /datum/affliction/lesion/laceration)
		T.injure(INJURY_CUT, 25, T_ext.organ_tag, src)
		act_message(src, T, others = span_danger("%U% severely damages %T%'s [T_ext.name]!"))

	add_attack_logs(src,T,"Shredded (hardvore)")

/mob/living/proc/shred_limb_temp()
	set name = "Damage/Remove Prey's Organ (beartrap)"
	set desc = "Severely damages prey's organ. If the limb is already severely damaged, it will be torn off."
	set category = VERB_CAT_ABILITIES_VORE
	shred_limb()

/mob/living/proc/flying_toggle()
	set name = "Toggle Flight"
	set desc = "While flying over open spaces, you will use up some nutrition. If you run out nutrition, you will fall."
	set category = VERB_CAT_ABILITIES_GENERAL

	var/mob/living/carbon/human/C = src
	if(!C.wing_style) //The species var isn't taken into account here, as it's only purpose is to give this proc to a person.
		to_chat(src, "You cannot fly without wings!!")
		return
	if(C.incapacitated(INCAPACITATION_ALL))
		to_chat(src, "You cannot fly in this state!")
		return
	if(C.nutrition < 25 && !C.flying) //Don't have any food in you?" You can't fly.
		to_chat(C, span_notice("You lack the nutrition to fly."))
		return

	C.flying = !C.flying
	update_floating()
	to_chat(C, span_notice("You have [C.flying?"started":"stopped"] flying."))

/mob/living/
	var/flight_vore = FALSE

/mob/living/proc/flying_vore_toggle()
	set name = "Toggle Flight Vore"
	set desc = "Allows you to engage in voracious misadventures while flying."
	set category = VERB_CAT_ABILITIES_VORE

	flight_vore = !flight_vore
	if(flight_vore)
		to_chat(src, "You have allowed for flight vore! Bumping into characters while flying will now trigger dropnoms! Unless prefs don't match.. then you will take a tumble!")
	else
		to_chat(src, "Flight vore disabled! You will no longer engage dropnoms while in flight.")

//Proc to stop inertial_drift. Exchange nutrition in order to stop gliding around.
/mob/living/proc/start_wings_hovering()
	set name = "Hover"
	set desc = "Allows you to stop gliding and hover. This will take a fair amount of nutrition to perform."
	set category = VERB_CAT_ABILITIES_GENERAL

	var/mob/living/carbon/human/C = src
	if(!C.wing_style) //The species var isn't taken into account here, as it's only purpose is to give this proc to a person.
		to_chat(src, "You don't have wings!")
		return
	if(!C.flying)
		to_chat(src, "You must be flying to hover!")
		return
	if(C.incapacitated(INCAPACITATION_ALL))
		to_chat(src, "You cannot hover in your current state!")
		return
	if(C.nutrition < 50 && !C.flying) //Don't have any food in you?" You can't hover, since it takes up 25 nutrition. And it's not 25 since we don't want them to immediately fall.
		to_chat(C, span_notice("You lack the nutrition to fly."))
		return
	if(C.anchored)
		to_chat(C, span_notice("You are already hovering and/or anchored in place!"))
		return

	if(!C.anchored && !C?.pulled_by_mob()) //Not currently anchored, and not pulled by anyone.
		C.set_anchored(TRUE) //This is the only way to stop the inertial_drift.
		C.adjust_nutrition(-25)
		update_floating()
		to_chat(C, span_notice("You hover in place."))
		after(C, 0.6 SECONDS, TYPE_PROC_REF(/atom/movable, set_anchored), with = list(FALSE)) //.6 seconds.
	else
		return

/mob/living/proc/toggle_pass_table()
	set name = "Toggle Agility" //Dunno a better name for this. You have to be pretty agile to hop over stuff!!!
	set desc = "Allows you to start/stop hopping over things such as hydroponics trays, tables, and railings."
	set category = VERB_CAT_ABILITIES_GENERAL
	pass_flags ^= PASSTABLE //I dunno what this fancy ^= is but Aronai gave it to me.
	to_chat(src, "You [pass_flags&PASSTABLE ? "will" : "will NOT"] move over tables/railings/trays!")

/mob/living/carbon/human/proc/toggle_eye_glow()
	set name = "Toggle Eye Glowing"
	set category = VERB_CAT_ABILITIES_GENERAL

	rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species.has_glowing_eyes = !species.has_glowing_eyes
	update_eyes()
	to_chat(src, "Your eyes [species.has_glowing_eyes ? "are now" : "are no longer"] glowing.")

MSG_DEF_SELF(human/cocoon_no_space, "You don't have enough space to spin a cocoon!")
MSG_DEF_SELF(human/cocoon_state, span_warning("You can't do that in your current state."))

/mob/living/carbon/human/proc/enter_cocoon()
	set name = "Spin Cocoon"
	set category = VERB_CAT_ABILITIES_WEAVER

	perform_op(src, src, "enter_cocoon", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)

/// Requirement: standing on a turf, not inside something.
/mob/living/carbon/human/proc/cocoon_has_space(datum/act/op/A)
	return (read_once(isturf(loc))) ? null : /datum/msg/req_failed

/// Requirement: awake, loose and rested (no tongue flicking while stunned).
/mob/living/carbon/human/proc/cocoon_fit(datum/act/op/A)
	return (!(src?.buckled_to() || stat || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || !read_once(COOLDOWN_FINISHED(src, last_special)))) ? null : /datum/msg/req_failed

/mob/living/carbon/human/proc/enter_cocoon_human_done(datum/act/op/A)
	var/obj/item/storage/vore_egg/bugcocoon/C = new(loc)
	forceMove(C)

	var/mob_holder_type = src.holder_type || /obj/item/holder
	C.w_class = src.size_multiplier * 4 //Egg size and weight scaled to match occupant.
	var/obj/item/holder/H = new mob_holder_type(C, src)
	C.max_storage_space = H.w_class
	C.icon_scale_x = 0.25 * C.w_class
	C.icon_scale_y = 0.25 * C.w_class
	C.update_transform()
	var/datum/tgui_module/appearance_changer/cocoon/V = new(src, src)
	V.tgui_interact(src)

/mob/living/carbon/human/proc/water_stealth()
	set name = "Dive under water / Resurface"
	set desc = "Dive under water, allowing for you to be stealthy and move faster."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(!COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 5 SECONDS) //No spamming!

	if(has_body_effect(/datum/body_effect/underwater_stealth))
		to_chat(src, "You resurface!")
		remove_body_effect(/datum/body_effect/underwater_stealth)
		return

	if(!isturf(loc)) //We have no turf.
		to_chat(src, "There is no water for you to dive into!")
		return

	if(istype(src.loc, /turf/simulated/floor/water))
		var/turf/simulated/floor/water/water_floor = src.loc
		if(water_floor.depth >= 1) //Is it deep enough?
			apply_body_effect(/datum/body_effect/underwater_stealth) //No duration. It'll remove itself when they exit the water!
			to_chat(src, "You dive into the water!")
			act_message(src, null, others = "%U% dives into the water!")
		else
			to_chat(src, "The water here is not deep enough to dive into!")
			return

	else
		to_chat(src, "There is no water for you to dive into!")
		return

/mob/living/carbon/human/proc/underwater_devour()
	set name = "Devour From Water"
	set desc = "Grab something in the water with you and devour them with your selected stomach."
	set category = VERB_CAT_ABILITIES_VORE

	if(!COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 5 SECONDS) //No spamming!

	if(stat == DEAD || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED))
		to_chat(src, span_notice("You cannot do that while in your current state."))
		return

	if(!(src.vore_selected))
		to_chat(src, span_notice("No selected belly found."))
		return


	if(!has_body_effect(/datum/body_effect/underwater_stealth))
		to_chat(src, "You must be underwater to do this!!")
		return

	var/list/targets = list() //Shameless copy and paste. If it ain't broke don't fix it!

	for(var/turf/T in range(1, src))
		if(istype(T, /turf/simulated/floor/water))
			for(var/mob/living/L in contents_of(T))
				if(L == src) //no eating yourself. 1984.
					continue
				if(L.devourable && L.can_be_drop_prey)
					targets += L

	if(!(targets.len))
		to_chat(src, span_notice("No eligible targets found."))
		return

	open_request(src, /datum/prompt/choice/victim/underwater, PROC_REF(underwater_devour_target_chosen), answerer = src, choices = targets)

/// Picking a victim for a vore ability. Re-checked on the answer: conscious.
/datum/prompt/choice/victim
	timeout = 0
	title = "Victim"
	question = "Please select a target."
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/victim/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	return null

/// Also re-checked: still stealthed underwater, and the target is still next to us.
/datum/prompt/choice/victim/underwater

/datum/prompt/choice/victim/underwater/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/L = answerer
	if(!L.has_body_effect(/datum/body_effect/underwater_stealth) || get_dist(L, value) > 1)
		return "lost the chance"
	return null

/mob/living/carbon/human/proc/underwater_devour_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/target = A.answer.value
	if(target && QDELETED(target))
		return
	to_chat(target, span_critical("Something begins to circle around you in the water!")) //Dun dun...
	var/starting_loc = target.loc

	task_timed(src, 5 SECONDS, target = target, receiver = src, on_done = PROC_REF(underwater_devour_human_done), done_args = list(target, starting_loc))

/mob/living/carbon/human/proc/underwater_devour_human_done(mob/living/target, starting_loc)
	if(target.loc != starting_loc)
		to_chat(target, span_warning("You got away from whatever that was..."))
		to_chat(src, span_notice("They got away."))
		return
	if(target?.buckled_to()) //how are you src?.buckled_to() in the water?!
		var/atom/movable/_tmp_buck_19 = target?.buckled_to()
		_tmp_buck_19.unbuckle_mob()
	act_message(target, src, MSG_SELF(span_vdanger("You are dragged below the water and feel yourself slipping directly into %T%'s [vore_selected.get_belly_name()]!")), \
		MSG_OTHERS(span_vwarning("%U% suddenly disappears, being dragged into the water!")))
	to_chat(src, span_vnotice("You successfully drag \the [target] into the water, slipping them into your [vore_selected.get_belly_name()]."))
	vore_selected.nom_atom(target)

/mob/living/carbon/human/proc/toggle_pain_module()
	set name = "Toggle pain simulation."
	set desc = "Turn on your pain simulation for that organic experience! Or turn it off for repairs, or if it's too much."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(synth_cosmetic_pain)
		to_chat(src, span_notice(" You turn off your pain simulators."))
	else
		to_chat(src, span_danger(" You turn on your pain simulators "))

	synth_cosmetic_pain = !synth_cosmetic_pain

//This is the 'long vore' ability. Also known as "Grab Prey with appendage" or "Long Predatorial Reach". Or simply "Tongue Vore"
//It involves projectiles (which means it can be VV'd onto a gun for shenanigans)
//It can also be recolored via the proc, which persists between rounds.

/mob/living/proc/long_vore() // Allows the user to tongue grab a creature in range. Made a /living proc so frogs can frog you.
	set name = "Grab Prey With Appendage"
	set category = VERB_CAT_ABILITIES_VORE
	set desc = "Grab a target with any of your appendages!"

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || !COOLDOWN_FINISHED(src, last_special) || is_incorporeal()) //No tongue flicking while status_units(STAT_STUNNED).
		to_chat(src, span_warning("You can't do that in your current state."))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS) //Anti-spam.

	if (!isliving(src))
		to_chat(src, span_warning("It doesn't work that way."))
		return

	open_request(src, /datum/prompt/choice, PROC_REF(long_vore_chosen), answerer = src, title = "Selection List", question = "Do you wish to change the color of your appendage, use it, or change its functionality?", choices = list("Use it", "Color", "Functionality"), buttons = TRUE, timeout = 0)

/mob/living/proc/long_vore_chosen(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.value)
		if("Color") //Easy way to set color so we don't bloat up the menu with even more buttons.
			open_request(src, /datum/prompt/color, PROC_REF(appendage_color_chosen), answerer = src, question = "Choose a color to set your appendage to!", default = appendage_color, timeout = 0)
		if("Functionality")
			open_request(src, /datum/prompt/choice, PROC_REF(appendage_setting_chosen), answerer = src, title = "Functionality Setting", question = "Choose if you want to be pulled to the target or pull them to you!", choices = list("Pull target to self", "Pull self to target"), buttons = TRUE, timeout = 0)
		if("Use it")
			var/list/targets = list() //IF IT IS NOT BROKEN. DO NOT FIX IT.
			for(var/mob/living/L in range(5, src))
				if(L == src) //no eating yourself. 1984.
					continue
				if(L.devourable && L.throw_vore && (L.can_be_drop_pred || L.can_be_drop_prey))
					targets += L
			if(!(targets.len))
				to_chat(src, span_notice("No eligible targets found."))
				return
			open_request(src, /datum/prompt/choice/victim, PROC_REF(long_vore_target_chosen), answerer = src, choices = targets)

/mob/living/proc/appendage_color_chosen(datum/act/request/A)
	if(!A.answer)
		return
	appendage_color = A.answer.value

/mob/living/proc/appendage_setting_chosen(datum/act/request/A)
	if(!A.answer)
		return
	appendage_alt_setting = (A.answer.value != "Pull target to self")

/mob/living/proc/long_vore_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/target = A.answer.value
	if(target && QDELETED(target))
		return
	if(!isliving(target)) //Safety.
		to_chat(src, span_warning("You need to select a living target!"))
		return
	if(has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || is_incorporeal())
		to_chat(src, span_warning("You can't do that in your current state."))
		return
	if (get_dist(src,target) >= 6)
		to_chat(src, span_warning("You need to be closer to do that."))
		return

	act_message(src, target, MSG_SELF(span_vnotice("You attempt to snatch up %T%!")), MSG_OTHERS(span_vnotice("%U% attempts to snatch up %T%!")))
	play_sfx(src, SFX_VORE_SUNESOUND_PRED_SCHLORP)

	//Code to shoot the beam here.
	var/obj/item/projectile/beam/appendage/appendage_attack = new /obj/item/projectile/beam/appendage(get_turf(loc))
	appendage_attack.launch_projectile(target, BP_TORSO, src) //Send it.
	COOLDOWN_START(src, last_special, 10 SECONDS) //Cooldown for successful strike.

/obj/item/projectile/beam/appendage //The tongue projecitle.
	name = "appendage"
	icon_state = "laser"
	nodamage = 1
	damage = 0
	eyeblur = 0
	can_miss = FALSE //Let's not miss our tongue!
	fire_sound = SFX_EFFECTS_SLIME_SQUISH
	hitsound = SFX_VORE_SUNESOUND_PRED_SCHLORP
	hitsound_wall = SFX_VORE_SUNESOUND_PRED_SCHLORP
	excavation_amount = 0
	hitscan_light_intensity = 0
	hitscan_light_range = 0
	muzzle_flash_intensity = 0
	muzzle_flash_range = 0
	impact_light_intensity = 0
	impact_light_range  = 0
	light_range = 0 //No your tongue can not glow...For now.
	light_power = 0
	light_on = 0 //NO LIGHT
	combustion = FALSE //No, your tongue can't set the room on fire.
	pass_flags = PASSTABLE

	muzzle_type = /obj/effect/projectile/muzzle/appendage
	tracer_type = /obj/effect/projectile/tracer/appendage
	impact_type = /obj/effect/projectile/impact/appendage

/obj/item/projectile/beam/appendage/generate_hitscan_tracers()
	if(firer) //This neat little code block allows for C O L O R A B L E tongues! Correction: 'Appendages'
		if(isliving(firer))
			var/mob/living/originator = firer
			color = originator.appendage_color
	..()

/obj/item/projectile/beam/appendage/on_hit(atom/target)
	if(target == firer) //NO EATING YOURSELF
		return
	if(isliving(target))
		var/mob/living/M = target
		var/throw_range = get_dist(firer,M)
		if(isliving(firer)) //Let's check for any alt settings. Such as: User selected to be thrown at target.
			var/mob/living/F = firer
			if(F.appendage_alt_setting == 1)
				F.throw_at(M, throw_range, firer.throw_speed, F) //Firer thrown at target.
				return
		if(istype(M))
			M.throw_at(firer, throw_range, M.throw_speed, firer) //Fun fact: living things have a throw_speed of 2.
			return
		else //Anything that isn't a /living
			return
	if(istype(target, /obj/item/)) //We hit an object? Pull it. This can only happen via admin shenanigans such as a gun being VV'd with this projectile.
		var/obj/item/hit_object = target
		if(hit_object.density || hit_object.anchored)
			if(isliving(firer))
				var/mob/living/originator = firer
				originator.status_at_least(STAT_WEAKENED, 2) //If you hit something dense or anchored, fall flat on your face.
				act_message(originator, null, MSG_SELF(span_warning("You trip over yourself and fall flat on your face!")), \
					MSG_OTHERS(span_warning("%U% trips over their self and falls flat on their face!")))
				play_sfx(originator, SFX_PUNCH, 0.5, extrarange = -1)
			return
		else
			hit_object.throw_at(firer, throw_range, hit_object.throw_speed, firer)
	if(istype(target, /turf/simulated/wall) || istype(target, /obj/machinery/door) || istype(target, /obj/structure/window)) //This can happen normally due to odd terrain. For some reason, it seems to not actually interact with walls.
		if(isliving(firer))
			var/mob/living/originator = firer
			originator.status_at_least(STAT_WEAKENED, 2) //Hit a wall? Whoops!
			act_message(originator, null, MSG_SELF(span_warning("You trip over yourself and fall flat on your face!")), \
				MSG_OTHERS(span_warning("%U% trips over their self and falls flat on their face!")))
			play_sfx(originator, SFX_PUNCH, 0.5, extrarange = -1)
			return
		else
			return



/obj/effect/projectile/muzzle/appendage
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "muzzle_appendage"
	light_range = 0
	light_power = 0
	light_color = "#FF0D00"

/obj/effect/projectile/tracer/appendage
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "appendage_beam"
	light_range = 0
	light_power = 0
	light_color = "#FF0D00" //Doesn't matter. Not used.

/obj/effect/projectile/impact/appendage
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "impact_appendage_combined"
	light_range = 0
	light_power = 0
	light_color = "#FF0D00"
//LONG VORE ABILITY END

/obj/item/gun/energy/gun/tongue //This is the 'tongue' gun for admin memery.
	name = "tongue"
	desc = "A tongue that can be used to grab things."
	icon = 'icons/mob/dogborg_vr.dmi'
	icon_state = "synthtongue"
	item_state = "gun"
	fire_delay = null
	force = 0
	fire_delay = 1 //Adminspawn. No delay.
	charge_cost = 0 //This is an adminspawn gun...No reason to force it to have a charge state.

	projectile_type = /obj/item/projectile/beam/appendage
	cell_type = /obj/item/cell/device/weapon/recharge
	battery_lock = 1
	modifystate = null


	firemodes = list(
		list(mode_name="vore", projectile_type=/obj/item/projectile/beam/appendage, modifystate=null, fire_sound=SFX_VORE_SUNESOUND_PRED_SCHLORP, charge_cost = 0),)

/// The look: always the tongue, whatever the charge.
/obj/item/gun/energy/gun/tongue/draw_charge_state(datum/look/look)
	look.state("synthtongue")

/obj/item/gun/energy/bfgtaser/tongue
	name = "9000-series Ball Tongue Taser"
	desc = "A banned riot control device."
	slot_flags = SLOT_BELT|SLOT_BACK
	projectile_type = /obj/item/projectile/bullet/BFGtaser/tongue
	fire_delay = 20
	w_class = ITEMSIZE_LARGE
	one_handed_penalty = 90 // The thing's heavy and huge.
	accuracy = 45
	charge_cost = 2400 //yes, this bad boy empties an entire weapon cell in one shot. What of it?

/obj/item/projectile/bullet/BFGtaser/tongue
	name = "tongue ball"
	hitsound = SFX_VORE_SUNESOUND_PRED_SCHLORP
	hitsound_wall = SFX_VORE_SUNESOUND_PRED_SCHLORP
	zaptype = /obj/item/projectile/beam/appendage

/mob/living/proc/target_lunge() //The leaper leap, but usable as an ability
	set name = "Lunge At Prey"
	set category = VERB_CAT_ABILITIES_VORE
	set desc = "Dive atop your prey and gobble them up!"

	var/leap_warmup = 1 SECOND //Easy to modify
	var/leap_sound = SFX_WEAPONS_SPIDERLUNGE

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || !COOLDOWN_FINISHED(src, last_special)) //No tongue flicking while status_units(STAT_STUNNED).
		to_chat(src, span_warning("You can't do that in your current state."))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS) //Anti-spam.

	if (!isliving(src))
		to_chat(src, span_warning("It doesn't work that way."))
		return

	else
		var/list/targets = list() //IF IT IS NOT BROKEN. DO NOT FIX IT.

		for(var/mob/living/L in range(5, src))
			if(!isliving(L)) //Don't eat anything that isn't mob/living. Failsafe.
				continue
			if(L == src) //no eating yourself. 1984.
				continue
			if(L.devourable && L.throw_vore && (L.can_be_drop_pred || L.can_be_drop_prey))
				targets += L

		if(!(targets.len))
			to_chat(src, span_notice("No eligible targets found."))
			return

		open_request(src, /datum/prompt/choice/victim/lunge, PROC_REF(target_lunge_chosen), answerer = src, choices = targets, leap_warmup = leap_warmup, leap_sound = leap_sound)

/// Carries the lunge's warm-up and sound.
/datum/prompt/choice/victim/lunge
	var/leap_warmup
	var/leap_sound

/mob/living/proc/target_lunge_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/victim/lunge/ask = A.request
	var/mob/living/target = A.answer.value
	if(target && QDELETED(target))
		return
	if(!isliving(target)) //Safety.
		to_chat(src, span_warning("You need to select a living target!"))
		return
	if(has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED))
		to_chat(src, span_warning("You can't do that in your current state."))
		return
	if (get_dist(src,target) >= 6)
		to_chat(src, span_warning("You need to be closer to do that."))
		return

	var/leap_warmup = ask.leap_warmup
	act_message(src, null, others = span_warning("%U% rears back, ready to lunge!"))
	to_chat(target, span_danger("\The [src] focuses on you!"))
	// Telegraph, since getting stunned suddenly feels bad.
	do_windup_animation(target, leap_warmup)
	after(src, leap_warmup, PROC_REF(target_lunge_leap), with = list(target, ask.leap_sound)) // For the telegraphing.

/mob/living/proc/target_lunge_leap(mob/living/target, leap_sound)
	if(!target || target.z != z)	//Make sure you haven't disappeared to somewhere we can't go
		return FALSE

	// Do the actual leap.
	set_status_flags(status_flags | LEAPING) // Lets us pass over everything.
	visible_message(span_critical("\The [src] leaps at \the [target]!"))
	throw_at(get_step(target, get_turf(src)), 7, 1, src)
	playsound(src, leap_sound, 75, 1)
	after(src, 0.5 SECONDS, PROC_REF(target_lunge_land), with = list(target), keeps_dead = TRUE) // For the throw to complete.

/mob/living/proc/target_lunge_land(mob/living/target)
	if(status_flags & LEAPING)
		set_status_flags(status_flags & ~LEAPING) // Revert special passage ability.

	if(target && Adjacent(target))	//We leapt at them but we didn't manage to hit them, let's see if we're next to them
		target.status_at_least(STAT_WEAKENED, 2)	//get knocked down, idiot


/mob/living/proc/injection() // Allows the user to inject reagents into others somehow, like stinging, or biting.
	set name = "Injection"
	set category = VERB_CAT_ABILITIES_GENERAL
	set desc = "Inject another being with something!"

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || !COOLDOWN_FINISHED(src, last_special)) //Epic copypasta from tongue grabbing.
		to_chat(src, span_warning("You can't do that in your current state."))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS) //Anti-spam.

	var/list/choices = list("Inject")

	if(LAZYLEN(trait_injection_reagents) > 1) //Should never happen, but who knows!
		choices += "Change reagent"
	else if(!trait_injection_selected)
		trait_injection_selected = LAZYACCESS(trait_injection_reagents, 1)

	choices += "Change amount"
	choices += "Change verb"
	choices += "Chemical Refresher"

	open_request(src, /datum/prompt/choice, PROC_REF(injection_chosen), answerer = src, title = "Selection List", question = "Do you wish to inject somebody, or adjust settings?", choices = choices, buttons = TRUE, timeout = 0)

/mob/living/proc/injection_reagent_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/reagent_choice = A.answer.value
	if(reagent_choice in trait_injection_reagents)
		trait_injection_selected = reagent_choice
	to_chat(src, span_notice("You prepare to inject [trait_injection_amount] units of [trait_injection_selected ? "[trait_injection_selected]" : "...nothing. Select a reagent before trying to inject anything."]"))

/mob/living/proc/injection_amount_chosen(datum/act/request/A)
	if(!A.answer)
		return
	trait_injection_amount = clamp(A.answer.value, 0, 5)
	to_chat(src, span_notice("You prepare to inject [trait_injection_amount] units of [trait_injection_selected ? "[trait_injection_selected]" : "...nothing. Select a reagent before trying to inject anything."]"))

/mob/living/proc/injection_verb_chosen(datum/act/request/A)
	if(!A.answer)
		return
	trait_injection_verb = A.answer.value
	to_chat(src, span_notice("You will [trait_injection_verb] your targets."))

/mob/living/proc/injection_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/choice = A.answer.value
	if(choice == "Change reagent")
		open_request(src, /datum/prompt/choice, PROC_REF(injection_reagent_chosen), answerer = src, title = "Select reagent", question = "Choose which reagent to inject!", choices = trait_injection_reagents || list(), timeout = 0)
		return
	if(choice == "Change amount")
		open_request(src, /datum/prompt/number, PROC_REF(injection_amount_chosen), answerer = src, timeout = 0, question = "How much of the reagent do you want to inject? (Up to 5 units) (Can select 0 for a bite that doesn't inject venom!)", title = "How much?", default = trait_injection_amount, max_value = 5, min_value = 0)
		return
	if(choice == "Change verb")
		open_request(src, /datum/prompt/text, PROC_REF(injection_verb_chosen), answerer = src, timeout = 0, question = "Choose the percieved manner of injection, such as 'bite' or 'sting', don't be misleading or abusive. This will show up in game as ('X' manages to 'Verb' 'Y'. Example: X manages to bite Y.)", title = "How are you injecting?", default = trait_injection_verb, max_len = 60) //Whoaa there cowboy don't put a novel in there.
		return
	if(choice == "Chemical Refresher")
		var/output = {"<HR>
					"} + span_bold("Options for venoms") + {"<BR>
					<BR>
					"} + span_bold("Size Chemicals") + {"<BR>
					Microcillin: Will make someone shrink. <br>
					Macrocillin: Will make someone grow. <br>
					Normalcillin: Will make someone normal size. <br>
					Note: 1 unit = 100% size diff. 0.01 unit = 1% size diff. <br>
					Note: Normacillin stops at 100%  size. <br>
					<br>
					"} + span_bold("Gender Chemicals") + {"<BR>
					Androrovir: Will transform someone's sex to male. <br>
					Gynorovir: Will transform someone's sex to female. <br>
					Androgynorovir: Will transform someone's sex to plural. <br>
					<br>
					"} + span_bold("Special Chemicals") + {"<BR>
					Stoxin: Will make someone drowsy. <br>
					Rainbow Toxin: Will make someone see rainbows. <br>
					Paralysis Toxin: Will make someone paralyzed. <br>
					Numbing Enzyme: Will make someone unable to feel pain. <br>
					Pain Enzyme: Will make someone feel amplified pain. <br>
					<br>
					"} + span_bold("Side Notes") + {"<BR>
					You can select a value of 0 to inject nothing! <br>
					Overdose threshold for most chemicals is 30 units. <br>
					Exceptions to OD is: (Numbing Enzyme:20)<br>
					You can also bite synthetics, but due to how synths work, they won't have anything injected into them.
					<br>
					"}

		// structured TGUI AdminReport.
		dq_admin_report_html(src, "Chemical Refresher", output)
		return
	else
		var/list/targets = list() //IF IT IS NOT BROKEN. DO NOT FIX IT. AND KEEP COPYPASTING IT  (Pointing Rick Dalton: "That's my code!" ~CL)

		for(var/mob/living/carbon/L in living_mobs(1, TRUE)) //Noncarbons don't even process reagents so don't bother listing others.
			if(!istype(L, /mob/living/carbon))
				continue
			if(L == src) //no getting high off your own supply, get a nif or something, nerd.
				continue
			if(!L.resizable && (trait_injection_selected == REAGENT_ID_MACROCILLIN || trait_injection_selected == REAGENT_ID_MICROCILLIN || trait_injection_selected == REAGENT_ID_NORMALCILLIN)) // If you're using a size reagent, ignore those with pref conflicts.
				continue
			if(!L.allow_spontaneous_tf && (trait_injection_selected == REAGENT_ID_ANDROROVIR || trait_injection_selected == REAGENT_ID_GYNOROVIR || trait_injection_selected == REAGENT_ID_ANDROGYNOROVIR)) // If you're using a TF reagent, ignore those with pref conflicts.
				continue
			targets += L

		if(!(targets.len))
			to_chat(src, span_notice("No eligible targets found."))
			return

		open_request(src, /datum/prompt/choice/victim, PROC_REF(injection_target_chosen), answerer = src, choices = targets)

/mob/living/proc/injection_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/target = A.answer.value
	if(target && QDELETED(target))
		return
	if(has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || !Adjacent(target))
		to_chat(src, span_warning("You can't do that in your current state."))
		return
	if(!istype(target, /mob/living/carbon)) //Safety.
		to_chat(src, span_warning("That won't work on that kind of creature! (Only works on crew/monkeys)"))
		return

	var/synth = 0
	if(HAS_SYNTHETIC_BIOLOGY(target))
		synth = 1

	if(!trait_injection_selected)
		to_chat(src, span_notice("You need to select a reagent."))
		return

	if(!trait_injection_verb)
		to_chat(src, span_notice("Somehow, you forgot your means of injecting. (Select a verb!)"))
		return

	act_message(src, target, others = span_warning("%U% is preparing to [trait_injection_verb] %T%!"))
	task_timed(src, 5 SECONDS, target = target, receiver = src, on_done = PROC_REF(injection_living_done), done_args = list(target, synth))

/mob/living/proc/injection_living_done(mob/living/target, synth)
	add_attack_logs(src,target,"Injection trait ([trait_injection_selected], [trait_injection_amount])")
	if(target.reagents && (trait_injection_amount > 0) && !synth)
		target.reagents.add_reagent(trait_injection_selected, trait_injection_amount)
	var/ourmsg = "[src] manages to [trait_injection_verb] [target] "
	switch(zone_sel.selecting)
		if(BP_HEAD)
			ourmsg += "on the head!"
		if(BP_TORSO)
			ourmsg += "on the chest!"
		if(BP_GROIN)
			ourmsg += "on the groin!"
		if(BP_R_ARM, BP_L_ARM)
			ourmsg += "on the arm!"
		if(BP_R_HAND, BP_L_HAND)
			ourmsg += "on the hand!"
		if(BP_R_LEG, BP_L_LEG)
			ourmsg += "on the leg!"
		if(BP_R_FOOT, BP_L_FOOT)
			ourmsg += "on the foot!"
		if("mouth")
			ourmsg += "on the mouth!"
		if("eyes")
			ourmsg += "on the eyes!"
	visible_message(span_warning(ourmsg))

//succuby bite is back baby
/mob/living/proc/succubus_bite()
	set name = "Inject Prey"
	set desc = "Bite prey and inject them with various toxins."
	set category = VERB_CAT_ABILITIES_SUCCUBUS

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(!ishuman(src))
		return //If you're not a human you don't have permission to do this.

	var/mob/living/carbon/human/C = src

	var/obj/item/grab/G = src.get_active_hand()

	if(!istype(G))
		to_chat(C, span_warning("You must be grabbing a creature in your active hand to bite them."))
		return

	var/mob/living/carbon/human/T = G?.grab_target()

	if(!istype(T) || HAS_SYNTHETIC_BIOLOGY(T))
		to_chat(src, span_warning("\The [T] is not able to be bitten."))
		return

	if(G.state != GRAB_NECK)
		to_chat(C, span_warning("You must have a tighter grip to bite this creature."))
		return

	COOLDOWN_START(src, last_special, 60 SECONDS)
	open_request(src, /datum/prompt/choice/succubus_bite, PROC_REF(succubus_bite_chosen), answerer = src, grab = G, target = T)

/// Re-checked on the answer: conscious, and still holding the target by the neck.
/datum/prompt/choice/succubus_bite
	timeout = 0
	title = "Reagent"
	question = "What do you wish to inject?"
	choices = list(REAGENT_APHRODISIAC, "Numbing", "Paralyzing")
	ask_flags = ASK_CONSCIOUS
	var/obj/item/grab/grab
	var/mob/living/carbon/human/target

CAPABILITIES(/datum/prompt/choice/succubus_bite)
	ref_one(nameof(grab), /obj/item/grab)
	ref_one(nameof(target), /mob/living/carbon/human)

/datum/prompt/choice/succubus_bite/prepare(datum/act/A)
	..()
	var/obj/item/grab/captured_grab = grab
	var/mob/living/carbon/human/captured_target = target
	rel_clear(src, nameof(grab))
	rel_clear(src, nameof(target))
	rel_set(src, nameof(grab), captured_grab)
	rel_set(src, nameof(target), captured_target)

/datum/prompt/choice/succubus_bite/begin()
	if(QDELETED(grab) || QDELETED(target))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/succubus_bite/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(grab) || QDELETED(target))
		return "gone"
	return answerer.get_active_hand() != grab || grab.grab_target() != target || grab.state != GRAB_NECK ? "lost grip" : null

/mob/living/proc/succubus_bite_chosen(datum/act/request/A)
	var/datum/prompt/choice/succubus_bite/ask = A.request
	if(!A.answer)
		if(!isnull(ask.value) && ask.last_error == "lost grip")
			to_chat(src, span_warning("You must have a tighter grip to bite this creature."))
		return
	var/mob/living/carbon/human/T = ask.target
	var/choice = A.answer.value
	act_message(src, T, others = span_bolddanger("%U% moves their head next to %T%'s neck, seemingly looking for something!"))

	task_timed(src, 30 SECONDS, target = T, receiver = src, on_done = PROC_REF(succubus_bite_living_done), done_args = list(T, choice))

/mob/living/proc/succubus_bite_living_done(mob/living/carbon/human/T, choice)
	if(choice == REAGENT_APHRODISIAC)
		src.show_message(span_warning("You sink your fangs into [T] and inject your aphrodisiac!"))
		act_message(src, T, others = span_red("%U% sinks their fangs into %T%!"))
		T.bloodstr.add_reagent(REAGENT_ID_APHRODIAC_FLUID,100)
		return 0
	else if(choice == "Numbing")
		src.show_message(span_warning("You sink your fangs into [T] and inject your poison!"))
		act_message(src, T, others = span_red("%U% sinks their fangs into %T%!"))
		T.bloodstr.add_reagent(REAGENT_ID_NUMBING_FLUID,20) //Poisons should work when more units are injected
	else if(choice == "Paralyzing")
		src.show_message(span_warning("You sink your fangs into [T] and inject your poison!"))
		act_message(src, T, others = span_red("%U% sinks their fangs into %T%!"))
		T.bloodstr.add_reagent(REAGENT_ID_PARALYZE_FLUID,20) //Poisons should work when more units are injected
	else
		return //Should never happen

/datum/reagent/succubi_aphrodisiac
	name = REAGENT_APHRODISIAC
	id = REAGENT_ID_APHRODIAC_FLUID
	description = "A unknown liquid, it smells sweet"
	metabolism = REM * 0.8
	color = "#8A0829"
	scannable = SCANNABLE_ADVANCED
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/succubi_aphrodisiac/affect_blood(mob/living/carbon/M, alien, removed)
	if(prob(3))
		M.show_message(span_warning("You feel funny, and fall in love with the person in front of you"))
		M.say(pick("!blushes", "!moans", "!giggles", "!turns visibly red")) //using mob say so we dont have to define this dumb one time use emote that equates to just blushing -shark
		//M.charmed() //TODO
	return

/datum/reagent/succubi_numbing //Using numbing_enzyme instead.
	name = REAGENT_NUMBING_FLUID
	id = REAGENT_ID_NUMBING_FLUID
	description = "A unknown liquid, it doesn't smell"
	metabolism = REM * 0.5
	color = "#41029B"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/succubi_numbing/affect_blood(mob/living/carbon/M, alien, removed)


	M.status_at_least(STAT_BLURRY, 10)
	M.status_at_least(STAT_WEAKENED, 2)
	M.status_at_least(STAT_DROWSY, 20)
	if(prob(7))
		M.show_message(span_warning("You start to feel weakened, your body seems heavy."))
	return

/datum/reagent/succubi_paralize
	name = REAGENT_PARALYZE_FLUID
	id = REAGENT_ID_PARALYZE_FLUID
	description = "A unknown liquid, it doesn't smell"
	metabolism= REM * 0.5
	color = "#41029B"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/succubi_paralize/affect_blood(mob/living/carbon/M, alien, removed) //will first keep it like that.  lets see what it changes. if nothing, than I will rework the effect again

	M.status_at_least(STAT_WEAKENED, 20)
	M.status_at_least(STAT_BLURRY, 10)
	if(prob(10))
		M.show_message(span_warning("You lose sensation of your body."))
	return

/mob/living/proc/mobegglaying()
	set name = "Egg laying"
	set desc = "you can lay Eggs"
	set category = VERB_CAT_ABILITIES_GENERAL

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 60 SECONDS)
	open_request(src, /datum/prompt/choice, PROC_REF(mobegglaying_chosen), answerer = src, title = "Egg Option", question = "What do you want to do?", choices = list("Make a Egg", "lay your Eggs"), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/proc/mobegglaying_chosen(datum/act/request/A)
	if(!A.answer)
		return
	task_timed(src, 30 SECONDS, target = src, receiver = src, on_done = PROC_REF(mobegglaying_living_done), done_args = list(src, A.answer.value))

/mob/living/proc/mobegglaying_living_done(mob/living/carbon/human/C, choice)
	if(choice == "Make a Egg" && eggs > 5)
		src.show_message(span_warning("Your Belly is full of Eggs you cant have more!!"))
		return 0
	else if(choice == "Make a Egg")
		src.show_message(span_warning("You feel your belly bulging a bit, you made an egg!"))
		C.adjust_nutrition(-(150))
		eggs += 1
		return 0
	else if(choice == "lay your Eggs" && eggs > 0)
		act_message(src, null, others = span_infoplain(span_white("%U% freezes and vissibly tries to squat down")))

		while(eggs > 0)
			src.show_message(span_warning("You lay a egg!"))
			eggs--
			var/obj/item/reagent_containers/food/snacks/egg/E = new(get_turf(src))
			E.pixel_x = rand(-6,6)
			E.pixel_y = rand(-6,6)
		return
	else
		src.visible_message(span_warning("you dont have any eggs!"))
		return //Should never happen

/mob/living/proc/insect_sting()
	set name = "Insect Sting"
	set desc = "Sting a target and inject a small amount of toxin"
	set category = VERB_CAT_ABILITIES_GENERAL

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	var/list/victims = list()
	for(var/mob/living/carbon/C in oview(1))
		victims += C
	open_request(src, /datum/prompt/choice/insect_sting, PROC_REF(insect_sting_chosen), answerer = src, choices = victims)

/// Re-checked on the answer: conscious, off cooldown, and next to the target.
/datum/prompt/choice/insect_sting
	timeout = 0
	title = "Target"
	question = "Who will we sting?"
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/insect_sting/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/mob/living/L = answerer
	if(!COOLDOWN_FINISHED(L, last_special) || !L.Adjacent(value))
		return "can't reach"
	return null

/mob/living/proc/insect_sting_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/T = A.answer.value
	if(T && QDELETED(T))
		return
	if(HAS_SYNTHETIC_BIOLOGY(T))
		to_chat(src, span_notice("We are unable to pierce the outer shell of [T]."))
		return

	to_chat(src, span_notice("You jab your stinger into [T]."))
	to_chat(T, span_danger("You feel a stabbing pain as you are stung!"))
	act_message(src, T, others = span_infoplain(span_red("%U% sinks their stinger into %T%!")))
	T.bloodstr.add_reagent(REAGENT_ID_CONDENSEDCAPSAICINV,3)
	COOLDOWN_START(src, last_special, (5 SECONDS)) // Many little jabs instead of one big one

/mob/living/proc/absorb_devour()
	if(!absorbed || !isbelly(loc))
		return
	if(!isliving(loc.loc))
		return
	var/mob/living/pred = loc.loc
	var/obj/belly/belly = loc
	var/list/targets = list()
	for(var/mob/living/potentialtarget in range(1, pred))
		if(!isliving(potentialtarget)) //Don't eat anything that isn't mob/living. Failsafe.
			continue
		if(potentialtarget == pred)
			continue
		if(potentialtarget.devourable)
			targets += potentialtarget
	if(!(targets.len))
		to_chat(src, span_notice("No eligible targets found."))
		return
	open_request(src, /datum/prompt/choice/victim/absorbed, PROC_REF(absorb_devour_chosen), answerer = src, choices = targets, belly = belly)

/// An absorbed prey picking a victim for its pred's belly. Re-checked on the answer: still
/// absorbed in that belly, inside a living pred. (No consciousness check.)
/datum/prompt/choice/victim/absorbed
	ask_flags = NONE
	var/obj/belly/belly

CAPABILITIES(/datum/prompt/choice/victim/absorbed)
	ref_one(nameof(belly), /obj/belly)

/datum/prompt/choice/victim/absorbed/prepare(datum/act/A)
	..()
	var/obj/belly/captured = belly
	rel_clear(src, nameof(belly))
	rel_set(src, nameof(belly), captured)

/datum/prompt/choice/victim/absorbed/begin()
	if(QDELETED(belly))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/victim/absorbed/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/L = answerer
	if(QDELETED(belly) || !L.absorbed || L.loc != belly || !isliving(belly.loc))
		return "not absorbed"
	return null

/mob/living/proc/absorb_devour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/target = A.answer.value
	if(target && QDELETED(target))
		return
	var/mob/living/pred = loc.loc
	var/obj/belly/belly = loc
	if(!isliving(target)) //Safety.
		to_chat(src, span_warning("You need to select a living target!"))
		return
	if (get_dist(src,target) >= 2)
		to_chat(src, span_warning("You need to be closer to do that."))
		return
	act_message(target, pred, MSG_SELF(span_vwarning("%T%'s [belly] threatens to [lowertext(belly.vore_verb)] you!")), \
		MSG_OTHERS(span_vnotice("%T%'s [belly] seems interested in %U%.")))
	to_chat(pred, span_vnotice("Your [belly] tries to [lowertext(belly.vore_verb)] \the [target].")) //people who want this will often be unaware pred players, so I'm making the warning a bit smaller text for them
	to_chat(pred, span_vwarning("You look for a chance to [lowertext(belly.vore_verb)] \the [target]."))
	var/starting_loc = target.loc
	task_start(/datum/task/timed/living_absorb_devour_living, src, target, pred = pred, belly = belly, starting_loc = starting_loc)

/datum/task/timed/living_absorb_devour_living
	duration = 5 SECONDS
	complete_proc = /mob/living/proc/absorb_devour_living_done
	var/mob/living/pred
	var/obj/belly/belly
	var/starting_loc

/mob/living/proc/absorb_devour_living_done(datum/task/timed/living_absorb_devour_living/task)
	var/mob/living/pred = task.pred
	var/obj/belly/belly = task.belly
	var/mob/living/target = task.target
	var/starting_loc = task.starting_loc
	if(target.loc != starting_loc)
		to_chat(src, span_notice("\The [target] is no longer within reach."))
		return
	if(target?.buckled_to())
		var/atom/movable/_tmp_buck_20 = target?.buckled_to()
		_tmp_buck_20.unbuckle_mob()
	to_chat(src, span_vwarning("You manage to [lowertext(belly.vore_verb)] \the [target]!"))
	to_chat(pred, span_vnotice("Your [belly] manages to [lowertext(belly.vore_verb)] \the [target]."))
	to_chat(target, span_vwarning("You are [lowertext(belly.vore_verb)]ed by \The [pred]'s [belly]!"))
	return pred.begin_instant_nom(src, target, pred, belly, FALSE)

/mob/living/proc/name_change_verb()
	set name = "Change Name"
	set desc = "Change your name. Notifies admins."
	set category = VERB_CAT_ABILITIES_SUPERPOWER

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	open_request(src, /datum/prompt/text, PROC_REF(name_change_entered), answerer = src, title = "Name change", question = "What would you like your name to become?", default = name, max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/mob/living/proc/name_change_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/chosen_name = A.answer.value
	if(!length(chosen_name) || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, (5 SECONDS)) //don't spam check the global list pls
	for(var/mob/checkplayer in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(checkplayer == src)
			continue
		if(!checkplayer.client) //no client, no problem
			continue
		if(checkplayer.name == chosen_name)
			if(checkplayer.client.prefs.read_preference(/datum/preference/toggle/human/resleeve_lock)) // resleeve_lock migrated
				to_chat(src, span_notice("\The [checkplayer]'s preferences forbid you from impersonating them."))
				log_and_message_admins("[key_name(src)] attempted to impersonate [key_name(checkplayer)], but preferences prevented it.", src)
				return
			log_and_message_admins("[key_name(src)] impersonated [key_name(checkplayer)]!", src)

	log_and_message_admins("[key_name(src)] set their name to [chosen_name]", src)
	if(dna)
		dna.real_name = chosen_name
	real_name = chosen_name
	name = chosen_name
