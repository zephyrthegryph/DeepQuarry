/mob/proc/flash_pain()
	flick("pain",pain)

/mob/var/list/pain_stored = list()
/mob/var/last_pain_message = ""
/mob/var/next_pain_time = 0
/mob/var/multilimb_pain_time = 0 // Global pain cooldown exists to prevent spam for multi-limb damage


// message is the custom message to be displayed
// power decides how much painkillers will stop the message
// force means it ignores anti-spam timer
/mob/living/carbon/proc/custom_pain(message, power, force)
	if((!message || stat || !can_feel_pain() || factor(BF_ANALGESIA) > power) && !synth_cosmetic_pain)
		return 0
	message = span_danger("[message]")
	if(power >= 50)
		message = span_large("[message]")

	// Anti message spam checks
	// If multiple limbs are injured, cooldown is ignored to print all injuries until all limbs are iterated over
	if(client?.prefs?.read_preference(/datum/preference/toggle/pain_frequency))
		switch(power)
			if(0 to 5)
				force = 0
			if(6 to 20)
				force = prob(1)
		if(force || (message != last_pain_message) || (world.time >= next_pain_time))
			switch(power)
				if(0 to 5)
					next_pain_time = world.time + 300 SECONDS
					multilimb_pain_time = world.time + 1 MINUTE
				if(6 to 20)
					next_pain_time = world.time + clamp((100 - power) SECONDS, 80 SECONDS, 95 SECONDS)
					multilimb_pain_time = world.time + clamp((100 - power) SECONDS, 80 SECONDS, 95 SECONDS)
				if(21 to INFINITY)
					next_pain_time = world.time + clamp((200 - power) SECONDS, 100 SECONDS, 3 MINUTES)
					multilimb_pain_time = world.time + clamp((200 - power) SECONDS, 100 SECONDS, 3 MINUTES)
			last_pain_message = message
			to_chat(src,message)
			// Emote in pain for custom pain, too
			if(prob(power / 10) && !isbelly(loc)) // No pain noises inside bellies.
				emote("pain")

	else if(force || (message != last_pain_message) || (world.time >= next_pain_time))
		last_pain_message = message
		to_chat(src,message)
		next_pain_time = world.time + (100 - power)
		multilimb_pain_time = world.time + (100 - power)
		// Emote in pain for custom pain, too
		if(prob(power / 10) && !isbelly(loc)) // No pain noises inside bellies.
			emote("pain")

/datum/life_system/pain
	name = "pain"
	wake_on = LIFE_WAKE_ON_BODY
	phase = LIFE_PHASE_TAIL
	order = 190
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/// Pain messages from limbs and organs.
/datum/life_system/pain/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	if(self.stat)
		return

	if(!self.can_feel_pain() && !self.synth_cosmetic_pain)
		return

	if(world.time < self.multilimb_pain_time) //prevents spam in case of multi-limb injuries.
		return
	var/maxdam = 0
	var/obj/item/organ/external/damaged_organ = null
	for(var/obj/item/organ/external/E in self.organs)
		if(!E.organ_can_feel_pain() && !self.synth_cosmetic_pain) continue
		var/dam = E.get_damage()
		// make the choice of the organ depend on damage,
		// but also sometimes use one of the less damaged ones
		if(dam > maxdam && (maxdam == 0 || prob(70)) )
			damaged_organ = E
			maxdam = dam
			if(ishuman(self))
				var/mob/living/carbon/human/H = self
				maxdam *= H.species.trauma_mod // end
	if(damaged_organ && self.factor(BF_ANALGESIA) < maxdam)
		if(maxdam > 10 && self.has_status(EFFECT_PARALYZED))
			self.status_adjust(EFFECT_PARALYZED, -round(maxdam/10))
		if(maxdam > 50 && prob(maxdam / 5))
			self.drop_item()
		var/burning = damaged_organ.get_burn() > damaged_organ.get_trauma()
		var/msg
		switch(maxdam)
			if(1 to 10)
				msg =  "Your [damaged_organ.name] [burning ? "burns" : "hurts"]."
			if(11 to 90)
				self.flash_weak_pain()
				msg = span_normal("Your [damaged_organ.name] [burning ? "burns" : "hurts"] badly!")
			if(91 to 10000)
				self.flash_pain()
				msg = span_large("OH GOD! Your [damaged_organ.name] is [burning ? "on fire" : "hurting terribly"]!")
		self.custom_pain(msg, maxdam, prob(10))

	// Damage to internal organs hurts a lot.
	for(var/obj/item/organ/I in self.internal_organs)
		if((I.status & ORGAN_DEAD) || I.robotic >= ORGAN_ROBOT) continue
		if(I.damage > 2) if(prob(2))
			var/obj/item/organ/external/parent = self.get_organ(I.parent_organ)
			self.custom_pain("You feel a sharp pain in your [parent.name]", 50)

	if(prob(2))
		var/toxic = self.injury_load(INJURY_CATEGORY_TOXIC)
		switch(toxic)
			if(1 to 10)
				self.custom_pain("Your body stings slightly.", toxic)
			if(11 to 30)
				self.custom_pain("Your body hurts a little.", toxic)
			if(31 to 60)
				self.custom_pain("Your whole body hurts badly.", toxic)
			if(61 to INFINITY)
				self.custom_pain("Your body aches all over, it's driving you mad.", toxic)
